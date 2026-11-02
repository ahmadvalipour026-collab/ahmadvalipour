import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const ALLOWED_ORIGINS = new Set(["https://ahmadvalipour.ir"]);
const ALLOWED_EVENTS = new Set(["announcement_created", "poll_created"]);
const MAX_BODY_BYTES = 8 * 1024;
const MAX_CONCURRENT_SENDS = 20;

Deno.serve(async (req) => {
  const origin = req.headers.get("origin");
  if (!origin || !ALLOWED_ORIGINS.has(origin)) {
    return json({ error: "Origin not allowed" }, 403);
  }

  const corsHeaders = {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Max-Age": "600",
    "Vary": "Origin",
  };

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405, corsHeaders);
  }

  try {
    if (!req.headers.get("content-type")?.toLowerCase().includes("application/json")) {
      return json({ error: "Content-Type must be application/json" }, 415, corsHeaders);
    }

    const contentLength = Number(req.headers.get("content-length") || 0);
    if (contentLength > MAX_BODY_BYTES) {
      return json({ error: "Request too large" }, 413, corsHeaders);
    }
    const rawBody = await req.text();
    if (new TextEncoder().encode(rawBody).byteLength > MAX_BODY_BYTES) {
      return json({ error: "Request too large" }, 413, corsHeaders);
    }

    let input: unknown;
    try {
      input = JSON.parse(rawBody);
    } catch {
      return json({ error: "Invalid JSON" }, 400, corsHeaders);
    }
    if (!input || typeof input !== "object" || Array.isArray(input)) {
      return json({ error: "Invalid request body" }, 400, corsHeaders);
    }

    const { token, event, title, body } = input as Record<string, unknown>;
    if (typeof token !== "string" ||
        !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(token)) {
      return json({ error: "Unauthorized" }, 401, corsHeaders);
    }
    if (typeof event !== "string" || !ALLOWED_EVENTS.has(event)) {
      return json({ error: "Unsupported event" }, 400, corsHeaders);
    }
    if ((title !== undefined && typeof title !== "string") ||
        (body !== undefined && typeof body !== "string")) {
      return json({ error: "Invalid notification content" }, 400, corsHeaders);
    }

    const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
    const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const VAPID_PUBLIC_KEY = Deno.env.get("VAPID_PUBLIC_KEY");
    const VAPID_PRIVATE_KEY = Deno.env.get("VAPID_PRIVATE_KEY");
    if (!SUPABASE_URL || !SERVICE_ROLE_KEY || !VAPID_PUBLIC_KEY || !VAPID_PRIVATE_KEY) {
      return json({ error: "Push service is not configured" }, 500, corsHeaders);
    }

    const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: session, error: sessionError } = await supabase
      .from("sessions")
      .select("account_id,expires_at,revoked_at")
      .eq("token", token)
      .maybeSingle();

    if (sessionError || !session || session.revoked_at ||
        !session.expires_at || new Date(session.expires_at).getTime() <= Date.now()) {
      return json({ error: "Unauthorized" }, 401, corsHeaders);
    }

    const { data: actor, error: actorError } = await supabase
      .from("accounts")
      .select("id,building_id,is_admin,is_active")
      .eq("id", session.account_id)
      .maybeSingle();

    if (actorError || !actor || actor.is_active !== true || actor.building_id == null) {
      return json({ error: "Unauthorized" }, 401, corsHeaders);
    }
    if (actor.is_admin !== true) {
      return json({ error: "Forbidden" }, 403, corsHeaders);
    }

    const safeTitle = (title as string | undefined)?.trim().slice(0, 120) || "اعلان ساختمان";
    const safeBody = (body as string | undefined)?.trim().slice(0, 500) || "یک اعلان جدید دریافت کردید.";

    // A notification may only be sent after its matching record exists in this building.
    if (event === "poll_created") {
      const pollTitle = safeTitle.startsWith("نظرسنجی جدید: ")
        ? safeTitle.slice("نظرسنجی جدید: ".length).trim()
        : "";
      if (!pollTitle) return json({ error: "Invalid poll notification" }, 400, corsHeaders);

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
      if (!poll) return json({ error: "Poll record not found" }, 403, corsHeaders);
    } else {
      const { data: announcement, error: announcementError } = await supabase
        .from("announcements")
        .select("id")
        .eq("building_id", actor.building_id)
        .eq("title", safeTitle)
        .eq("content", safeBody)
        .gte("created_at", new Date(Date.now() - 5 * 60 * 1000).toISOString())
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (announcementError) throw announcementError;
      if (!announcement) return json({ error: "Announcement record not found" }, 403, corsHeaders);
    }

    const { data: recipients, error: recipientsError } = await supabase
      .from("accounts")
      .select("id")
      .eq("building_id", actor.building_id)
      .eq("is_active", true)
      .neq("id", actor.id);

    if (recipientsError) throw recipientsError;
    const recipientIds = (recipients || []).map((account: { id: string }) => account.id);
    if (!recipientIds.length) return json({ ok: true, sent: 0 }, 200, corsHeaders);

    const { data: subscriptions, error: subsError } = await supabase
      .from("push_subscriptions")
      .select("id,account_id,endpoint,p256dh,auth")
      .eq("building_id", actor.building_id)
      .in("account_id", recipientIds);

    if (subsError) throw subsError;
    if (!subscriptions?.length) return json({ ok: true, sent: 0 }, 200, corsHeaders);

    webpush.setVapidDetails("mailto:admin@ahmadvalipour.ir", VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY);
    const payload = JSON.stringify({
      title: safeTitle,
      body: safeBody,
      url: "/",
      tag: event + "-" + Date.now(),
    });

    let sent = 0;
    for (let i = 0; i < subscriptions.length; i += MAX_CONCURRENT_SENDS) {
      const batch = subscriptions.slice(i, i + MAX_CONCURRENT_SENDS);
      const results = await Promise.all(batch.map(async (sub: {
        id: string; endpoint: string; p256dh: string; auth: string;
      }) => {
        try {
          await webpush.sendNotification(
            { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
            payload,
            { TTL: 60 * 60 * 12 },
          );
          return { sent: true, expiredId: null as string | null };
        } catch (error) {
          const status = (error as { statusCode?: number })?.statusCode;
          if (status === 404 || status === 410) return { sent: false, expiredId: sub.id };
          console.error("Push delivery failed", status || "unknown error");
          return { sent: false, expiredId: null as string | null };
        }
      }));

      sent += results.filter((result) => result.sent).length;
      const expiredIds = results.map((result) => result.expiredId).filter((id): id is string => !!id);
      if (expiredIds.length) {
        const { error } = await supabase.from("push_subscriptions").delete().in("id", expiredIds);
        if (error) console.error("Failed to clean expired push subscriptions");
      }
    }

    return json({ ok: true, sent }, 200, corsHeaders);
  } catch (error) {
    console.error("Push delivery request failed", error instanceof Error ? error.message : "unknown error");
    return json({ error: "Push delivery failed" }, 500, corsHeaders);
  }
});

function json(data: unknown, status = 200, corsHeaders: Record<string, string> = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}
