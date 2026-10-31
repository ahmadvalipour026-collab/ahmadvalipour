import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const VAPID_PUBLIC_KEY = Deno.env.get("VAPID_PUBLIC_KEY")!;
    const VAPID_PRIVATE_KEY = Deno.env.get("VAPID_PRIVATE_KEY")!;
    if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !VAPID_PUBLIC_KEY || !VAPID_PRIVATE_KEY) {
      return json({ error: "Push service is not configured" }, 500);
    }

    const { token, event, title, body } = await req.json();
    if (!token || typeof token !== "string" || !/^[0-9a-f-]{36}$/i.test(token)) {
      return json({ error: "Unauthorized" }, 401);
    }
    const allowed = new Set(["announcement_created", "poll_created"]);
    if (!allowed.has(event)) return json({ error: "Unsupported event" }, 400);

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: session, error: sessionError } = await supabase
      .from("sessions").select("account_id,expires_at,revoked_at")
      .eq("token", token).maybeSingle();
    if (sessionError || !session || session.revoked_at || new Date(session.expires_at).getTime() <= Date.now()) {
      return json({ error: "Unauthorized" }, 401);
    }

    const { data: actor, error: actorError } = await supabase
      .from("accounts").select("id,building_id,is_admin,is_active,unit_no,full_name")
      .eq("id", session.account_id).maybeSingle();
    if (actorError || !actor || !actor.is_active || actor.building_id == null) {
      return json({ error: "Unauthorized" }, 401);
    }

    if (!actor.is_admin) {
      return json({ error: "Forbidden" }, 403);
    }

    const safeTitle = String(title || "اعلان ساختمان").slice(0, 120);
    const safeBody = String(body || "یک اعلان جدید دریافت کردید.").slice(0, 500);

    // Verify that the requested notification corresponds to a real recent database record.
    if (event === "poll_created") {
      const pollTitle = safeTitle.startsWith("نظرسنجی جدید: ")
        ? safeTitle.slice("نظرسنجی جدید: ".length) : "";
      if (!pollTitle) return json({ error: "Invalid poll notification" }, 400);
      const { data: poll, error: pollError } = await supabase
        .from("building_polls")
        .select("id")
        .eq("building_id", actor.building_id)
        .eq("created_by", actor.id)
        .eq("title", pollTitle)
        .eq("description", safeBody)
        .gte("created_at", new Date(Date.now() - 5 * 60 * 1000).toISOString())
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (pollError) throw pollError;
      if (!poll) return json({ error: "Poll record not found" }, 403);
    } else if (event === "announcement_created") {
      const { data: announcement, error: announcementError } = await supabase
        .from("announcements")
        .select("id")
        .eq("title", safeTitle)
        .eq("content", safeBody)
        .gte("created_at", new Date(Date.now() - 5 * 60 * 1000).toISOString())
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      if (announcementError) throw announcementError;
      if (!announcement) return json({ error: "Announcement record not found" }, 403);
    }

    let accountQuery = supabase.from("accounts").select("id")
      .eq("building_id", actor.building_id).eq("is_active", true)
      .neq("id", actor.id);


    const { data: recipients, error: recipientsError } = await accountQuery;
    if (recipientsError) throw recipientsError;
    const recipientIds = (recipients || []).map((a: {id:string}) => a.id);
    if (!recipientIds.length) return json({ ok: true, sent: 0 });

    const { data: subscriptions, error: subsError } = await supabase
      .from("push_subscriptions")
      .select("id,account_id,endpoint,p256dh,auth")
      .eq("building_id", actor.building_id)
      .in("account_id", recipientIds);
    if (subsError) throw subsError;
    if (!subscriptions?.length) return json({ ok: true, sent: 0 });

    webpush.setVapidDetails("mailto:admin@ahmadvalipour.ir", VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);
    const payload = JSON.stringify({
      title: safeTitle,
      body: safeBody,
      url: "https://ahmadvalipour.ir/",
      tag: event + "-" + Date.now(),
    });

    let sent = 0;
    await Promise.all(subscriptions.map(async (sub: any) => {
      try {
        await webpush.sendNotification(
          { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
          payload,
          { TTL: 60 * 60 * 12 }
        );
        sent++;
      } catch (error) {
        const status = (error as any)?.statusCode;
        if (status === 404 || status === 410) {
          await supabase.from("push_subscriptions").delete().eq("id", sub.id);
        } else {
          console.error("Push delivery failed", status || error);
        }
      }
    }));

    return json({ ok: true, sent });
  } catch (error) {
    console.error(error);
    return json({ error: "Push delivery failed" }, 500);
  }
});

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
