-- Security and integrity hardening for the legacy single-building PWA.
-- Applied to Supabase project hpgvgoehkcpjmdbfmnse as migration
-- 20261102202636_security_and_integrity_hardening.

-- The old recovery endpoint authenticated users using only username + phone.
-- This is not a secure identity proof (no OTP); disable until a verified flow exists.
REVOKE EXECUTE ON FUNCTION public.app_reset_password(text, text, text) FROM PUBLIC, anon, authenticated;

-- Internal helpers are only called from owner-executed SECURITY DEFINER routines.
REVOKE EXECUTE ON FUNCTION public.bm_auth(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.bm_admin(uuid) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.bm_account_month_due(uuid, integer) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.bm_account_total_due(uuid, integer, integer) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.bm_unit_month_due(integer, integer) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.bm_total_due(integer, integer, integer) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.bm_exempt(integer, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.bm_setting(text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.bm_is_duplicate(integer, integer, integer, integer, text, text, text, bigint, bigint) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.rls_auto_enable() FROM PUBLIC, anon, authenticated;

-- Password reset returns a temporary password once to the administrator,
-- revokes existing sessions, and never writes the password into audit logs.
CREATE OR REPLACE FUNCTION public.app_admin_reset_password(p_token uuid, p_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  me public.accounts;
  target_acc public.accounts;
  v_new_pass text;
BEGIN
  me := public.bm_admin(p_token);

  SELECT * INTO target_acc
  FROM public.accounts
  WHERE id = p_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'حساب پیدا نشد';
  END IF;

  v_new_pass := lpad((floor(random() * 90000000)::bigint + 10000000)::text, 8, '0');

  UPDATE public.accounts
  SET password_hash = extensions.crypt(v_new_pass, extensions.gen_salt('bf')),
      must_change_password = true,
      failed_attempts = 0,
      locked_until = NULL,
      updated_at = now()
  WHERE id = p_id;

  UPDATE public.sessions
  SET revoked_at = now()
  WHERE account_id = p_id AND revoked_at IS NULL;

  INSERT INTO public.activity_logs
    (account_id, unit_no, full_name, action, details, actor_id, building_id)
  VALUES
    (p_id, target_acc.unit_no, target_acc.full_name, 'ریست رمز',
     'مدیر رمز عبور را بازنشانی کرد', me.id, target_acc.building_id);

  RETURN v_new_pass;
END
$function$;

-- Enforce the application's documented username/password format at the DB boundary.
-- Remove the insecure default password for newly-created accounts.
CREATE OR REPLACE FUNCTION public.app_admin_save_account(
  p_token uuid,
  p_id uuid,
  p_unit_no integer,
  p_username text,
  p_full_name text,
  p_phone text,
  p_occupancy text,
  p_is_primary boolean DEFAULT true,
  p_is_active boolean DEFAULT true,
  p_new_password text DEFAULT NULL,
  p_start_ym integer DEFAULT 140406
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'public', 'extensions'
AS $function$
DECLARE
  v_admin boolean;
  v_existing_id uuid;
  v_current_username text;
  v_password_hash text;
BEGIN
  SELECT a.is_admin INTO v_admin
  FROM public.accounts a
  JOIN public.sessions s ON s.account_id = a.id
  WHERE s.token = p_token
    AND s.expires_at > now()
    AND s.revoked_at IS NULL
    AND a.is_active = true;

  IF NOT coalesce(v_admin, false) THEN
    RAISE EXCEPTION 'AUTH_REQUIRED: دسترسی مدیر لازم است';
  END IF;

  IF p_username IS NULL OR btrim(p_username) = '' OR p_username !~ '^[A-Za-z0-9._-]{3,40}$' THEN
    RAISE EXCEPTION 'نام کاربری باید انگلیسی و بین ۳ تا ۴۰ نویسه باشد';
  END IF;

  IF p_new_password IS NOT NULL AND p_new_password <> '' AND p_new_password !~ '^[0-9]{4,8}$' THEN
    RAISE EXCEPTION 'رمز عبور باید فقط شامل ۴ تا ۸ رقم باشد';
  END IF;

  IF p_id IS NULL AND (p_new_password IS NULL OR p_new_password = '') THEN
    RAISE EXCEPTION 'برای ساخت حساب جدید، رمز اولیه الزامی است';
  END IF;

  IF p_id IS NOT NULL THEN
    SELECT username INTO v_current_username
    FROM public.accounts WHERE id = p_id;
  END IF;

  IF p_id IS NULL OR v_current_username IS DISTINCT FROM p_username THEN
    SELECT id INTO v_existing_id
    FROM public.accounts
    WHERE lower(username) = lower(p_username)
      AND (p_id IS NULL OR id <> p_id)
    LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
      RAISE EXCEPTION 'این نام کاربری قبلاً استفاده شده است';
    END IF;
  END IF;

  IF p_new_password IS NOT NULL AND p_new_password <> '' THEN
    v_password_hash := extensions.crypt(p_new_password, extensions.gen_salt('bf'));
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.accounts (
      username, password_hash, unit_no, full_name, phone,
      occupancy, is_admin, is_primary, is_active,
      must_change_password, failed_attempts, start_ym, created_at, updated_at
    ) VALUES (
      p_username, v_password_hash, p_unit_no, p_full_name, p_phone,
      p_occupancy, false, coalesce(p_is_primary, true), coalesce(p_is_active, true),
      true, 0, p_start_ym, now(), now()
    );
  ELSE
    UPDATE public.accounts
    SET username = p_username,
        unit_no = p_unit_no,
        full_name = p_full_name,
        phone = p_phone,
        occupancy = p_occupancy,
        is_primary = coalesce(p_is_primary, is_primary),
        is_active = coalesce(p_is_active, is_active),
        start_ym = coalesce(p_start_ym, start_ym),
        password_hash = coalesce(v_password_hash, password_hash),
        must_change_password = CASE WHEN v_password_hash IS NOT NULL THEN true ELSE must_change_password END,
        failed_attempts = CASE WHEN v_password_hash IS NOT NULL THEN 0 ELSE failed_attempts END,
        locked_until = CASE WHEN v_password_hash IS NOT NULL THEN NULL ELSE locked_until END,
        updated_at = now()
    WHERE id = p_id;

    IF NOT FOUND THEN
      RAISE EXCEPTION 'حساب موردنظر پیدا نشد';
    END IF;

    IF coalesce(p_is_active, true) = false THEN
      UPDATE public.sessions
      SET revoked_at = now()
      WHERE account_id = p_id AND revoked_at IS NULL;
    END IF;
  END IF;
END
$function$;

-- Pin search_path for functions that previously inherited the caller's path.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS signature
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proconfig IS NULL
  LOOP
    EXECUTE format('ALTER FUNCTION %s SET search_path TO pg_catalog, public, extensions', r.signature);
  END LOOP;
END
$$;

-- Cover the foreign keys identified by Supabase's performance advisor.
CREATE INDEX IF NOT EXISTS idx_accounts_building_id ON public.accounts(building_id);
CREATE INDEX IF NOT EXISTS idx_accounts_unit_no ON public.accounts(unit_no);
CREATE INDEX IF NOT EXISTS idx_activity_logs_account_id ON public.activity_logs(account_id);
CREATE INDEX IF NOT EXISTS idx_building_poll_votes_account_id ON public.building_poll_votes(account_id);
CREATE INDEX IF NOT EXISTS idx_building_poll_votes_option_poll ON public.building_poll_votes(option_id, poll_id);
CREATE INDEX IF NOT EXISTS idx_building_polls_created_by ON public.building_polls(created_by);
CREATE INDEX IF NOT EXISTS idx_payment_requests_account_id ON public.payment_requests(account_id);
CREATE INDEX IF NOT EXISTS idx_payment_requests_building_id ON public.payment_requests(building_id);
CREATE INDEX IF NOT EXISTS idx_payment_requests_reviewed_by ON public.payment_requests(reviewed_by);
CREATE INDEX IF NOT EXISTS idx_payment_requests_unit_no ON public.payment_requests(unit_no);
CREATE INDEX IF NOT EXISTS idx_receipt_lines_receipt_id ON public.receipt_lines(receipt_id);
CREATE INDEX IF NOT EXISTS idx_resident_requests_account_id ON public.resident_requests(account_id);
CREATE INDEX IF NOT EXISTS idx_sessions_account_id ON public.sessions(account_id);
CREATE INDEX IF NOT EXISTS idx_transactions_building_id ON public.transactions(building_id);
CREATE INDEX IF NOT EXISTS idx_transactions_created_by ON public.transactions(created_by);
CREATE INDEX IF NOT EXISTS idx_units_building_id ON public.units(building_id);

-- Drop the duplicate username index; accounts_username_uq remains.
DROP INDEX IF EXISTS public.idx_accounts_username_unique;
