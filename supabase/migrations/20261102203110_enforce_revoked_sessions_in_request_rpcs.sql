-- These legacy functions queried sessions directly and omitted revoked_at/is_active checks.
-- Keep their existing response shape while enforcing immediate session revocation and suspension.
CREATE OR REPLACE FUNCTION public.app_get_requests(p_token text)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  v_acc RECORD;
  v_result JSON;
BEGIN
  SELECT a.* INTO v_acc
  FROM public.accounts a
  JOIN public.sessions s ON s.account_id = a.id
  WHERE s.token::text = p_token
    AND s.expires_at > now()
    AND s.revoked_at IS NULL
    AND a.is_active = true;

  IF v_acc IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  IF v_acc.is_admin THEN
    SELECT json_agg(row_to_json(t)) INTO v_result
    FROM (
      SELECT r.*, a.full_name, a.unit_no
      FROM public.resident_requests r
      LEFT JOIN public.accounts a ON a.id = r.account_id
      ORDER BY r.created_at DESC
    ) t;
  ELSE
    SELECT json_agg(row_to_json(t)) INTO v_result
    FROM (
      SELECT r.*, a.full_name, a.unit_no
      FROM public.resident_requests r
      LEFT JOIN public.accounts a ON a.id = r.account_id
      WHERE r.account_id = v_acc.id
      ORDER BY r.created_at DESC
    ) t;
  END IF;

  RETURN coalesce(v_result, '[]'::json);
END;
$function$;

CREATE OR REPLACE FUNCTION public.app_admin_reply_request(
  p_token text,
  p_id bigint,
  p_status text,
  p_reply text
)
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  v_acc RECORD;
  v_req RECORD;
BEGIN
  SELECT a.* INTO v_acc
  FROM public.accounts a
  JOIN public.sessions s ON s.account_id = a.id
  WHERE s.token::text = p_token
    AND s.expires_at > now()
    AND s.revoked_at IS NULL
    AND a.is_active = true;

  IF v_acc IS NULL OR NOT v_acc.is_admin THEN
    RAISE EXCEPTION 'AUTH_REQUIRED: دسترسی مدیر لازم است';
  END IF;

  IF p_status NOT IN ('pending', 'reviewing', 'done') THEN
    RAISE EXCEPTION 'وضعیت نامعتبر است';
  END IF;

  UPDATE public.resident_requests
  SET status = p_status,
      admin_reply = p_reply,
      replied_at = now(),
      replied_by = v_acc.username
  WHERE id = p_id
  RETURNING * INTO v_req;

  IF v_req IS NULL THEN
    RAISE EXCEPTION 'درخواست یافت نشد';
  END IF;

  RETURN json_build_object('ok', true, 'request', row_to_json(v_req));
END;
$function$;
