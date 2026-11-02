-- Enforce the product credential policy in the legacy Negin 2 UI RPCs.
-- This keeps the old interface functional while aligning its password rules.
begin;

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

  v_new_pass := floor(random() * 900000 + 100000)::bigint::text;

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

CREATE OR REPLACE FUNCTION public.app_admin_save_account(p_token uuid, p_id uuid, p_unit_no integer, p_username text, p_full_name text, p_phone text, p_occupancy text, p_is_primary boolean DEFAULT true, p_is_active boolean DEFAULT true, p_new_password text DEFAULT NULL::text, p_start_ym integer DEFAULT 140406)
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

  IF p_username IS NULL OR btrim(p_username) = '' OR p_username !~ '^[A-Za-z0-9_]{3,32}$' THEN
    RAISE EXCEPTION 'نام کاربری باید ۳ تا ۳۲ نویسه انگلیسی، عدد یا زیرخط باشد';
  END IF;

  IF p_new_password IS NOT NULL AND p_new_password <> '' AND p_new_password !~ '^[0-9]{4,6}$' THEN
    RAISE EXCEPTION 'رمز عبور باید فقط شامل ۴ تا ۶ رقم باشد';
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

CREATE OR REPLACE FUNCTION public.app_reset_password(p_username text, p_phone text, p_new_password text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare a accounts;
begin
  select * into a from accounts where lower(username) = lower(btrim(p_username)) and phone = btrim(p_phone) limit 1;
  if not found then return jsonb_build_object('ok', false, 'error', 'نام کاربری یا موبایل یافت نشد'); end if;
  if p_new_password !~ '^[0-9]{4,6}
  update accounts set password_hash = extensions.crypt(p_new_password, extensions.gen_salt('bf')), must_change_password = false, failed_attempts = 0, locked_until = null where id = a.id;
  update sessions set revoked_at = now() where account_id = a.id;
  insert into activity_logs (account_id, unit_no, full_name, action, details, actor_id) values (a.id, a.unit_no, a.full_name, 'فراموشی رمز', 'تغییر رمز با موبایل', a.id);
  return jsonb_build_object('ok', true);
end $function$
 then return jsonb_build_object('ok', false, 'error', 'رمز باید ۴ تا ۶ رقم انگلیسی باشد'); end if;
  update accounts set password_hash = extensions.crypt(p_new_password, extensions.gen_salt('bf')), must_change_password = false, failed_attempts = 0, locked_until = null where id = a.id;
  update sessions set revoked_at = now() where account_id = a.id;
  insert into activity_logs (account_id, unit_no, full_name, action, details, actor_id) values (a.id, a.unit_no, a.full_name, 'فراموشی رمز', 'تغییر رمز با موبایل', a.id);
  return jsonb_build_object('ok', true);
end $function$;

CREATE OR REPLACE FUNCTION public.app_update_profile(p_token uuid, p_full_name text, p_phone text, p_email text, p_username text DEFAULT NULL::text, p_current_password text DEFAULT NULL::text, p_new_password text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
declare a accounts; v_user text := nullif(btrim(p_username), ''); v_newpass text := nullif(p_new_password, '');
begin
  a := bm_auth(p_token);

  if (v_user is not null and lower(v_user) <> lower(a.username)) or v_newpass is not null then
    if a.password_hash <> extensions.crypt(coalesce(p_current_password, ''), a.password_hash) then
      raise exception 'رمز عبور فعلی اشتباه است';
    end if;
  end if;

  if v_user is not null and lower(v_user) <> lower(a.username) then
    if v_user !~ '^[A-Za-z0-9_]{3,32}
    if exists (select 1 from accounts where lower(username) = lower(v_user) and id <> a.id) then
      raise exception 'این نام کاربری قبلاً استفاده شده است';
    end if;
    update accounts set username = v_user where id = a.id;
  end if;

  if v_newpass is not null then
    if v_newpass !~ '^[0-9]{4,6}
    update accounts set password_hash = extensions.crypt(v_newpass, extensions.gen_salt('bf')),
                        must_change_password = false
     where id = a.id;
    delete from sessions where account_id = a.id and token <> p_token;
  end if;

  update accounts
     set full_name = nullif(btrim(p_full_name), ''),
         phone     = nullif(btrim(p_phone), ''),
         email     = nullif(btrim(p_email), ''),
         updated_at = now()
   where id = a.id
   returning * into a;
  return bm_account_json(a);
end $function$
 then raise exception 'نام کاربری باید ۳ تا ۳۲ نویسه انگلیسی، عدد یا زیرخط باشد'; end if;
    if exists (select 1 from accounts where lower(username) = lower(v_user) and id <> a.id) then
      raise exception 'این نام کاربری قبلاً استفاده شده است';
    end if;
    update accounts set username = v_user where id = a.id;
  end if;

  if v_newpass is not null then
    if length(v_newpass) < 4 then raise exception 'رمز عبور باید حداقل ۴ کاراکتر باشد'; end if;
    update accounts set password_hash = extensions.crypt(v_newpass, extensions.gen_salt('bf')),
                        must_change_password = false
     where id = a.id;
    delete from sessions where account_id = a.id and token <> p_token;
  end if;

  update accounts
     set full_name = nullif(btrim(p_full_name), ''),
         phone     = nullif(btrim(p_phone), ''),
         email     = nullif(btrim(p_email), ''),
         updated_at = now()
   where id = a.id
   returning * into a;
  return bm_account_json(a);
end $function$
 then raise exception 'رمز عبور باید ۴ تا ۶ رقم انگلیسی باشد'; end if;
    update accounts set password_hash = extensions.crypt(v_newpass, extensions.gen_salt('bf')),
                        must_change_password = false
     where id = a.id;
    delete from sessions where account_id = a.id and token <> p_token;
  end if;

  update accounts
     set full_name = nullif(btrim(p_full_name), ''),
         phone     = nullif(btrim(p_phone), ''),
         email     = nullif(btrim(p_email), ''),
         updated_at = now()
   where id = a.id
   returning * into a;
  return bm_account_json(a);
end $function$
 then raise exception 'نام کاربری باید ۳ تا ۳۲ نویسه انگلیسی، عدد یا زیرخط باشد'; end if;
    if exists (select 1 from accounts where lower(username) = lower(v_user) and id <> a.id) then
      raise exception 'این نام کاربری قبلاً استفاده شده است';
    end if;
    update accounts set username = v_user where id = a.id;
  end if;

  if v_newpass is not null then
    if length(v_newpass) < 4 then raise exception 'رمز عبور باید حداقل ۴ کاراکتر باشد'; end if;
    update accounts set password_hash = extensions.crypt(v_newpass, extensions.gen_salt('bf')),
                        must_change_password = false
     where id = a.id;
    delete from sessions where account_id = a.id and token <> p_token;
  end if;

  update accounts
     set full_name = nullif(btrim(p_full_name), ''),
         phone     = nullif(btrim(p_phone), ''),
         email     = nullif(btrim(p_email), ''),
         updated_at = now()
   where id = a.id
   returning * into a;
  return bm_account_json(a);
end $function$;

commit;
