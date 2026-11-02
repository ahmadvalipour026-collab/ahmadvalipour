-- Isolated multi-building backend for Negin 2.
-- Generated from the verified multi-building reference project.
-- Legacy public.* tables and RPCs remain untouched.
begin;
create schema if not exists mb;
set search_path to mb, public;

CREATE TABLE IF NOT EXISTS mb.app_accounts (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  username text NOT NULL,
  password_hash text NOT NULL,
  full_name text NOT NULL,
  phone text,
  email text,
  account_status text DEFAULT 'active'::text,
  must_change_password boolean DEFAULT false,
  is_superadmin boolean DEFAULT false,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT app_accounts_pkey PRIMARY KEY (id),
  CONSTRAINT app_accounts_username_key UNIQUE (username)
);

CREATE TABLE IF NOT EXISTS mb.app_sessions (
  token_hash text NOT NULL,
  account_id uuid,
  created_at timestamp with time zone DEFAULT now(),
  expires_at timestamp with time zone DEFAULT (now() + '7 days'::interval),
  CONSTRAINT app_sessions_account_id_fkey FOREIGN KEY (account_id) REFERENCES app_accounts(id) ON DELETE CASCADE,
  CONSTRAINT app_sessions_pkey PRIMARY KEY (token_hash)
);

CREATE TABLE IF NOT EXISTS mb.buildings (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  name text NOT NULL,
  building_status text DEFAULT 'active'::text,
  suspension_reason text,
  unit_count integer DEFAULT 1,
  current_manager_membership_id uuid,
  created_at timestamp with time zone DEFAULT now(),
  address text,
  floor_count integer,
  CONSTRAINT buildings_floor_count_check CHECK (((floor_count IS NULL) OR ((floor_count >= 1) AND (floor_count <= 200)))),
  CONSTRAINT buildings_pkey PRIMARY KEY (id),
  CONSTRAINT buildings_unit_count_check CHECK (((unit_count >= 1) AND (unit_count <= 1000)))
);

CREATE TABLE IF NOT EXISTS mb.units (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  building_id uuid,
  unit_no integer NOT NULL,
  area numeric DEFAULT 0,
  resident_count integer DEFAULT 1,
  CONSTRAINT units_area_check CHECK (((area IS NULL) OR (area > (0)::numeric))),
  CONSTRAINT units_building_id_fkey FOREIGN KEY (building_id) REFERENCES buildings(id) ON DELETE CASCADE,
  CONSTRAINT units_building_id_unit_no_key UNIQUE (building_id, unit_no),
  CONSTRAINT units_pkey PRIMARY KEY (id),
  CONSTRAINT units_resident_count_check CHECK (((resident_count IS NULL) OR (resident_count >= 1))),
  CONSTRAINT units_unit_no_check CHECK ((unit_no >= 1))
);

CREATE TABLE IF NOT EXISTS mb.building_memberships (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  building_id uuid,
  account_id uuid,
  unit_id uuid,
  access_role text DEFAULT 'resident'::text,
  resident_type text DEFAULT 'owner_resident'::text,
  membership_status text DEFAULT 'active'::text,
  joined_at timestamp with time zone DEFAULT now(),
  ended_at timestamp with time zone,
  opening_debt numeric DEFAULT 0 NOT NULL,
  CONSTRAINT building_memberships_account_id_fkey FOREIGN KEY (account_id) REFERENCES app_accounts(id) ON DELETE SET NULL,
  CONSTRAINT building_memberships_building_id_fkey FOREIGN KEY (building_id) REFERENCES buildings(id) ON DELETE CASCADE,
  CONSTRAINT building_memberships_pkey PRIMARY KEY (id),
  CONSTRAINT building_memberships_unit_id_fkey FOREIGN KEY (unit_id) REFERENCES units(id) ON DELETE CASCADE,
  CONSTRAINT financial_v2_opening_debt_check CHECK ((opening_debt >= (0)::numeric)),
  CONSTRAINT memberships_date_order_check CHECK (((ended_at IS NULL) OR (ended_at >= joined_at)))
);

CREATE TABLE IF NOT EXISTS mb.registration_requests (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  username text NOT NULL,
  requested_password_hash text NOT NULL,
  full_name text NOT NULL,
  phone text,
  email text,
  requested_role text NOT NULL,
  building_id uuid,
  new_building_name text,
  new_building_unit_count integer,
  unit_no integer,
  area numeric,
  resident_count integer,
  request_status text DEFAULT 'pending'::text,
  reviewed_by uuid,
  reviewed_at timestamp with time zone,
  review_note text,
  created_at timestamp with time zone DEFAULT now(),
  new_building_address text,
  new_building_floor_count integer,
  CONSTRAINT registration_requests_building_id_fkey FOREIGN KEY (building_id) REFERENCES buildings(id) ON DELETE CASCADE,
  CONSTRAINT registration_requests_pkey PRIMARY KEY (id),
  CONSTRAINT registration_requests_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES app_accounts(id)
);

CREATE TABLE IF NOT EXISTS mb.building_requests (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  building_id uuid,
  membership_id uuid,
  request_type text NOT NULL,
  title text NOT NULL,
  description text,
  request_status text DEFAULT 'pending'::text,
  manager_reply text,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT building_requests_building_id_fkey FOREIGN KEY (building_id) REFERENCES buildings(id) ON DELETE CASCADE,
  CONSTRAINT building_requests_membership_id_fkey FOREIGN KEY (membership_id) REFERENCES building_memberships(id) ON DELETE CASCADE,
  CONSTRAINT building_requests_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS mb.building_finance_settings (
  building_id uuid NOT NULL,
  accounting_start_date date DEFAULT CURRENT_DATE NOT NULL,
  opening_balance numeric DEFAULT 0,
  created_by uuid,
  updated_by uuid,
  updated_at timestamp with time zone DEFAULT now(),
  CONSTRAINT building_finance_settings_building_id_fkey FOREIGN KEY (building_id) REFERENCES buildings(id) ON DELETE CASCADE,
  CONSTRAINT building_finance_settings_created_by_fkey FOREIGN KEY (created_by) REFERENCES app_accounts(id),
  CONSTRAINT building_finance_settings_pkey PRIMARY KEY (building_id),
  CONSTRAINT building_finance_settings_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES app_accounts(id)
);

CREATE TABLE IF NOT EXISTS mb.building_expenses (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  building_id uuid,
  description text NOT NULL,
  amount numeric NOT NULL,
  expense_date date DEFAULT CURRENT_DATE NOT NULL,
  allocation_method text NOT NULL,
  tx_type text DEFAULT 'هزینه'::text NOT NULL,
  category text DEFAULT 'سایر'::text,
  expense_status text DEFAULT 'active'::text,
  created_by uuid,
  created_at timestamp with time zone DEFAULT now(),
  payer_roles text[] DEFAULT ARRAY['owner'::text, 'owner_resident'::text] NOT NULL,
  period_start date,
  period_end date,
  input_amount numeric,
  selected_unit_ids uuid[],
  CONSTRAINT building_expenses_building_id_fkey FOREIGN KEY (building_id) REFERENCES buildings(id) ON DELETE CASCADE,
  CONSTRAINT building_expenses_created_by_fkey FOREIGN KEY (created_by) REFERENCES app_accounts(id),
  CONSTRAINT building_expenses_pkey PRIMARY KEY (id),
  CONSTRAINT financial_v2_payer_roles_check CHECK ((NOT (('owner'::text = ANY (payer_roles)) AND ('tenant'::text = ANY (payer_roles))))),
  CONSTRAINT financial_v2_period_check CHECK (((period_start IS NULL) OR (period_end IS NULL) OR (period_start <= period_end)))
);

CREATE TABLE IF NOT EXISTS mb.building_expense_allocations (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  building_id uuid,
  expense_id uuid,
  membership_id uuid,
  amount numeric NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  original_membership_id uuid,
  transfer_note text,
  CONSTRAINT building_expense_allocations_building_id_fkey FOREIGN KEY (building_id) REFERENCES buildings(id) ON DELETE CASCADE,
  CONSTRAINT building_expense_allocations_expense_id_fkey FOREIGN KEY (expense_id) REFERENCES building_expenses(id) ON DELETE CASCADE,
  CONSTRAINT building_expense_allocations_membership_id_fkey FOREIGN KEY (membership_id) REFERENCES building_memberships(id) ON DELETE CASCADE,
  CONSTRAINT building_expense_allocations_original_membership_id_fkey FOREIGN KEY (original_membership_id) REFERENCES building_memberships(id) ON DELETE SET NULL,
  CONSTRAINT building_expense_allocations_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS mb.building_payments (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  building_id uuid,
  membership_id uuid,
  amount numeric NOT NULL,
  payment_date date DEFAULT CURRENT_DATE NOT NULL,
  description text,
  status text DEFAULT 'pending'::text,
  created_by uuid,
  reviewed_at timestamp with time zone,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT building_payments_building_id_fkey FOREIGN KEY (building_id) REFERENCES buildings(id) ON DELETE CASCADE,
  CONSTRAINT building_payments_created_by_fkey FOREIGN KEY (created_by) REFERENCES app_accounts(id),
  CONSTRAINT building_payments_membership_id_fkey FOREIGN KEY (membership_id) REFERENCES building_memberships(id) ON DELETE CASCADE,
  CONSTRAINT building_payments_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS mb.building_payment_allocations (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  building_id uuid,
  payment_id uuid,
  expense_allocation_id uuid,
  amount numeric NOT NULL,
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT building_payment_allocations_building_id_fkey FOREIGN KEY (building_id) REFERENCES buildings(id) ON DELETE CASCADE,
  CONSTRAINT building_payment_allocations_expense_allocation_id_fkey FOREIGN KEY (expense_allocation_id) REFERENCES building_expense_allocations(id) ON DELETE CASCADE,
  CONSTRAINT building_payment_allocations_payment_id_fkey FOREIGN KEY (payment_id) REFERENCES building_payments(id) ON DELETE CASCADE,
  CONSTRAINT building_payment_allocations_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS mb.building_payment_item_requests (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  building_id uuid NOT NULL,
  payment_id uuid NOT NULL,
  expense_allocation_id uuid NOT NULL,
  amount numeric NOT NULL,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT building_payment_item_request_payment_id_expense_allocation_key UNIQUE (payment_id, expense_allocation_id),
  CONSTRAINT building_payment_item_requests_amount_check CHECK ((amount > (0)::numeric)),
  CONSTRAINT building_payment_item_requests_building_id_fkey FOREIGN KEY (building_id) REFERENCES buildings(id) ON DELETE CASCADE,
  CONSTRAINT building_payment_item_requests_expense_allocation_id_fkey FOREIGN KEY (expense_allocation_id) REFERENCES building_expense_allocations(id) ON DELETE RESTRICT,
  CONSTRAINT building_payment_item_requests_payment_id_fkey FOREIGN KEY (payment_id) REFERENCES building_payments(id) ON DELETE CASCADE,
  CONSTRAINT building_payment_item_requests_pkey PRIMARY KEY (id)
);

CREATE TABLE IF NOT EXISTS mb.push_subscriptions (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  account_id uuid NOT NULL,
  endpoint text NOT NULL,
  p256dh text NOT NULL,
  auth text NOT NULL,
  user_agent text,
  created_at timestamp with time zone DEFAULT now() NOT NULL,
  updated_at timestamp with time zone DEFAULT now() NOT NULL,
  CONSTRAINT push_subscriptions_account_id_fkey FOREIGN KEY (account_id) REFERENCES app_accounts(id) ON DELETE CASCADE,
  CONSTRAINT push_subscriptions_endpoint_key UNIQUE (endpoint),
  CONSTRAINT push_subscriptions_pkey PRIMARY KEY (id)
);

ALTER TABLE mb.buildings ADD CONSTRAINT fk_manager FOREIGN KEY (current_manager_membership_id) REFERENCES mb.building_memberships(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_bp_created_by ON mb.building_payments USING btree (created_by)
CREATE INDEX IF NOT EXISTS idx_br_membership_id ON mb.building_requests USING btree (membership_id)
CREATE UNIQUE INDEX IF NOT EXISTS ux_active_tenant_per_unit ON mb.building_memberships USING btree (unit_id) WHERE ((membership_status = 'active'::text) AND (resident_type = 'tenant'::text))
CREATE UNIQUE INDEX IF NOT EXISTS ux_active_owner_per_unit ON mb.building_memberships USING btree (unit_id) WHERE ((membership_status = 'active'::text) AND (resident_type = ANY (ARRAY['owner'::text, 'owner_resident'::text])))
CREATE INDEX IF NOT EXISTS idx_bea_membership_id ON mb.building_expense_allocations USING btree (membership_id)
CREATE INDEX IF NOT EXISTS idx_bpa_expense_allocation_id ON mb.building_payment_allocations USING btree (expense_allocation_id)
CREATE INDEX IF NOT EXISTS idx_bm_account_id ON mb.building_memberships USING btree (account_id)
CREATE INDEX IF NOT EXISTS idx_bfs_created_by ON mb.building_finance_settings USING btree (created_by)
CREATE INDEX IF NOT EXISTS idx_rr_reviewed_by ON mb.registration_requests USING btree (reviewed_by)
CREATE INDEX IF NOT EXISTS idx_buildings_manager_membership_id ON mb.buildings USING btree (current_manager_membership_id)
CREATE INDEX IF NOT EXISTS idx_bpa_building_id ON mb.building_payment_allocations USING btree (building_id)
CREATE INDEX IF NOT EXISTS idx_bp_building_id ON mb.building_payments USING btree (building_id)
CREATE INDEX IF NOT EXISTS idx_rr_building_id ON mb.registration_requests USING btree (building_id)
CREATE INDEX IF NOT EXISTS idx_bpa_payment_id ON mb.building_payment_allocations USING btree (payment_id)
CREATE INDEX IF NOT EXISTS idx_app_sessions_account_id ON mb.app_sessions USING btree (account_id)
CREATE UNIQUE INDEX IF NOT EXISTS ux_active_manager_per_building ON mb.building_memberships USING btree (building_id) WHERE ((membership_status = 'active'::text) AND (access_role = 'manager'::text))
CREATE UNIQUE INDEX IF NOT EXISTS ux_buildings_name_ci ON mb.buildings USING btree (lower(name))
CREATE INDEX IF NOT EXISTS idx_bm_building_id ON mb.building_memberships USING btree (building_id)
CREATE INDEX IF NOT EXISTS idx_bea_original_membership_id ON mb.building_expense_allocations USING btree (original_membership_id)
CREATE INDEX IF NOT EXISTS idx_payment_item_requests_expense_allocation_id ON mb.building_payment_item_requests USING btree (expense_allocation_id)
CREATE INDEX IF NOT EXISTS idx_bea_building_id ON mb.building_expense_allocations USING btree (building_id)
CREATE INDEX IF NOT EXISTS idx_be_building_id ON mb.building_expenses USING btree (building_id)
CREATE INDEX IF NOT EXISTS idx_be_created_by ON mb.building_expenses USING btree (created_by)
CREATE INDEX IF NOT EXISTS idx_br_building_id ON mb.building_requests USING btree (building_id)
CREATE INDEX IF NOT EXISTS idx_bp_membership_id ON mb.building_payments USING btree (membership_id)
CREATE INDEX IF NOT EXISTS idx_payment_item_requests_building_id ON mb.building_payment_item_requests USING btree (building_id)
CREATE INDEX IF NOT EXISTS idx_bea_expense_id ON mb.building_expense_allocations USING btree (expense_id)
CREATE INDEX IF NOT EXISTS idx_bfs_updated_by ON mb.building_finance_settings USING btree (updated_by)
CREATE INDEX IF NOT EXISTS idx_bm_unit_id ON mb.building_memberships USING btree (unit_id)

do $$
declare t record;
begin
  for t in select tablename from pg_tables where schemaname='mb' loop
    execute format('alter table mb.%I enable row level security',t.tablename);
    execute format('revoke all privileges on table mb.%I from anon, authenticated',t.tablename);
  end loop;
end $$;

CREATE OR REPLACE FUNCTION public.mb_app_admin_delete_building(p_token uuid, p_building_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_actor mb.app_accounts;
BEGIN
    SELECT * INTO v_actor FROM public.mb_app_require_session(p_token);
    IF NOT v_actor.is_superadmin THEN RAISE EXCEPTION 'دسترسی غیرمجاز'; END IF;
    UPDATE mb.buildings SET building_status = 'deleted' WHERE id = p_building_id;
    UPDATE mb.building_memberships SET membership_status = 'inactive' WHERE building_id = p_building_id;
    RETURN jsonb_build_object('success', true);
END; $function$;


CREATE OR REPLACE FUNCTION public.mb_app_admin_get_db_tables(p_token uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_actor mb.app_accounts; v_tables jsonb;
BEGIN
    SELECT * INTO v_actor FROM public.mb_app_require_session(p_token);
    IF NOT v_actor.is_superadmin THEN RAISE EXCEPTION 'دسترسی غیرمجاز'; END IF;
    SELECT COALESCE(jsonb_agg(jsonb_build_object('table_name', table_name)), '[]'::jsonb) INTO v_tables
    FROM information_schema.tables WHERE table_schema = 'mb' AND table_type = 'BASE TABLE';
    RETURN v_tables;
END; $function$;


CREATE OR REPLACE FUNCTION public.mb_app_admin_get_table_data(p_token uuid, p_table_name text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_actor mb.app_accounts; v_data jsonb;
BEGIN
    SELECT * INTO v_actor FROM public.mb_app_require_session(p_token);
    IF NOT v_actor.is_superadmin THEN RAISE EXCEPTION 'دسترسی غیرمجاز'; END IF;
    EXECUTE format('SELECT COALESCE(jsonb_agg(t), ''[]''::jsonb) FROM (SELECT * FROM mb.%I LIMIT 100) t', p_table_name) INTO v_data;
    RETURN v_data;
END; $function$;


CREATE OR REPLACE FUNCTION public.mb_app_admin_list_buildings(p_token uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_actor mb.app_accounts; v_buildings jsonb;
BEGIN
    SELECT * INTO v_actor FROM public.mb_app_require_session(p_token);
    IF NOT v_actor.is_superadmin THEN RAISE EXCEPTION 'دسترسی غیرمجاز'; END IF;
    
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'building_id', b.id, 'building_name', b.name, 'building_status', b.building_status, 
        'suspension_reason', b.suspension_reason, 'unit_count', b.unit_count,
        'manager_name', a.full_name, 'manager_username', a.username
    ) ORDER BY b.created_at DESC), '[]'::jsonb) INTO v_buildings
    FROM mb.buildings b
    LEFT JOIN mb.building_memberships bm ON bm.id = b.current_manager_membership_id
    LEFT JOIN mb.app_accounts a ON a.id = bm.account_id;
    
    RETURN jsonb_build_object('buildings', v_buildings);
END; $function$;


CREATE OR REPLACE FUNCTION public.mb_app_admin_list_registration_requests(p_token uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_actor mb.app_accounts; v_reqs jsonb;
BEGIN
    SELECT * INTO v_actor FROM public.mb_app_require_session(p_token);
    IF NOT v_actor.is_superadmin THEN RAISE EXCEPTION 'دسترسی غیرمجاز'; END IF;
    
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
        'id', r.id, 'full_name', r.full_name, 'username', r.username, 'phone', r.phone, 'email', r.email,
        'building_name', r.new_building_name, 'unit_count', r.new_building_unit_count, 
        'requested_role', r.requested_role, 'unit_no', r.unit_no, 'area', r.area, 'resident_count', r.resident_count
    )), '[]'::jsonb) INTO v_reqs
    FROM mb.registration_requests r
    WHERE r.request_status = 'pending' AND r.requested_role = 'building_manager';
    
    RETURN v_reqs;
END; $function$;


CREATE OR REPLACE FUNCTION public.mb_app_admin_reset_manager_password(p_token uuid, p_building_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_actor mb.app_accounts; v_temp text; v_acc_id uuid;
BEGIN
    SELECT * INTO v_actor FROM public.mb_app_require_session(p_token);
    IF NOT v_actor.is_superadmin THEN RAISE EXCEPTION 'دسترسی غیرمجاز'; END IF;
    
    SELECT account_id INTO v_acc_id FROM mb.building_memberships WHERE id = (SELECT current_manager_membership_id FROM mb.buildings WHERE id = p_building_id);
    v_temp := floor(random()*900000+100000)::bigint::text;
    
    UPDATE mb.app_accounts SET password_hash = extensions.crypt(v_temp, extensions.gen_salt('bf')), must_change_password = true WHERE id = v_acc_id;
    RETURN jsonb_build_object('success', true, 'temp_password', v_temp);
END; $function$;


CREATE OR REPLACE FUNCTION public.mb_app_admin_review_manager_request(p_token uuid, p_request_id uuid, p_approve boolean, p_review_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_actor mb.app_accounts;
 v_req mb.registration_requests%rowtype;
 v_b_id uuid;
 v_acc_id uuid;
 v_m_id uuid;
 v_unit_id uuid;
begin
 select * into v_actor from public.mb_app_require_session(p_token);
 if not v_actor.is_superadmin then raise exception 'دسترسی غیرمجاز'; end if;
 select * into v_req from mb.registration_requests where id=p_request_id for update;
 if not found then raise exception 'درخواست پیدا نشد'; end if;
 if p_approve then
  if v_req.new_building_name is not null then
   insert into mb.buildings(name,address,floor_count,unit_count,building_status)
   values(v_req.new_building_name,v_req.new_building_address,v_req.new_building_floor_count,v_req.new_building_unit_count,'active')
   returning id into v_b_id;
   insert into mb.units(building_id,unit_no,area,resident_count)
   select v_b_id,gs,null,null from generate_series(1,v_req.new_building_unit_count) gs;
  else
   v_b_id:=v_req.building_id;
  end if;
  if v_req.unit_no is not null then
   select id into v_unit_id from mb.units where building_id=v_b_id and unit_no=v_req.unit_no for update;
   if v_unit_id is null then raise exception 'واحد انتخاب‌شده در ساختمان وجود ندارد'; end if;
   if v_req.area is null or v_req.area<=0 then raise exception 'متراژ واحد نامعتبر است'; end if;
   update mb.units set area=v_req.area,resident_count=coalesce(v_req.resident_count,1) where id=v_unit_id;
  end if;
  insert into mb.app_accounts(username,password_hash,full_name,phone,email,account_status)
  values(v_req.username,v_req.requested_password_hash,v_req.full_name,v_req.phone,v_req.email,'active') returning id into v_acc_id;
  insert into mb.building_memberships(building_id,account_id,access_role,membership_status,resident_type,unit_id)
  values(v_b_id,v_acc_id,'manager','active',case when v_req.unit_no is not null then 'owner_resident' else null end,v_unit_id)
  returning id into v_m_id;
  update mb.buildings set current_manager_membership_id=v_m_id where id=v_b_id;
  update mb.registration_requests set request_status='approved',reviewed_by=v_actor.id,reviewed_at=now(),review_note=p_review_note where id=p_request_id;
 else
  update mb.registration_requests set request_status='rejected',reviewed_by=v_actor.id,reviewed_at=now(),review_note=p_review_note where id=p_request_id;
 end if;
 return jsonb_build_object('success',true,'building_id',v_b_id);
end;
$function$;


CREATE OR REPLACE FUNCTION public.mb_app_admin_set_building_status(p_token uuid, p_building_id uuid, p_new_status text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_actor mb.app_accounts;
BEGIN
    SELECT * INTO v_actor FROM public.mb_app_require_session(p_token);
    IF NOT v_actor.is_superadmin THEN RAISE EXCEPTION 'دسترسی غیرمجاز'; END IF;
    UPDATE mb.buildings SET building_status = p_new_status, suspension_reason = p_reason WHERE id = p_building_id;
    RETURN jsonb_build_object('success', true);
END; $function$;


CREATE OR REPLACE FUNCTION public.mb_app_change_password(p_token uuid, p_new_password text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_acc mb.app_accounts;
BEGIN
    IF p_new_password !~ '^[0-9]{4,6}$' THEN RAISE EXCEPTION 'رمز عبور باید ۴ تا ۶ رقم انگلیسی باشد'; END IF;
    v_acc := public.mb_app_require_session(p_token);
    UPDATE mb.app_accounts SET password_hash = extensions.crypt(p_new_password, extensions.gen_salt('bf')), must_change_password = false WHERE id = v_acc.id;
    RETURN jsonb_build_object('success', true);
END; $function$;


CREATE OR REPLACE FUNCTION public.mb_app_check_registration_status(p_username text, p_password text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_req record;
BEGIN
    SELECT * INTO v_req FROM mb.registration_requests WHERE lower(username) = lower(p_username) ORDER BY created_at DESC LIMIT 1;
    IF NOT FOUND THEN RAISE EXCEPTION 'درخواستی با این نام کاربری یافت نشد'; END IF;
    RETURN jsonb_build_object('requested_role', v_req.requested_role, 'request_status', v_req.request_status, 'review_note', v_req.review_note);
END; $function$;


CREATE OR REPLACE FUNCTION public.mb_app_financial_v2_close_tenant(p_token uuid, p_building_id uuid, p_membership_id uuid, p_end_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare t mb.building_memberships; owner_id uuid; a record; paid numeric; due numeric; new_id uuid; total numeric:=0; total_paid numeric; total_alloc numeric; credit numeric;
begin
 perform public.mb_app_financial_v2_require_manager(p_token,p_building_id); select * into t from mb.building_memberships where id=p_membership_id and building_id=p_building_id for update;
 if not found or t.resident_type<>'tenant' or t.membership_status<>'active' then raise exception 'مستأجر فعال پیدا نشد'; end if;
 if p_end_date<t.joined_at::date or p_end_date>current_date then raise exception 'تاریخ خروج نامعتبر است'; end if;
 select id into owner_id from mb.building_memberships where unit_id=t.unit_id and building_id=p_building_id and resident_type in ('owner','owner_resident') and membership_status='active' order by (resident_type='owner_resident') desc,joined_at desc limit 1; if owner_id is null then raise exception 'ابتدا مالک واحد را ثبت کنید'; end if;
 update mb.building_memberships set ended_at=p_end_date,membership_status='inactive' where id=p_membership_id; perform public.mb_app_recalculate_expense_allocations(p_token,p_building_id);
 for a in select ea.*,e.description from mb.building_expense_allocations ea join mb.building_expenses e on e.id=ea.expense_id where ea.building_id=p_building_id and ea.membership_id=p_membership_id and e.expense_status='active' loop
  select coalesce(sum(pa.amount),0) into paid from mb.building_payment_allocations pa where pa.expense_allocation_id=a.id; due:=greatest(a.amount-paid,0);
  if due>0 then update mb.building_expense_allocations set amount=paid where id=a.id; insert into mb.building_expense_allocations(building_id,expense_id,membership_id,amount,original_membership_id,transfer_note) values(p_building_id,a.expense_id,owner_id,due,p_membership_id,'انتقال بدهی مستأجر قبلی به مالک') returning id into new_id; total:=total+due; end if;
 end loop;
 select coalesce(sum(amount),0) into total_paid from mb.building_payments where building_id=p_building_id and membership_id=p_membership_id and status='approved';
 select coalesce(sum(pa.amount),0) into total_alloc from mb.building_payment_allocations pa join mb.building_payments p on p.id=pa.payment_id where p.building_id=p_building_id and p.membership_id=p_membership_id and p.status='approved';
 credit:=greatest(total_paid-total_alloc,0); due:=greatest(coalesce(t.opening_debt,0)-credit,0);
 if due>0 then update mb.building_memberships set opening_debt=coalesce(opening_debt,0)+due where id=owner_id; update mb.building_memberships set opening_debt=greatest(opening_debt-due,0) where id=p_membership_id; total:=total+due; end if;
 perform public.mb_app_reallocate_member_payments(p_building_id,owner_id); return jsonb_build_object('success',true,'transferred_amount',total,'tenant_membership_id',p_membership_id,'owner_membership_id',owner_id);
end; $function$;


CREATE OR REPLACE FUNCTION public.mb_app_financial_v2_create_transaction(p_token uuid, p_building_id uuid, p_description text, p_amount numeric, p_expense_date date, p_allocation_method text, p_tx_type text, p_category text, p_payer_roles text[], p_period_start date DEFAULT NULL::date, p_period_end date DEFAULT NULL::date, p_allocations jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid;v_id uuid;v_item jsonb;v_member uuid;v_item_amount numeric;v_sum numeric:=0;
begin
 v_actor:=public.mb_app_financial_v2_require_manager(p_token,p_building_id);
 if p_amount is null or p_amount<=0 then raise exception 'مبلغ نامعتبر'; end if;
 if nullif(btrim(p_description),'') is null then raise exception 'شرح تراکنش الزامی است'; end if;
 if p_tx_type not in ('درآمد','هزینه') then raise exception 'نوع تراکنش نامعتبر است'; end if;
 if p_allocation_method not in ('none','manual','equal','area','residents','per_unit','dynamic_per_unit','dynamic_per_meter','dynamic_per_resident') then
  raise exception 'روش تخصیص نامعتبر است';
 end if;
 if coalesce(array_length(p_payer_roles,1),0)=0 and p_allocation_method<>'none' then raise exception 'مسئول پرداخت را مشخص کنید'; end if;
 if 'owner'=any(p_payer_roles) and 'tenant'=any(p_payer_roles) then raise exception 'مالک و مستأجر نمی‌توانند هم‌زمان مسئول پرداخت باشند'; end if;
 if p_period_start is not null and p_period_end is not null and p_period_end<p_period_start then raise exception 'بازه زمانی نامعتبر است'; end if;

 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  p_building_id::text||'|'||v_actor::text||'|'||coalesce(p_description,'')||'|'||p_amount::text||'|'||coalesce(p_expense_date,current_date)::text,0));
 if exists(select 1 from mb.building_expenses e where e.building_id=p_building_id
  and e.created_by=v_actor and e.description=btrim(p_description) and e.amount=p_amount
  and e.expense_date=coalesce(p_expense_date,current_date) and e.tx_type=p_tx_type
  and e.expense_status='active' and e.created_at>now()-interval '20 seconds') then
  raise exception 'تراکنش مشابه همین لحظه ثبت شده است؛ از ثبت مجدد خودداری شد';
 end if;

 if p_allocation_method='manual' then
  if jsonb_typeof(p_allocations) is distinct from 'array' or jsonb_array_length(p_allocations)=0 then
   raise exception 'تخصیص دستی باید حداقل یک ردیف داشته باشد';
  end if;
  for v_item in select value from jsonb_array_elements(p_allocations) loop
   v_member:=(v_item->>'membership_id')::uuid;
   v_item_amount:=(v_item->>'amount')::numeric;
   if v_item_amount is null or v_item_amount<=0 then raise exception 'مبلغ تخصیص دستی نامعتبر است'; end if;
   if not exists(select 1 from mb.building_memberships bm where bm.id=v_member and bm.building_id=p_building_id and bm.membership_status='active') then
    raise exception 'عضویت تخصیص انتخاب‌شده متعلق به این ساختمان یا فعال نیست';
   end if;
   v_sum:=v_sum+v_item_amount;
  end loop;
  if round(v_sum,2)<>round(p_amount,2) then raise exception 'جمع تخصیص‌ها باید با مبلغ تراکنش برابر باشد'; end if;
 end if;

 insert into mb.building_expenses(building_id,description,amount,input_amount,expense_date,allocation_method,
  tx_type,category,created_by,payer_roles,period_start,period_end)
 values(p_building_id,btrim(p_description),p_amount,p_amount,coalesce(p_expense_date,current_date),
  p_allocation_method,p_tx_type,p_category,v_actor,p_payer_roles,p_period_start,p_period_end)
 returning id into v_id;

 if p_allocation_method='manual' then
  for v_item in select value from jsonb_array_elements(p_allocations) loop
   insert into mb.building_expense_allocations(building_id,expense_id,membership_id,amount)
   values(p_building_id,v_id,(v_item->>'membership_id')::uuid,(v_item->>'amount')::numeric);
  end loop;
 else
  perform public.mb_app_recalculate_expense_allocations(p_token,p_building_id);
 end if;
 return jsonb_build_object('success',true,'expense_id',v_id);
end;$function$;


CREATE OR REPLACE FUNCTION public.mb_app_financial_v2_edit_transaction_details(p_token uuid, p_id uuid, p_description text, p_category text, p_expense_date date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_building_id uuid;
BEGIN
    SELECT building_id INTO v_building_id
    FROM mb.building_expenses
    WHERE id = p_id
      AND expense_status = 'active'
    FOR UPDATE;

    IF v_building_id IS NULL THEN
        RAISE EXCEPTION 'تراکنش پیدا نشد';
    END IF;

    PERFORM public.mb_app_financial_v2_require_manager(
        p_token, v_building_id
    );

    UPDATE mb.building_expenses
    SET
        description = trim(p_description),
        category = p_category,
        expense_date = p_expense_date
    WHERE id = p_id;

    RETURN jsonb_build_object('success', true);
END;
$function$;


CREATE OR REPLACE FUNCTION public.mb_app_financial_v2_require_manager(p_token uuid, p_building_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_actor mb.app_accounts;
BEGIN
 SELECT * INTO v_actor FROM public.mb_app_require_session(p_token);
 IF NOT v_actor.is_superadmin AND NOT EXISTS (
  SELECT 1 FROM mb.building_memberships bm WHERE bm.account_id=v_actor.id
   AND bm.building_id=p_building_id AND bm.membership_status='active' AND bm.access_role='manager'
 ) THEN RAISE EXCEPTION 'دسترسی مدیر این ساختمان لازم است'; END IF;
 RETURN v_actor.id;
END $function$;


CREATE OR REPLACE FUNCTION public.mb_app_financial_v2_set_opening_debt(p_token uuid, p_building_id uuid, p_membership_id uuid, p_amount numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
 PERFORM public.mb_app_financial_v2_require_manager(p_token,p_building_id);
 IF p_amount < 0 THEN RAISE EXCEPTION 'بدهی اولیه منفی نیست'; END IF;
 UPDATE mb.building_memberships SET opening_debt=p_amount WHERE id=p_membership_id AND building_id=p_building_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'عضو پیدا نشد'; END IF;
 RETURN jsonb_build_object('success',true);
END $function$;


CREATE OR REPLACE FUNCTION public.mb_app_login(p_username text, p_password text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_acc mb.app_accounts; v_token uuid; v_memberships jsonb;
begin
 select * into v_acc from mb.app_accounts where lower(username)=lower(btrim(p_username)) and account_status='active' and password_hash=extensions.crypt(p_password,password_hash);
 if not found then return jsonb_build_object('success',false,'error','نام کاربری یا رمز عبور اشتباه است'); end if;
 v_token:=gen_random_uuid();
 insert into mb.app_sessions(token_hash,account_id) values(encode(extensions.digest(v_token::text,'sha256'),'hex'),v_acc.id);
 select coalesce(jsonb_agg(jsonb_build_object('membership_id',bm.id,'building_id',b.id,'building_name',b.name,'unit_no',u.unit_no,'access_role',bm.access_role,'resident_type',bm.resident_type,'membership_status',bm.membership_status,'building_status',b.building_status,'address',b.address,'floor_count',b.floor_count) order by b.created_at desc),'[]'::jsonb) into v_memberships from mb.building_memberships bm join mb.buildings b on b.id=bm.building_id left join mb.units u on u.id=bm.unit_id where bm.account_id=v_acc.id and bm.membership_status='active';
 return jsonb_build_object('success',true,'token',v_token,'account_id',v_acc.id,'username',v_acc.username,'full_name',v_acc.full_name,'is_superadmin',v_acc.is_superadmin,'must_change_password',v_acc.must_change_password,'memberships',v_memberships);
end; $function$;


CREATE OR REPLACE FUNCTION public.mb_app_logout(p_token uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
    DELETE FROM mb.app_sessions WHERE token_hash = encode(extensions.digest(p_token::text, 'sha256'), 'hex');
    RETURN jsonb_build_object('success', true);
END; $function$;


CREATE OR REPLACE FUNCTION public.mb_app_manager_add_unit_and_resident(p_token uuid, p_building_id uuid, p_unit_no integer, p_area numeric, p_resident_count integer, p_full_name text, p_username text, p_password text, p_occupancy text, p_phone text, p_email text, p_joined_at date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_unit_id uuid; v_account_id uuid; v_member_id uuid; v_limit integer;
begin
 perform public.mb_app_financial_v2_require_manager(p_token,p_building_id);
 select b.unit_count into v_limit from mb.buildings b where b.id=p_building_id and b.building_status='active' for update; if not found then raise exception 'ساختمان فعال پیدا نشد'; end if;
 if p_username !~ '^[A-Za-z0-9_]{3,32}$' then raise exception 'نام کاربری باید ۳ تا ۳۲ نویسه انگلیسی، عدد یا زیرخط باشد'; end if;
 if p_password !~ '^[0-9]{4,6}$' then raise exception 'رمز عبور باید ۴ تا ۶ رقم انگلیسی باشد'; end if;
 if p_unit_no is null or p_unit_no<1 or p_unit_no>v_limit then raise exception 'شماره واحد نامعتبر است'; end if;
 select u.id into v_unit_id from mb.units u where u.building_id=p_building_id and u.unit_no=p_unit_no for update; if v_unit_id is null then raise exception 'این واحد در ساختار ثابت ساختمان وجود ندارد'; end if;
 if p_area is null or p_area<=0 or p_resident_count is null or p_resident_count<1 then raise exception 'متراژ و تعداد ساکنین نامعتبر است'; end if;
 if p_occupancy not in ('owner','owner_resident','tenant') then raise exception 'نوع سکونت نامعتبر است'; end if;
 if p_joined_at is null or p_joined_at>current_date then raise exception 'تاریخ شروع نامعتبر است'; end if;
 if exists(select 1 from mb.app_accounts where lower(username)=lower(btrim(p_username))) then raise exception 'نام کاربری تکراری است'; end if;
 if p_occupancy in ('owner','owner_resident') and exists(select 1 from mb.building_memberships bm where bm.unit_id=v_unit_id and bm.membership_status='active' and bm.resident_type in ('owner','owner_resident')) then raise exception 'این واحد قبلاً مالک فعال دارد'; end if;
 if p_occupancy='tenant' and exists(select 1 from mb.building_memberships bm where bm.unit_id=v_unit_id and bm.membership_status='active' and bm.resident_type='tenant') then raise exception 'این واحد قبلاً مستأجر فعال دارد'; end if;
 if p_occupancy='tenant' and exists(select 1 from mb.building_memberships bm where bm.unit_id=v_unit_id and bm.membership_status='active' and bm.resident_type='owner_resident') then raise exception 'واحد دارای مالک ساکن فعال است'; end if;
 if p_occupancy='owner_resident' and exists(select 1 from mb.building_memberships bm where bm.unit_id=v_unit_id and bm.membership_status='active' and bm.resident_type='tenant') then raise exception 'واحد دارای مستأجر فعال است'; end if;
 update mb.units set area=p_area,resident_count=p_resident_count where id=v_unit_id;
 insert into mb.app_accounts(username,password_hash,full_name,phone,email,account_status,must_change_password) values(btrim(p_username),extensions.crypt(p_password,extensions.gen_salt('bf')),btrim(p_full_name),nullif(btrim(p_phone),''),nullif(btrim(p_email),''),'active',true) returning id into v_account_id;
 insert into mb.building_memberships(building_id,account_id,unit_id,access_role,resident_type,membership_status,joined_at) values(p_building_id,v_account_id,v_unit_id,'resident',p_occupancy,'active',p_joined_at) returning id into v_member_id;
 perform public.mb_app_recalculate_expense_allocations(p_token,p_building_id);
 return jsonb_build_object('success',true,'unit_id',v_unit_id,'membership_id',v_member_id);
end; $function$;


CREATE OR REPLACE FUNCTION public.mb_app_manager_create_expense(p_token uuid, p_building_id uuid, p_description text, p_amount numeric, p_expense_date date, p_allocation_method text, p_tx_type text, p_category text, p_allocations jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_actor_id uuid;
 v_expense_id uuid;
 v_item jsonb;
 v_member_id uuid;
 v_item_amount numeric;
begin
 v_actor_id := public.mb_app_financial_v2_require_manager(p_token,p_building_id);
 if p_amount is null or p_amount <= 0 then
   raise exception 'مبلغ تراکنش نامعتبر است';
 end if;
 if nullif(btrim(p_description),'') is null then
   raise exception 'شرح تراکنش الزامی است';
 end if;

 insert into mb.building_expenses
  (building_id,description,amount,expense_date,allocation_method,tx_type,category,created_by)
 values
  (p_building_id,btrim(p_description),p_amount,coalesce(p_expense_date,current_date),
   p_allocation_method,p_tx_type,p_category,v_actor_id)
 returning id into v_expense_id;

 if p_allocation_method in ('selected','manual') then
   if p_allocations is null or jsonb_typeof(p_allocations) <> 'array'
      or jsonb_array_length(p_allocations)=0 then
     raise exception 'برای این روش تخصیص، انتخاب واحدها الزامی است';
   end if;
   for v_item in select value from jsonb_array_elements(p_allocations)
   loop
     v_member_id := (v_item->>'membership_id')::uuid;
     v_item_amount := (v_item->>'amount')::numeric;
     if v_item_amount is null or v_item_amount <= 0 then
       raise exception 'مبلغ تخصیص باید بیشتر از صفر باشد';
     end if;
     if not exists (
       select 1 from mb.building_memberships bm
       where bm.id=v_member_id and bm.building_id=p_building_id
         and bm.membership_status='active'
     ) then
       raise exception 'عضویت انتخاب‌شده متعلق به این ساختمان یا فعال نیست';
     end if;
     insert into mb.building_expense_allocations
       (building_id,expense_id,membership_id,amount)
     values (p_building_id,v_expense_id,v_member_id,v_item_amount);
   end loop;
 else
   perform public.mb_app_recalculate_expense_allocations(p_token,p_building_id);
 end if;
 return jsonb_build_object('success',true,'expense_id',v_expense_id);
end;
$function$;


CREATE OR REPLACE FUNCTION public.mb_app_manager_delete_payment(p_token uuid, p_payment_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_payment mb.building_payments;
begin
 select * into v_payment
 from mb.building_payments
 where id=p_payment_id
 for update;

 if not found then
   raise exception 'پرداخت پیدا نشد';
 end if;

 perform public.mb_app_financial_v2_require_manager(p_token,v_payment.building_id);

 delete from mb.building_payments where id=p_payment_id;
 perform public.mb_app_reallocate_member_payments(v_payment.building_id,v_payment.membership_id);

 return jsonb_build_object('success',true);
end;
$function$;


CREATE OR REPLACE FUNCTION public.mb_app_manager_delete_resident_account(p_token uuid, p_building_id uuid, p_membership_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare target mb.building_memberships;
begin
 perform public.mb_app_financial_v2_require_manager(p_token,p_building_id);
 select * into target from mb.building_memberships
 where id=p_membership_id and building_id=p_building_id for update;
 if not found then raise exception 'عضویت در این ساختمان پیدا نشد'; end if;
 if target.access_role='manager' then raise exception 'حذف حساب مدیر از این مسیر مجاز نیست'; end if;

 update mb.building_memberships
 set membership_status='inactive',ended_at=coalesce(ended_at,current_date)
 where id=p_membership_id;

 -- Rebuild charge allocations: active residents keep full charges; exited residents are prorated.
 perform public.mb_app_recalculate_expense_allocations(p_token,p_building_id);

 if target.account_id is not null and not exists(
   select 1 from mb.building_memberships
   where account_id=target.account_id and membership_status='active'
 ) then
   update mb.app_accounts set account_status='inactive' where id=target.account_id;
   delete from mb.app_sessions where account_id=target.account_id;
 end if;
 return jsonb_build_object('success',true);
end;
$function$;


CREATE OR REPLACE FUNCTION public.mb_app_manager_delete_transaction(p_token uuid, p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_building_id uuid;
    v_member record;
BEGIN
    SELECT building_id
    INTO v_building_id
    FROM mb.building_expenses
    WHERE id = p_id
      AND expense_status = 'active'
    FOR UPDATE;

    IF v_building_id IS NULL THEN
        RAISE EXCEPTION 'تراکنش فعال پیدا نشد';
    END IF;

    PERFORM public.mb_app_financial_v2_require_manager(
        p_token, v_building_id
    );

    UPDATE mb.building_expenses
    SET expense_status = 'deleted'
    WHERE id = p_id;

    FOR v_member IN
        SELECT id
        FROM mb.building_memberships
        WHERE building_id = v_building_id
    LOOP
        PERFORM public.mb_app_reallocate_member_payments(
            v_building_id,
            v_member.id
        );
    END LOOP;

    RETURN jsonb_build_object('success', true);
END;
$function$;


CREATE OR REPLACE FUNCTION public.mb_app_manager_get_fund_summary(p_token uuid, p_building_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_open numeric;v_inc numeric;v_exp numeric;v_pen numeric;v_bal numeric;
begin
 perform public.mb_app_financial_v2_require_manager(p_token,p_building_id);
 select coalesce(opening_balance,0) into v_open from mb.building_finance_settings where building_id=p_building_id;
 select coalesce(sum(amount),0) into v_inc from mb.building_payments where building_id=p_building_id and status='approved';
 select coalesce(sum(amount),0) into v_exp from mb.building_expenses where building_id=p_building_id and expense_status='active' and tx_type<>'درآمد';
 select coalesce(sum(amount),0) into v_pen from mb.building_payments where building_id=p_building_id and status='pending';
 v_bal:=coalesce(v_open,0)+v_inc-v_exp;
 return jsonb_build_object('fund_balance',v_bal,'approved_income',v_inc,'active_expenses',v_exp,
 'pending_payments_amount',v_pen,'pending_payments_count',(select count(*) from mb.building_payments where building_id=p_building_id and status='pending'),
 'active_expenses_count',(select count(*) from mb.building_expenses where building_id=p_building_id and expense_status='active' and tx_type<>'درآمد'),
 'accounting_start_date',(select accounting_start_date from mb.building_finance_settings where building_id=p_building_id),'opening_balance',v_open);
end;$function$;


CREATE OR REPLACE FUNCTION public.mb_app_manager_get_member_balances(p_token uuid, p_building_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_member record;v_members jsonb:='[]'::jsonb;v_total_exp numeric;v_total_paid numeric;v_pending numeric;
begin
 perform public.mb_app_financial_v2_require_manager(p_token,p_building_id);
 perform public.mb_app_reconcile_inactive_tenant_debts(p_token,p_building_id);
 for v_member in
  select bm.id membership_id,bm.opening_debt,u.unit_no,a.full_name,bm.resident_type,bm.access_role
  from mb.building_memberships bm
  left join mb.app_accounts a on a.id=bm.account_id
  left join mb.units u on u.id=bm.unit_id
  where bm.building_id=p_building_id and bm.membership_status='active'
 loop
  select coalesce(v_member.opening_debt,0)+coalesce(sum(ea.amount),0) into v_total_exp
  from mb.building_expense_allocations ea
  join mb.building_expenses e on e.id=ea.expense_id
  where ea.building_id=p_building_id and ea.membership_id=v_member.membership_id and e.expense_status='active';
  select coalesce(sum(amount),0) into v_total_paid from mb.building_payments
   where building_id=p_building_id and membership_id=v_member.membership_id and status='approved';
  select coalesce(sum(amount),0) into v_pending from mb.building_payments
   where building_id=p_building_id and membership_id=v_member.membership_id and status='pending';
  v_members:=v_members||jsonb_build_array(jsonb_build_object(
   'membership_id',v_member.membership_id,'unit_no',v_member.unit_no,'full_name',v_member.full_name,
   'access_role',v_member.access_role,'resident_type',v_member.resident_type,
   'outstanding_debt',case when v_member.resident_type='tenant' or v_member.access_role='manager' then round(greatest(v_total_exp-v_total_paid,0),0) else 0 end,
   'credit_balance',case when v_member.resident_type='tenant' or v_member.access_role='manager' then round(greatest(v_total_paid-v_total_exp,0),0) else 0 end,'pending_payments',v_pending));
 end loop;
 return jsonb_build_object('members',v_members);
end;$function$;


CREATE OR REPLACE FUNCTION public.mb_app_manager_get_monthly_report(p_token uuid, p_building_id uuid, p_year integer, p_month integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_start date;v_end date;v_inc numeric;v_exp numeric;v_bal numeric;v_payments jsonb;v_expenses jsonb;
begin
 perform public.mb_app_financial_v2_require_manager(p_token,p_building_id);
 if p_month not between 1 and 12 then raise exception 'ماه نامعتبر است'; end if;
 v_start:=make_date(p_year,p_month,1);v_end:=(v_start+interval '1 month - 1 day')::date;
 select coalesce(sum(amount),0) into v_inc from mb.building_payments where building_id=p_building_id and status='approved' and payment_date between v_start and v_end;
 select coalesce(sum(amount),0) into v_exp from mb.building_expenses where building_id=p_building_id and expense_status='active' and tx_type<>'درآمد' and expense_date between v_start and v_end;
 select coalesce(opening_balance,0)+v_inc-v_exp into v_bal from mb.building_finance_settings where building_id=p_building_id;
 v_bal:=coalesce(v_bal,v_inc-v_exp);
 select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'membership_id',p.membership_id,'amount',p.amount,'payment_date',p.payment_date,'description',p.description,'status',p.status) order by p.payment_date desc),'[]'::jsonb)
 into v_payments from mb.building_payments p where p.building_id=p_building_id and p.payment_date between v_start and v_end;
 select coalesce(jsonb_agg(jsonb_build_object('id',e.id,'description',e.description,'amount',e.amount,'expense_date',e.expense_date,'tx_type',e.tx_type,'category',e.category) order by e.expense_date desc),'[]'::jsonb)
 into v_expenses from mb.building_expenses e where e.building_id=p_building_id and e.expense_status='active' and e.expense_date between v_start and v_end;
 return jsonb_build_object('month_income',v_inc,'month_expenses',v_exp,'fund_balance_to_month_end',v_bal,'payments',v_payments,'expenses',v_expenses);
end;$function$;


CREATE OR REPLACE FUNCTION public.mb_app_manager_get_transactions(p_token uuid, p_building_id uuid, p_year integer DEFAULT NULL::integer, p_month integer DEFAULT NULL::integer, p_type text DEFAULT NULL::text, p_unit_no integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_txs jsonb;
begin
 perform public.mb_app_financial_v2_require_manager(p_token,p_building_id);
 select coalesce(jsonb_agg(t order by (t->>'date')::date desc),'[]'::jsonb) into v_txs from (
  select jsonb_build_object('id',e.id,'date',e.expense_date,'description',e.description,'amount',e.amount,'type',e.tx_type,'category',e.category,'status','approved',
   'unit_display',case when e.allocation_method='none' then 'کل ساختمان'
    when (select count(*) from mb.building_expense_allocations ea where ea.expense_id=e.id)>1 then 'ساختمان'
    else coalesce((select 'واحد '||u.unit_no from mb.building_expense_allocations ea join mb.building_memberships bm on bm.id=ea.membership_id join mb.units u on u.id=bm.unit_id where ea.expense_id=e.id limit 1),'ساختمان') end) t
  from mb.building_expenses e where e.building_id=p_building_id and e.expense_status='active'
   and (p_year is null or extract(year from e.expense_date)=p_year)
   and (p_month is null or extract(month from e.expense_date)=p_month)
   and (p_type is null or e.tx_type=p_type)
   and (p_unit_no is null or exists(select 1 from mb.building_expense_allocations ea join mb.building_memberships bm on bm.id=ea.membership_id join mb.units u on u.id=bm.unit_id where ea.expense_id=e.id and u.unit_no=p_unit_no))
  union all
  select jsonb_build_object('id',p.id,'date',p.payment_date,'description',coalesce(p.description,'واریز به صندوق'),'amount',p.amount,'type','واریز ساکنین','category','پرداخت','status',p.status,
   'unit_display',(select 'واحد '||u.unit_no from mb.building_memberships bm join mb.units u on u.id=bm.unit_id where bm.id=p.membership_id)) t
  from mb.building_payments p where p.building_id=p_building_id and (p_type is null or p_type='واریز ساکنین')
   and (p_year is null or extract(year from p.payment_date)=p_year)
   and (p_month is null or extract(month from p.payment_date)=p_month)
   and (p_unit_no is null or exists(select 1 from mb.building_memberships bm join mb.units u on u.id=bm.unit_id where bm.id=p.membership_id and u.unit_no=p_unit_no))
 ) x;
 return v_txs;
end;$function$;


CREATE OR REPLACE FUNCTION public.mb_app_manager_list_building_members(p_token uuid, p_building_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_members jsonb;
begin
 perform public.mb_app_financial_v2_require_manager(p_token,p_building_id);
 select coalesce(jsonb_agg(jsonb_build_object('membership_id',bm.id,'account_id',a.id,'full_name',a.full_name,'username',a.username,
  'phone',a.phone,'email',a.email,'access_role',bm.access_role,'resident_type',bm.resident_type,'membership_status',bm.membership_status,
  'unit_no',u.unit_no,'unit_area',u.area,'unit_resident_count',u.resident_count,'joined_at',bm.joined_at,'ended_at',bm.ended_at)
  order by u.unit_no),'[]'::jsonb) into v_members
 from mb.building_memberships bm left join mb.app_accounts a on a.id=bm.account_id
 left join mb.units u on u.id=bm.unit_id where bm.building_id=p_building_id
  and bm.membership_status='active' and (a.account_status is null or a.account_status<>'deleted');
 return jsonb_build_object('members',v_members);
end;$function$;


CREATE OR REPLACE FUNCTION public.mb_app_manager_list_building_requests(p_token uuid, p_building_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_reqs jsonb;
begin
 perform public.mb_app_financial_v2_require_manager(p_token,p_building_id);
 select coalesce(jsonb_agg(jsonb_build_object('request_id',r.id,'title',r.title,'description',r.description,'request_type',r.request_type,
  'request_status',r.request_status,'manager_reply',r.manager_reply,'resident_name',a.full_name,'unit_no',u.unit_no) order by r.created_at desc),'[]'::jsonb)
 into v_reqs from mb.building_requests r join mb.building_memberships bm on bm.id=r.membership_id
 left join mb.app_accounts a on a.id=bm.account_id left join mb.units u on u.id=bm.unit_id
 where r.building_id=p_building_id;
 return jsonb_build_object('requests',v_reqs);
end;$function$;


CREATE OR REPLACE FUNCTION public.mb_app_manager_list_pending_payments(p_token uuid, p_building_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_payments jsonb;
begin
 perform public.mb_app_financial_v2_require_manager(p_token,p_building_id);
 select coalesce(jsonb_agg(jsonb_build_object(
   'payment_id',p.id,'full_name',a.full_name,'unit_no',u.unit_no,
   'resident_type',bm.resident_type,'amount',p.amount,
   'payment_date',p.payment_date,'description',p.description
  ) order by p.payment_date,p.created_at),'[]'::jsonb)
 into v_payments
 from mb.building_payments p
 join mb.building_memberships bm on bm.id=p.membership_id
 join mb.app_accounts a on a.id=bm.account_id
 left join mb.units u on u.id=bm.unit_id
 where p.building_id=p_building_id and p.status='pending';
 return jsonb_build_object('payments',v_payments);
end;
$function$;


CREATE OR REPLACE FUNCTION public.mb_app_manager_list_resident_requests(p_token uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor mb.app_accounts;v_reqs jsonb;
begin
 v_actor:=public.mb_app_require_session(p_token);
 if not v_actor.is_superadmin and not exists(select 1 from mb.building_memberships bm where bm.account_id=v_actor.id and bm.access_role='manager' and bm.membership_status='active') then
  raise exception 'دسترسی مدیر لازم است';
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'full_name',r.full_name,'username',r.username,'phone',r.phone,'email',r.email,
  'requested_role',r.requested_role,'unit_no',r.unit_no,'area',r.area,'resident_count',r.resident_count,'building_id',r.building_id) order by r.created_at),'[]'::jsonb)
 into v_reqs from mb.registration_requests r
 where r.request_status='pending' and r.requested_role in ('owner','tenant','owner_resident')
 and (v_actor.is_superadmin or exists(select 1 from mb.building_memberships bm where bm.account_id=v_actor.id and bm.building_id=r.building_id and bm.access_role='manager' and bm.membership_status='active'));
 return v_reqs;
end;$function$;


CREATE OR REPLACE FUNCTION public.mb_app_manager_reply_building_request(p_token uuid, p_building_id uuid, p_request_id uuid, p_new_status text, p_manager_reply text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform public.mb_app_financial_v2_require_manager(p_token,p_building_id);
 if p_new_status not in ('new','in_progress','answered','resolved','rejected') then raise exception 'وضعیت درخواست نامعتبر است'; end if;
 update mb.building_requests set request_status=p_new_status,manager_reply=p_manager_reply
 where id=p_request_id and building_id=p_building_id;
 if not found then raise exception 'درخواست در این ساختمان پیدا نشد'; end if;
 return jsonb_build_object('success',true);
end;$function$;


CREATE OR REPLACE FUNCTION public.mb_app_manager_report_matrix(p_token uuid, p_building_id uuid, p_start date, p_end date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_result jsonb;
BEGIN
 PERFORM public.mb_app_financial_v2_require_manager(p_token,p_building_id);
 IF p_start IS NULL OR p_end IS NULL OR p_end<p_start OR p_end-p_start>45 THEN
  RAISE EXCEPTION 'بازه گزارش نامعتبر است';
 END IF;
 SELECT jsonb_build_object(
  'transactions',COALESCE((
    SELECT jsonb_agg(jsonb_build_object('id',e.id,'title',COALESCE(NULLIF(btrim(e.description),''),e.category,'تراکنش'),
      'date',e.expense_date,'category',e.category) ORDER BY e.expense_date,e.created_at,e.id)
    FROM mb.building_expenses e
    WHERE e.building_id=p_building_id AND e.expense_status='active'
      AND e.expense_date BETWEEN p_start AND p_end
      AND EXISTS (SELECT 1 FROM mb.building_expense_allocations a WHERE a.expense_id=e.id)
  ),'[]'::jsonb),
  'rows',COALESCE((
    SELECT jsonb_agg(jsonb_build_object(
      'membership_id',bm.id,'unit_no',u.unit_no,'resident_type',bm.resident_type,
      'opening_debt',COALESCE(bm.opening_debt,0),
      'previous_debt',GREATEST(0,COALESCE(bm.opening_debt,0)+COALESCE((
        SELECT SUM(a.amount) FROM mb.building_expense_allocations a
        JOIN mb.building_expenses e ON e.id=a.expense_id
        WHERE a.membership_id=bm.id AND e.expense_status='active' AND e.expense_date<p_start
      ),0)-COALESCE((
        SELECT SUM(p.amount) FROM mb.building_payments p
        WHERE p.membership_id=bm.id AND p.status='approved' AND p.payment_date<p_start
      ),0)),
      'due_to_end',GREATEST(0,COALESCE(bm.opening_debt,0)+COALESCE((
        SELECT SUM(a.amount) FROM mb.building_expense_allocations a
        JOIN mb.building_expenses e ON e.id=a.expense_id
        WHERE a.membership_id=bm.id AND e.expense_status='active' AND e.expense_date<=p_end
      ),0)-COALESCE((
        SELECT SUM(p.amount) FROM mb.building_payments p
        WHERE p.membership_id=bm.id AND p.status='approved' AND p.payment_date<=p_end
      ),0)),
      'charges',COALESCE((
        SELECT jsonb_object_agg(z.expense_id,z.amount) FROM (
          SELECT a.expense_id::text AS expense_id,SUM(a.amount) AS amount
          FROM mb.building_expense_allocations a
          JOIN mb.building_expenses e ON e.id=a.expense_id
          WHERE a.membership_id=bm.id AND e.building_id=p_building_id
            AND e.expense_status='active'
            AND e.expense_date BETWEEN p_start AND p_end
          GROUP BY a.expense_id
        ) z
      ),'{}'::jsonb)
    ) ORDER BY u.unit_no,bm.resident_type,bm.id)
    FROM mb.building_memberships bm
    JOIN mb.units u ON u.id=bm.unit_id
    WHERE bm.building_id=p_building_id AND (
      bm.membership_status='active' OR EXISTS (
        SELECT 1 FROM mb.building_expense_allocations a
        JOIN mb.building_expenses e ON e.id=a.expense_id
        WHERE a.membership_id=bm.id AND e.expense_status='active' AND e.expense_date<=p_end
      )
    )
  ),'[]'::jsonb)
 ) INTO v_result;
 RETURN v_result;
END $function$;


CREATE OR REPLACE FUNCTION public.mb_app_manager_review_payment(p_token uuid, p_payment_id uuid, p_approve boolean, p_review_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_payment mb.building_payments;
begin
 select * into v_payment from mb.building_payments where id=p_payment_id for update;
 if not found then raise exception 'پرداخت پیدا نشد'; end if;
 perform public.mb_app_financial_v2_require_manager(p_token,v_payment.building_id);
 if v_payment.status<>'pending' then raise exception 'این پرداخت قبلاً بررسی شده است'; end if;

 update mb.building_payments
 set status=case when p_approve then 'approved' else 'rejected' end,
     reviewed_at=now()
 where id=p_payment_id;

 if p_approve then
  perform public.mb_app_reallocate_member_payments(v_payment.building_id,v_payment.membership_id);
 end if;
 return jsonb_build_object('success',true);
end;
$function$;


CREATE OR REPLACE FUNCTION public.mb_app_manager_review_resident_request(p_token uuid, p_request_id uuid, p_approve boolean, p_review_note text DEFAULT NULL::text, p_join_date date DEFAULT CURRENT_DATE, p_opening_debt numeric DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 r mb.registration_requests;
 actor uuid;
 v_unit_id uuid;
 v_account_id uuid;
 v_member_id uuid;
BEGIN
 SELECT * INTO r FROM mb.registration_requests rr WHERE rr.id=p_request_id FOR UPDATE;
 IF NOT FOUND OR r.request_status<>'pending' THEN RAISE EXCEPTION 'درخواست معتبر نیست'; END IF;
 actor:=public.mb_app_financial_v2_require_manager(p_token,r.building_id);

 IF NOT p_approve THEN
   UPDATE mb.registration_requests SET request_status='rejected',review_note=p_review_note,
     reviewed_by=actor,reviewed_at=now() WHERE id=r.id;
   RETURN jsonb_build_object('success',true);
 END IF;

 IF r.requested_role NOT IN ('owner','owner_resident','tenant') THEN
   RAISE EXCEPTION 'نوع درخواست ساکن نامعتبر است';
 END IF;
 IF p_join_date IS NULL OR p_join_date>current_date OR p_opening_debt<0 THEN
   RAISE EXCEPTION 'تاریخ شروع یا بدهی اولیه نامعتبر است';
 END IF;
 IF EXISTS (SELECT 1 FROM mb.app_accounts a WHERE lower(a.username)=lower(r.username)) THEN
   RAISE EXCEPTION 'نام کاربری قبلاً استفاده شده است';
 END IF;
 SELECT u.id INTO v_unit_id FROM mb.units u
 WHERE u.building_id=r.building_id AND u.unit_no=r.unit_no FOR UPDATE;
 IF v_unit_id IS NULL THEN RAISE EXCEPTION 'واحد انتخاب‌شده در ساختار ساختمان وجود ندارد'; END IF;
 IF r.area IS NULL OR r.area<=0 THEN RAISE EXCEPTION 'متراژ واحد نامعتبر است'; END IF;
 IF r.resident_count IS NOT NULL AND r.resident_count<1 THEN RAISE EXCEPTION 'تعداد ساکنان نامعتبر است'; END IF;

 IF EXISTS (
   SELECT 1 FROM mb.registration_requests rr
   WHERE rr.id<>r.id AND rr.building_id=r.building_id AND rr.unit_no=r.unit_no
     AND rr.request_status='pending'
     AND (
       (r.requested_role IN ('owner','owner_resident') AND rr.requested_role IN ('owner','owner_resident'))
       OR (r.requested_role='tenant' AND rr.requested_role IN ('tenant','owner_resident'))
       OR (r.requested_role='owner_resident' AND rr.requested_role='tenant')
     )
 ) THEN RAISE EXCEPTION 'درخواست با درخواست دیگری که هنوز تعیین تکلیف نشده تعارض دارد'; END IF;

 IF r.requested_role IN ('owner','owner_resident') AND EXISTS (
   SELECT 1 FROM mb.building_memberships bm WHERE bm.unit_id=v_unit_id
   AND bm.membership_status='active' AND bm.resident_type IN ('owner','owner_resident')
 ) THEN RAISE EXCEPTION 'این واحد قبلاً مالک فعال دارد'; END IF;
 IF r.requested_role='tenant' AND EXISTS (
   SELECT 1 FROM mb.building_memberships bm WHERE bm.unit_id=v_unit_id
   AND bm.membership_status='active' AND bm.resident_type='tenant'
 ) THEN RAISE EXCEPTION 'این واحد قبلاً مستأجر فعال دارد'; END IF;
 IF r.requested_role='tenant' AND EXISTS (
   SELECT 1 FROM mb.building_memberships bm WHERE bm.unit_id=v_unit_id
   AND bm.membership_status='active' AND bm.resident_type='owner_resident'
 ) THEN RAISE EXCEPTION 'واحد دارای مالک ساکن فعال است'; END IF;
 IF r.requested_role='owner_resident' AND EXISTS (
   SELECT 1 FROM mb.building_memberships bm WHERE bm.unit_id=v_unit_id
   AND bm.membership_status='active' AND bm.resident_type='tenant'
 ) THEN RAISE EXCEPTION 'واحد دارای مستأجر فعال است'; END IF;

 UPDATE mb.units SET area=r.area,resident_count=coalesce(r.resident_count,1) WHERE id=v_unit_id;
 INSERT INTO mb.app_accounts(username,password_hash,full_name,phone,email,account_status,must_change_password)
 VALUES(r.username,r.requested_password_hash,r.full_name,r.phone,r.email,'active',true)
 RETURNING id INTO v_account_id;
 INSERT INTO mb.building_memberships(building_id,account_id,unit_id,access_role,resident_type,membership_status,joined_at,opening_debt)
 VALUES(r.building_id,v_account_id,v_unit_id,'resident',r.requested_role,'active',p_join_date,p_opening_debt)
 RETURNING id INTO v_member_id;
 UPDATE mb.registration_requests SET request_status='approved',reviewed_by=actor,
   reviewed_at=now(),review_note=p_review_note WHERE id=r.id;
 PERFORM public.mb_app_recalculate_expense_allocations(p_token,r.building_id);
 RETURN jsonb_build_object('success',true,'membership_id',v_member_id);
END;
$function$;


CREATE OR REPLACE FUNCTION public.mb_app_manager_set_finance_settings(p_token uuid, p_building_id uuid, p_accounting_start_date date, p_opening_balance numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor uuid;
begin
 v_actor:=public.mb_app_financial_v2_require_manager(p_token,p_building_id);
 if p_opening_balance is null then raise exception 'موجودی اولیه نامعتبر است'; end if;
 insert into mb.building_finance_settings(building_id,accounting_start_date,opening_balance,created_by,updated_by)
 values(p_building_id,p_accounting_start_date,p_opening_balance,v_actor,v_actor)
 on conflict(building_id) do update set accounting_start_date=excluded.accounting_start_date,
  opening_balance=excluded.opening_balance,updated_by=v_actor,updated_at=now();
 perform public.mb_app_recalculate_expense_allocations(p_token,p_building_id);
 return jsonb_build_object('success',true);
end;$function$;


CREATE OR REPLACE FUNCTION public.mb_app_manager_transfer_management(p_token uuid, p_building_id uuid, p_target_membership_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor uuid; current_mid uuid; target mb.building_memberships;
begin
 actor:=public.mb_app_financial_v2_require_manager(p_token,p_building_id);
 select id into current_mid from mb.building_memberships where account_id=actor and building_id=p_building_id and access_role='manager' and membership_status='active' for update;
 if current_mid is null then raise exception 'عضویت مدیر فعلی پیدا نشد'; end if;
 select * into target from mb.building_memberships where id=p_target_membership_id and building_id=p_building_id and access_role='resident' and membership_status='active' for update;
 if not found then raise exception 'ساکن مقصد معتبر نیست'; end if;
 update mb.building_memberships set access_role='resident' where id=current_mid;
 update mb.building_memberships set access_role='manager' where id=target.id;
 update mb.buildings set current_manager_membership_id=target.id where id=p_building_id;
 return jsonb_build_object('success',true,'new_manager_membership_id',target.id,'old_manager_membership_id',current_mid);
end; $function$;


CREATE OR REPLACE FUNCTION public.mb_app_manager_update_member_profile(p_token uuid, p_building_id uuid, p_membership_id uuid, p_full_name text, p_phone text, p_email text, p_resident_type text, p_resident_count integer, p_joined_at date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare target mb.building_memberships;
begin
 perform public.mb_app_financial_v2_require_manager(p_token,p_building_id); select * into target from mb.building_memberships where id=p_membership_id and building_id=p_building_id for update; if not found then raise exception 'عضویت در این ساختمان پیدا نشد'; end if;
 if target.access_role='manager' and p_resident_type<>'owner_resident' then raise exception 'مدیر فعلی باید مالک ساکن باقی بماند؛ ابتدا انتقال مدیریت انجام دهید'; end if;
 if p_resident_type not in ('owner','owner_resident','tenant') or p_joined_at is null or p_joined_at>current_date or p_resident_count is null or p_resident_count<1 then raise exception 'اطلاعات سکونت نامعتبر است'; end if;
 if p_resident_type in ('owner','owner_resident') and exists(select 1 from mb.building_memberships where unit_id=target.unit_id and id<>target.id and membership_status='active' and resident_type in ('owner','owner_resident')) then raise exception 'این واحد مالک فعال دیگری دارد'; end if;
 if p_resident_type='tenant' and exists(select 1 from mb.building_memberships where unit_id=target.unit_id and id<>target.id and membership_status='active' and resident_type='tenant') then raise exception 'این واحد مستأجر فعال دیگری دارد'; end if;
 if p_resident_type='tenant' and exists(select 1 from mb.building_memberships where unit_id=target.unit_id and id<>target.id and membership_status='active' and resident_type='owner_resident') then raise exception 'واحد دارای مالک ساکن فعال است'; end if;
 update mb.building_memberships set resident_type=p_resident_type,joined_at=p_joined_at where id=p_membership_id;
 update mb.units set resident_count=p_resident_count where id=target.unit_id and building_id=p_building_id;
 update mb.app_accounts set full_name=p_full_name,phone=p_phone,email=p_email where id=target.account_id;
 perform public.mb_app_recalculate_expense_allocations(p_token,p_building_id); return jsonb_build_object('success',true);
end; $function$;


CREATE OR REPLACE FUNCTION public.mb_app_manager_update_payment(p_token uuid, p_payment_id uuid, p_amount numeric, p_payment_date date, p_description text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
    v_payment mb.building_payments;
BEGIN
    SELECT * INTO v_payment
    FROM mb.building_payments
    WHERE id = p_payment_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'پرداخت پیدا نشد';
    END IF;

    PERFORM public.mb_app_financial_v2_require_manager(
        p_token,
        v_payment.building_id
    );

    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'مبلغ پرداخت نامعتبر است';
    END IF;

    UPDATE mb.building_payments
    SET
        amount = p_amount,
        payment_date = p_payment_date,
        description = p_description
    WHERE id = p_payment_id;

    PERFORM public.mb_app_reallocate_member_payments(
        v_payment.building_id,
        v_payment.membership_id
    );

    RETURN jsonb_build_object('success', true);
END;
$function$;


CREATE OR REPLACE FUNCTION public.mb_app_public_buildings()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_buildings jsonb;
BEGIN
    SELECT COALESCE(jsonb_agg(jsonb_build_object('building_id', id, 'building_name', name)), '[]'::jsonb) INTO v_buildings FROM mb.buildings WHERE building_status = 'active';
    RETURN v_buildings;
END; $function$;


CREATE OR REPLACE FUNCTION public.mb_app_push_delete_subscription(p_token uuid, p_endpoint text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_acc mb.app_accounts;
begin
  v_acc := public.mb_app_require_session(p_token);
  delete from mb.push_subscriptions where account_id=v_acc.id and endpoint=p_endpoint;
  return jsonb_build_object('success',true);
end $function$;


CREATE OR REPLACE FUNCTION public.mb_app_push_save_subscription(p_token uuid, p_subscription jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_acc mb.app_accounts; v_endpoint text; v_p256dh text; v_auth text;
begin
  v_acc := public.mb_app_require_session(p_token);
  v_endpoint := nullif(btrim(p_subscription->>'endpoint'),'');
  v_p256dh := nullif(btrim(p_subscription->'keys'->>'p256dh'),'');
  v_auth := nullif(btrim(p_subscription->'keys'->>'auth'),'');
  if v_endpoint is null or v_p256dh is null or v_auth is null
     or v_endpoint !~ '^https://'
     or length(v_endpoint)>2048 or length(v_p256dh)>256 or length(v_auth)>256 then
    raise exception 'اطلاعات اشتراک اعلان معتبر نیست';
  end if;
  insert into mb.push_subscriptions(account_id,endpoint,p256dh,auth,user_agent,updated_at)
  values(v_acc.id,v_endpoint,v_p256dh,v_auth,left(p_subscription->>'userAgent',500),now())
  on conflict(endpoint) do update set account_id=excluded.account_id,p256dh=excluded.p256dh,
    auth=excluded.auth,user_agent=excluded.user_agent,updated_at=now();
  return jsonb_build_object('success',true);
end $function$;


CREATE OR REPLACE FUNCTION public.mb_app_reallocate_member_payments(p_building_id uuid, p_membership_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_payment record;
 v_due record;
 v_req record;
 v_remaining numeric;
 v_take numeric;
 v_allocated numeric;
begin
 delete from mb.building_payment_allocations pa
 where pa.payment_id in (
  select p.id from mb.building_payments p
  where p.building_id=p_building_id and p.membership_id=p_membership_id
 );

 for v_payment in
  select p.id,p.amount from mb.building_payments p
  where p.building_id=p_building_id and p.membership_id=p_membership_id and p.status='approved'
  order by p.payment_date,p.created_at,p.id
 loop
  v_remaining:=v_payment.amount;

  for v_req in
   select r.expense_allocation_id,r.amount,ea.amount as due_amount
   from mb.building_payment_item_requests r
   join mb.building_expense_allocations ea on ea.id=r.expense_allocation_id
   join mb.building_expenses e on e.id=ea.expense_id
   where r.payment_id=v_payment.id and r.building_id=p_building_id
    and ea.membership_id=p_membership_id and e.expense_status='active'
   order by r.created_at
  loop
   select greatest(v_req.due_amount-coalesce(sum(pa.amount),0),0) into v_allocated
   from mb.building_payment_allocations pa
   where pa.expense_allocation_id=v_req.expense_allocation_id;
   v_take:=least(v_req.amount,v_allocated,v_remaining);
   if v_take>0 then
    insert into mb.building_payment_allocations(building_id,payment_id,expense_allocation_id,amount)
    values(p_building_id,v_payment.id,v_req.expense_allocation_id,v_take);
    v_remaining:=v_remaining-v_take;
   end if;
   exit when v_remaining<=0;
  end loop;

  if v_remaining>0 then
   for v_due in
    select ea.id,ea.amount,e.expense_date,e.created_at
    from mb.building_expense_allocations ea
    join mb.building_expenses e on e.id=ea.expense_id
    where ea.building_id=p_building_id and ea.membership_id=p_membership_id
      and e.expense_status='active'
    order by e.expense_date,e.created_at,ea.id
   loop
    select greatest(v_due.amount-coalesce(sum(pa.amount),0),0) into v_allocated
    from mb.building_payment_allocations pa
    where pa.expense_allocation_id=v_due.id;
    v_take:=least(v_allocated,v_remaining);
    if v_take>0 then
     insert into mb.building_payment_allocations(building_id,payment_id,expense_allocation_id,amount)
     values(p_building_id,v_payment.id,v_due.id,v_take);
     v_remaining:=v_remaining-v_take;
    end if;
    exit when v_remaining<=0;
   end loop;
  end if;
 end loop;
end;
$function$;


CREATE OR REPLACE FUNCTION public.mb_app_recalculate_expense_allocations(p_token uuid, p_building_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 e record;u record;m record;d date;v_start date;v_end date;v_days integer;
 v_owner uuid;v_tenant uuid;v_target uuid;v_weight numeric;v_den numeric;
 v_total numeric;v_share numeric;v_sum numeric;v_last uuid;v_existing_id uuid;
begin
 perform public.mb_app_financial_v2_require_manager(p_token,p_building_id);

 delete from mb.building_payment_allocations pa
 where pa.payment_id in(select p.id from mb.building_payments p where p.building_id=p_building_id);

 for e in select * from mb.building_expenses where building_id=p_building_id
  and expense_status='active' and allocation_method<>'manual'
 loop
  if e.allocation_method='none' then continue; end if;
  v_start:=coalesce(e.period_start,e.expense_date);v_end:=coalesce(e.period_end,e.expense_date);
  v_days:=(v_end-v_start)+1;
  if v_days<1 then raise exception 'بازه زمانی هزینه نامعتبر است'; end if;
  if exists(select 1 from mb.building_expense_allocations where expense_id=e.id and original_membership_id is not null) then continue; end if;

  -- Keep allocation rows referenced by payment-item requests; their IDs are historical references.
  delete from mb.building_expense_allocations ea
  where ea.expense_id=e.id
    and not exists(select 1 from mb.building_payment_item_requests r where r.expense_allocation_id=ea.id);

  create temp table if not exists v2_weights(membership_id uuid primary key,weight numeric not null) on commit drop;
  truncate v2_weights;

  for u in select * from mb.units where building_id=p_building_id
   and (e.selected_unit_ids is null or id=any(e.selected_unit_ids))
  loop
   for d in select generate_series(v_start,v_end,interval '1 day')::date loop
    v_owner:=null;v_tenant:=null;v_target:=null;
    select bm.id into v_owner from mb.building_memberships bm
    where bm.unit_id=u.id and bm.building_id=p_building_id
     and bm.resident_type in ('owner','owner_resident')
     and (bm.membership_status='active' or bm.ended_at is not null)
     and (
       (bm.membership_status='active' and d=v_start)
       or
       (bm.membership_status<>'active' and bm.joined_at::date<=d and (bm.ended_at is null or bm.ended_at::date>=d))
     )
    order by (bm.resident_type='owner_resident') desc,bm.joined_at desc limit 1;

    select bm.id into v_tenant from mb.building_memberships bm
    where bm.unit_id=u.id and bm.building_id=p_building_id and bm.resident_type='tenant'
     and (bm.membership_status='active' or bm.ended_at is not null)
     and (
       (bm.membership_status='active' and d=v_start)
       or
       (bm.membership_status<>'active' and bm.joined_at::date<=d and (bm.ended_at is null or bm.ended_at::date>=d))
     )
    order by bm.joined_at desc limit 1;

    if v_tenant is not null and 'tenant'=any(e.payer_roles) then v_target:=v_tenant;
    elsif v_owner is not null and ('owner'=any(e.payer_roles) or 'owner_resident'=any(e.payer_roles)) then v_target:=v_owner;
    elsif v_tenant is null then v_target:=v_owner;
    end if;
    if v_target is null then continue; end if;

    v_weight:=case
     when e.allocation_method in ('area','dynamic_per_meter') then greatest(coalesce(u.area,0),0)
     when e.allocation_method in ('residents','dynamic_per_resident') then greatest(coalesce(u.resident_count,0),0)
     else 1 end;

    -- Active memberships receive the full-period weight even if their join date is later.
    -- Inactive memberships retain day-based weight, so proration occurs on exit only.
    if exists(select 1 from mb.building_memberships bm
              where bm.id=v_target and bm.membership_status='active') then
      v_weight:=v_weight*v_days;
    end if;

    insert into v2_weights values(v_target,v_weight)
    on conflict(membership_id) do update set weight=v2_weights.weight+excluded.weight;
   end loop;
  end loop;

  select coalesce(sum(weight),0) into v_den from v2_weights;
  if v_den=0 then continue; end if;
  v_total:=case when e.allocation_method in ('dynamic_per_unit','dynamic_per_meter','dynamic_per_resident')
   then coalesce(e.input_amount,e.amount)*v_den/v_days else coalesce(e.input_amount,e.amount) end;
  v_sum:=0;v_last:=null;
  for m in select * from v2_weights order by membership_id loop
   v_share:=round(v_total*m.weight/v_den,2);

   -- Reuse an existing referenced allocation for this expense/member instead of deleting its ID.
   v_existing_id:=null;
   select ea.id into v_existing_id
   from mb.building_expense_allocations ea
   where ea.expense_id=e.id and ea.membership_id=m.membership_id
     and ea.original_membership_id is null
     and exists(select 1 from mb.building_payment_item_requests r where r.expense_allocation_id=ea.id)
   order by ea.created_at,ea.id
   limit 1
   for update;

   if v_existing_id is not null then
    update mb.building_expense_allocations set amount=v_share where id=v_existing_id;
   else
    insert into mb.building_expense_allocations(building_id,expense_id,membership_id,amount)
    values(p_building_id,e.id,m.membership_id,v_share);
   end if;

   v_sum:=v_sum+v_share;v_last:=m.membership_id;
  end loop;
  update mb.building_expense_allocations set amount=amount+(v_total-v_sum)
  where expense_id=e.id and membership_id=v_last and original_membership_id is null;
  if e.tx_type='درآمد' and e.allocation_method like 'dynamic_%' then
   update mb.building_expenses set amount=v_total where id=e.id;
  end if;
 end loop;

 for m in select id from mb.building_memberships where building_id=p_building_id loop
  perform public.mb_app_reallocate_member_payments(p_building_id,m.id);
 end loop;
end;
$function$;


CREATE OR REPLACE FUNCTION public.mb_app_reconcile_inactive_tenant_debts(p_token uuid, p_building_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_actor uuid; t record; owner_id uuid; a record; due numeric; paid numeric; transfer numeric:=0; opening numeric:=0; n integer:=0;
begin
 v_actor:=public.mb_app_financial_v2_require_manager(p_token,p_building_id);
 for t in
  select bm.id,bm.unit_id,bm.opening_debt,bm.ended_at
  from mb.building_memberships bm
  where bm.building_id=p_building_id and bm.resident_type='tenant' and bm.membership_status='inactive'
 loop
  select bm.id into owner_id
  from mb.building_memberships bm
  where bm.building_id=p_building_id and bm.unit_id=t.unit_id
    and bm.resident_type in ('owner','owner_resident') and bm.membership_status='active'
  order by (bm.resident_type='owner_resident') desc,bm.joined_at desc limit 1;
  if owner_id is null then continue; end if;

  for a in
   select ea.id,ea.expense_id,ea.amount,e.description
   from mb.building_expense_allocations ea
   join mb.building_expenses e on e.id=ea.expense_id
   where ea.building_id=p_building_id and ea.membership_id=t.id and e.expense_status='active'
     and not exists(select 1 from mb.building_expense_allocations x
                    where x.building_id=p_building_id and x.expense_id=ea.expense_id
                      and x.membership_id=owner_id and x.original_membership_id=t.id)
  loop
   select coalesce(sum(pa.amount),0) into paid
   from mb.building_payment_allocations pa where pa.expense_allocation_id=a.id;
   due:=greatest(a.amount-paid,0);
   if due>0 then
    insert into mb.building_expense_allocations(building_id,expense_id,membership_id,amount,original_membership_id,transfer_note)
    values(p_building_id,a.expense_id,owner_id,due,t.id,'انتقال بدهی مستأجر قبلی به مالک');
    transfer:=transfer+due;
   end if;
  end loop;

  if coalesce(t.opening_debt,0)>0 then
   opening:=opening+t.opening_debt;
   update mb.building_memberships set opening_debt=0 where id=t.id;
   update mb.building_memberships set opening_debt=coalesce(opening_debt,0)+t.opening_debt where id=owner_id;
  end if;
  n:=n+1;
 end loop;

 for t in select id from mb.building_memberships where building_id=p_building_id loop
  perform public.mb_app_reallocate_member_payments(p_building_id,t.id);
 end loop;
 return jsonb_build_object('success',true,'processed_memberships',n,'transferred_allocations',transfer,'transferred_opening_debt',opening);
end;$function$;


CREATE OR REPLACE FUNCTION public.mb_app_require_session(p_token uuid)
 RETURNS app_accounts
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_account mb.app_accounts;
BEGIN
    IF p_token IS NULL THEN RAISE EXCEPTION 'نشست معتبر نیست'; END IF;
    SELECT a.* INTO v_account FROM mb.app_sessions s JOIN mb.app_accounts a ON a.id = s.account_id
    WHERE s.token_hash = encode(extensions.digest(p_token::text, 'sha256'), 'hex') AND s.expires_at > now();
    IF NOT FOUND THEN RAISE EXCEPTION 'نشست منقضی شده است'; END IF;
    IF v_account.account_status <> 'active' THEN RAISE EXCEPTION 'حساب شما فعال نیست'; END IF;
    RETURN v_account;
END; $function$;


CREATE OR REPLACE FUNCTION public.mb_app_resident_get_financial_summary(p_token uuid, p_building_id uuid, p_membership_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_actor mb.app_accounts;
 v_building record;
 v_member record;
 v_total_exp numeric := 0;
 v_total_paid numeric := 0;
 v_pending numeric := 0;
 v_debt numeric := 0;
 v_credit numeric := 0;
 v_payments jsonb := '[]'::jsonb;
 v_charges jsonb := '[]'::jsonb;
begin
 v_actor := public.mb_app_require_session(p_token);

 select * into v_building
 from mb.buildings
 where id=p_building_id;
 if not found then raise exception 'ساختمان پیدا نشد'; end if;

 select bm.*,u.unit_no,u.area,u.resident_count
 into v_member
 from mb.building_memberships bm
 join mb.units u on u.id=bm.unit_id
 where bm.id=p_membership_id
   and bm.building_id=p_building_id
   and bm.membership_status='active';

 if not found then
  raise exception 'عضویت فعال در این ساختمان پیدا نشد';
 end if;

 if v_member.account_id <> v_actor.id then
  perform public.mb_app_financial_v2_require_manager(p_token,p_building_id);
 end if;

 v_total_exp := coalesce(v_member.opening_debt,0);
 select v_total_exp+coalesce(sum(ea.amount),0) into v_total_exp
 from mb.building_expense_allocations ea
 join mb.building_expenses e on e.id=ea.expense_id
 where ea.membership_id=p_membership_id and ea.building_id=p_building_id
   and e.building_id=p_building_id and e.expense_status='active';

 select coalesce(sum(amount),0) into v_total_paid
 from mb.building_payments
 where membership_id=p_membership_id and building_id=p_building_id and status='approved';

 select coalesce(sum(amount),0) into v_pending
 from mb.building_payments
 where membership_id=p_membership_id and building_id=p_building_id and status='pending';

 v_debt := case when v_member.resident_type='tenant' or v_member.access_role='manager' then greatest(0,round(v_total_exp-v_total_paid,0)) else 0 end;
 v_credit := case when v_member.resident_type='tenant' or v_member.access_role='manager' then greatest(0,round(v_total_paid-v_total_exp,0)) else 0 end;

 select coalesce(jsonb_agg(to_jsonb(x) order by x.payment_date desc),'[]'::jsonb)
 into v_payments
 from (
   select id,amount,payment_date,description,status
   from mb.building_payments
   where membership_id=p_membership_id and building_id=p_building_id
 ) x;

 /*
  * amount = مبلغ اصلی هر بدهی
  * payable_amount = مانده واقعی قابل پرداخت پس از کسر پرداخت‌های قبلی و
  *                  بستانکاری باقی‌مانده. بستانکاری از قدیمی‌ترین بدهی
  *                  به جدیدترین بدهی اعمال می‌شود.
  */
 select coalesce(jsonb_agg(to_jsonb(x) order by x.item_date desc),'[]'::jsonb)
 into v_charges
 from (
   select
     q.id,
     q.description,
     q.amount,
     q.payable_amount,
     q.item_date,
     q.item_type,
     q.transfer_note
   from (
     select
       b.id,
       b.description,
       b.amount,
       b.item_date,
       b.item_type,
       b.transfer_note,
       greatest(
         least(
           b.outstanding_amount,
           greatest(
             v_credit - coalesce(
               sum(b.outstanding_amount) over (
                 order by b.item_date asc, b.created_at asc, b.id asc
                 rows between unbounded preceding and 1 preceding
               ),0
             ),
             0
           )
         ),
         0
       ) as credit_applied,
       greatest(
         b.outstanding_amount - greatest(
           least(
             b.outstanding_amount,
             greatest(
               v_credit - coalesce(
                 sum(b.outstanding_amount) over (
                   order by b.item_date asc, b.created_at asc, b.id asc
                   rows between unbounded preceding and 1 preceding
                 ),0
               ),
               0
             )
           ),
           0
         ),
         0
       ) as payable_amount
     from (
       select
         ea.id,
         e.description,
         ea.amount,
         e.expense_date as item_date,
         e.created_at,
         'expense'::text as item_type,
         ea.transfer_note,
         greatest(
           ea.amount - coalesce((
             select sum(pa.amount)
             from mb.building_payment_allocations pa
             join mb.building_payments pp on pp.id=pa.payment_id
             where pa.expense_allocation_id=ea.id
               and pa.building_id=p_building_id
               and pp.membership_id=p_membership_id
               and pp.building_id=p_building_id
               and pp.status='approved'
           ),0),
           0
         ) as outstanding_amount
       from mb.building_expense_allocations ea
       join mb.building_expenses e on e.id=ea.expense_id
       where ea.membership_id=p_membership_id
         and ea.building_id=p_building_id
         and e.building_id=p_building_id
         and e.expense_status='active'
     ) b
   ) q
 ) x;

 return jsonb_build_object(
   'success',true,'building_id',p_building_id,'building_name',v_building.name,
   'membership_id',p_membership_id,'unit_no',v_member.unit_no,
   'resident_type',v_member.resident_type,'debt_balance',v_debt,
   'credit_balance',v_credit,'pending_payments',v_pending,
   'payments',v_payments,'charges',v_charges,
   'opening_debt',coalesce(v_member.opening_debt,0)
 );
end;
$function$;


CREATE OR REPLACE FUNCTION public.mb_app_resident_list_building_requests(p_token uuid, p_building_id uuid, p_membership_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_actor mb.app_accounts;v_reqs jsonb;
begin
 v_actor:=public.mb_app_require_session(p_token);
 if not exists(select 1 from mb.building_memberships bm where bm.id=p_membership_id
  and bm.building_id=p_building_id and bm.account_id=v_actor.id and bm.membership_status='active') then
  raise exception 'دسترسی به درخواست‌های این عضویت ندارید';
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('request_id',id,'title',title,'description',description,
  'request_type',request_type,'request_status',request_status,'manager_reply',manager_reply) order by created_at desc),'[]'::jsonb)
 into v_reqs from mb.building_requests where building_id=p_building_id and membership_id=p_membership_id;
 return v_reqs;
end;$function$;


CREATE OR REPLACE FUNCTION public.mb_app_submit_building_request(p_token uuid, p_building_id uuid, p_membership_id uuid, p_request_type text, p_title text, p_description text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor mb.app_accounts;
begin
 actor:=public.mb_app_require_session(p_token); if not exists(select 1 from mb.building_memberships where id=p_membership_id and building_id=p_building_id and account_id=actor.id and membership_status='active') then raise exception 'عضویت فعال برای ثبت درخواست پیدا نشد'; end if;
 if p_request_type not in ('repair','criticism','suggestion','complaint','other') then raise exception 'نوع درخواست نامعتبر است'; end if;
 if nullif(btrim(p_title),'') is null or nullif(btrim(p_description),'') is null then raise exception 'عنوان و شرح درخواست الزامی است'; end if;
 insert into mb.building_requests(building_id,membership_id,request_type,title,description,request_status) values(p_building_id,p_membership_id,p_request_type,btrim(p_title),btrim(p_description),'pending'); return jsonb_build_object('success',true);
end; $function$;


CREATE OR REPLACE FUNCTION public.mb_app_submit_itemized_payment(p_token uuid, p_building_id uuid, p_membership_id uuid, p_payment_date date, p_description text, p_allocations jsonb, p_total_amount numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_actor mb.app_accounts;
 v_payment_id uuid;
 v_item jsonb;
 v_ea uuid;
 v_amount numeric;
 v_sum numeric:=0;
 v_total_exp numeric:=0;
 v_total_paid numeric:=0;
 v_current_debt numeric:=0;
 v_due_remaining numeric:=0;
begin
 v_actor:=public.mb_app_require_session(p_token);

 if p_total_amount is null or p_total_amount<=0 then
  raise exception 'مبلغ پرداخت نامعتبر است';
 end if;
 if jsonb_typeof(p_allocations) is distinct from 'array' or jsonb_array_length(p_allocations)=0 then
  raise exception 'حداقل یک ردیف بدهی را انتخاب کنید';
 end if;
 if not exists(
  select 1 from mb.building_memberships bm
  where bm.id=p_membership_id and bm.building_id=p_building_id and bm.membership_status='active'
 ) then raise exception 'عضویت فعال در این ساختمان پیدا نشد'; end if;
 if not exists(
  select 1 from mb.building_memberships bm
  where bm.id=p_membership_id and bm.building_id=p_building_id
    and bm.account_id=v_actor.id and bm.membership_status='active'
 ) then perform public.mb_app_financial_v2_require_manager(p_token,p_building_id); end if;

 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
  p_membership_id::text||'|'||p_total_amount::text||'|'||coalesce(p_payment_date,current_date)::text,0
 ));

 select coalesce(bm.opening_debt,0) into v_total_exp
 from mb.building_memberships bm
 where bm.id=p_membership_id and bm.building_id=p_building_id;
 select v_total_exp+coalesce(sum(ea.amount),0) into v_total_exp
 from mb.building_expense_allocations ea
 join mb.building_expenses e on e.id=ea.expense_id
 where ea.membership_id=p_membership_id and ea.building_id=p_building_id
   and e.building_id=p_building_id and e.expense_status='active';
 select coalesce(sum(amount),0) into v_total_paid
 from mb.building_payments
 where membership_id=p_membership_id and building_id=p_building_id and status='approved';
 v_current_debt:=greatest(0,round(v_total_exp-v_total_paid,0));
 if round(p_total_amount,0)>round(v_current_debt,0) then
  raise exception 'مبلغ پرداخت بیشتر از مانده واقعی بدهی است؛ مانده قابل پرداخت: % تومان', round(v_current_debt,0);
 end if;

 if exists(
  select 1 from mb.building_payments p
  where p.building_id=p_building_id and p.membership_id=p_membership_id
   and p.amount=p_total_amount and p.payment_date=coalesce(p_payment_date,current_date)
   and p.status='pending' and p.created_at>now()-interval '2 minutes'
 ) then raise exception 'پرداخت مشابه در انتظار بررسی است؛ از ثبت مجدد خودداری شد'; end if;

 for v_item in select value from jsonb_array_elements(p_allocations) loop
  if v_item->>'type'<>'expense' then raise exception 'نوع ردیف پرداخت پشتیبانی نمی‌شود'; end if;
  v_ea:=(v_item->>'id')::uuid;
  v_amount:=(v_item->>'amount')::numeric;
  if v_amount is null or v_amount<=0 then raise exception 'مبلغ تخصیص نامعتبر است'; end if;

  select greatest(
    ea.amount-coalesce((select sum(pa.amount)
      from mb.building_payment_allocations pa
      join mb.building_payments pp on pp.id=pa.payment_id
      where pa.expense_allocation_id=ea.id
        and pp.membership_id=p_membership_id and pp.building_id=p_building_id
        and pp.status='approved'),0),0)
  into v_due_remaining
  from mb.building_expense_allocations ea
  join mb.building_expenses e on e.id=ea.expense_id
  where ea.id=v_ea and ea.membership_id=p_membership_id and ea.building_id=p_building_id
    and e.building_id=p_building_id and e.expense_status='active';
  if v_due_remaining is null then raise exception 'ردیف بدهی انتخاب‌شده معتبر نیست'; end if;
  if v_amount>v_due_remaining then
   raise exception 'مبلغ پرداخت این ردیف بیشتر از مانده خود بدهی است';
  end if;
  v_sum:=v_sum+v_amount;
 end loop;

 if round(v_sum,2)<>round(p_total_amount,2) then raise exception 'جمع ردیف‌ها با مبلغ پرداخت برابر نیست'; end if;

 insert into mb.building_payments(building_id,membership_id,amount,payment_date,description,status,created_by)
 values(p_building_id,p_membership_id,p_total_amount,coalesce(p_payment_date,current_date),p_description,'pending',v_actor.id)
 returning id into v_payment_id;

 for v_item in select value from jsonb_array_elements(p_allocations) loop
  insert into mb.building_payment_item_requests(building_id,payment_id,expense_allocation_id,amount)
  values(p_building_id,v_payment_id,(v_item->>'id')::uuid,(v_item->>'amount')::numeric);
 end loop;
 return jsonb_build_object('success',true,'payment_id',v_payment_id);
end;
$function$;


CREATE OR REPLACE FUNCTION public.mb_app_submit_registration(p_username text, p_password text, p_full_name text, p_phone text, p_email text, p_requested_role text, p_building_id uuid DEFAULT NULL::uuid, p_unit_no integer DEFAULT NULL::integer, p_area numeric DEFAULT NULL::numeric, p_resident_count integer DEFAULT NULL::integer, p_new_building_name text DEFAULT NULL::text, p_new_building_unit_count integer DEFAULT NULL::integer, p_new_building_address text DEFAULT NULL::text, p_new_building_floor_count integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
 v_role text := lower(btrim(coalesce(p_requested_role,'')));
 v_unit_id uuid;
BEGIN
 IF nullif(btrim(coalesce(p_username,'')),'') IS NULL
    OR nullif(p_password,'') IS NULL
    OR nullif(btrim(coalesce(p_full_name,'')),'') IS NULL THEN
   RAISE EXCEPTION 'نام کاربری، رمز عبور و نام و نام خانوادگی الزامی است';
 END IF;

 IF p_username !~ '^[A-Za-z0-9_]{3,32}$' THEN RAISE EXCEPTION 'نام کاربری باید ۳ تا ۳۲ نویسه انگلیسی، عدد یا زیرخط باشد'; END IF;
 IF p_password !~ '^[0-9]{4,6}$' THEN RAISE EXCEPTION 'رمز عبور باید ۴ تا ۶ رقم انگلیسی باشد'; END IF;

 IF v_role NOT IN ('manager','building_manager','owner','owner_resident','tenant') THEN
   RAISE EXCEPTION 'نوع ثبت‌نام نامعتبر است';
 END IF;

 IF EXISTS (SELECT 1 FROM mb.app_accounts a WHERE lower(a.username)=lower(btrim(p_username))) THEN
   RAISE EXCEPTION 'نام کاربری تکراری است';
 END IF;
 IF EXISTS (SELECT 1 FROM mb.registration_requests rr
            WHERE lower(rr.username)=lower(btrim(p_username)) AND rr.request_status='pending') THEN
   RAISE EXCEPTION 'برای این نام کاربری درخواست ثبت‌نام در انتظار بررسی وجود دارد';
 END IF;

 IF v_role IN ('manager','building_manager') THEN
   IF nullif(btrim(p_new_building_name),'') IS NULL THEN RAISE EXCEPTION 'نام ساختمان الزامی است'; END IF;
   IF p_new_building_unit_count IS NULL OR p_new_building_unit_count<1 OR p_new_building_unit_count>1000 THEN
     RAISE EXCEPTION 'تعداد واحد نامعتبر است';
   END IF;
   IF nullif(btrim(p_new_building_address),'') IS NULL THEN RAISE EXCEPTION 'آدرس ساختمان الزامی است'; END IF;
   IF p_new_building_floor_count IS NULL OR p_new_building_floor_count<1 OR p_new_building_floor_count>200 THEN
     RAISE EXCEPTION 'تعداد طبقات نامعتبر است';
   END IF;
   IF p_building_id IS NOT NULL OR p_unit_no IS NOT NULL THEN
     RAISE EXCEPTION 'درخواست مدیر ساختمان جدید نباید شناسه ساختمان یا شماره واحد داشته باشد';
   END IF;
 ELSE
   IF p_building_id IS NULL OR p_unit_no IS NULL OR p_unit_no<1 THEN
     RAISE EXCEPTION 'انتخاب ساختمان و شماره واحد الزامی است';
   END IF;
   IF p_area IS NULL OR p_area<=0 THEN RAISE EXCEPTION 'متراژ واحد باید بیشتر از صفر باشد'; END IF;
   IF p_resident_count IS NOT NULL AND p_resident_count<1 THEN
     RAISE EXCEPTION 'تعداد ساکنان باید حداقل یک نفر باشد';
   END IF;

   SELECT u.id INTO v_unit_id
   FROM mb.units u
   WHERE u.building_id=p_building_id AND u.unit_no=p_unit_no
   FOR UPDATE;
   IF v_unit_id IS NULL THEN RAISE EXCEPTION 'واحد انتخاب‌شده در این ساختمان وجود ندارد'; END IF;

   -- وضعیت اعضای فعال
   IF v_role IN ('owner','owner_resident') AND EXISTS (
     SELECT 1 FROM mb.building_memberships bm
     WHERE bm.unit_id=v_unit_id AND bm.membership_status='active'
       AND bm.resident_type IN ('owner','owner_resident')
   ) THEN RAISE EXCEPTION 'این واحد قبلاً مالک فعال دارد'; END IF;

   IF v_role='tenant' AND EXISTS (
     SELECT 1 FROM mb.building_memberships bm
     WHERE bm.unit_id=v_unit_id AND bm.membership_status='active'
       AND bm.resident_type='tenant'
   ) THEN RAISE EXCEPTION 'این واحد قبلاً مستأجر فعال دارد'; END IF;

   IF v_role='tenant' AND EXISTS (
     SELECT 1 FROM mb.building_memberships bm
     WHERE bm.unit_id=v_unit_id AND bm.membership_status='active'
       AND bm.resident_type='owner_resident'
   ) THEN RAISE EXCEPTION 'این واحد دارای مالک ساکن فعال است و امکان ثبت مستأجر وجود ندارد'; END IF;

   IF v_role='owner_resident' AND EXISTS (
     SELECT 1 FROM mb.building_memberships bm
     WHERE bm.unit_id=v_unit_id AND bm.membership_status='active'
       AND bm.resident_type='tenant'
   ) THEN RAISE EXCEPTION 'این واحد دارای مستأجر فعال است و امکان ثبت مالک ساکن وجود ندارد'; END IF;

   -- درخواست‌های در انتظار نیز مانع درخواست متناقض یا تکراری هستند
   IF EXISTS (
     SELECT 1 FROM mb.registration_requests rr
     WHERE rr.building_id=p_building_id AND rr.unit_no=p_unit_no
       AND rr.request_status='pending'
       AND (
         (v_role IN ('owner','owner_resident') AND rr.requested_role IN ('owner','owner_resident'))
         OR (v_role='tenant' AND rr.requested_role IN ('tenant','owner_resident'))
         OR (v_role='owner_resident' AND rr.requested_role='tenant')
       )
   ) THEN RAISE EXCEPTION 'برای این واحد درخواست متعارض یا مشابه در انتظار بررسی وجود دارد'; END IF;
 END IF;

 INSERT INTO mb.registration_requests(
   username,requested_password_hash,full_name,phone,email,requested_role,
   building_id,unit_no,area,resident_count,new_building_name,
   new_building_unit_count,new_building_address,new_building_floor_count
 ) VALUES (
   btrim(p_username),extensions.crypt(p_password,extensions.gen_salt('bf')),
   btrim(p_full_name),p_phone,p_email,v_role,p_building_id,p_unit_no,p_area,
   p_resident_count,p_new_building_name,p_new_building_unit_count,
   p_new_building_address,p_new_building_floor_count
 );
 RETURN jsonb_build_object('success',true);
END;
$function$;


CREATE OR REPLACE FUNCTION public.mb_recalculate_membership_expenses(p_membership_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE v_building_id uuid;
BEGIN
    SELECT building_id INTO v_building_id FROM mb.building_memberships WHERE id = p_membership_id;
    IF v_building_id IS NOT NULL THEN
        PERFORM public.mb_app_reallocate_member_payments(v_building_id, p_membership_id);
    END IF;
END; $function$;



-- Compatibility bridge: the same Negin 2 account can use the new multi-building
-- session while retaining a separate legacy session for the untouched old UI.
CREATE OR REPLACE FUNCTION public.mb_app_login(p_username text, p_password text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_acc mb.app_accounts;
 v_token uuid;
 v_memberships jsonb;
 v_legacy jsonb;
 v_legacy_token uuid;
begin
 select * into v_acc
 from mb.app_accounts
 where lower(username)=lower(btrim(p_username))
   and account_status='active'
   and password_hash=extensions.crypt(p_password,password_hash);
 if not found then
   return jsonb_build_object('success',false,'error','نام کاربری یا رمز عبور اشتباه است');
 end if;

 v_token:=gen_random_uuid();
 insert into mb.app_sessions(token_hash,account_id)
 values(encode(extensions.digest(v_token::text,'sha256'),'hex'),v_acc.id);

 select coalesce(jsonb_agg(jsonb_build_object(
   'membership_id',bm.id,'building_id',b.id,'building_name',b.name,
   'unit_no',u.unit_no,'access_role',bm.access_role,'resident_type',bm.resident_type,
   'membership_status',bm.membership_status,'building_status',b.building_status,
   'address',b.address,'floor_count',b.floor_count
 ) order by b.created_at desc),'[]'::jsonb)
 into v_memberships
 from mb.building_memberships bm
 join mb.buildings b on b.id=bm.building_id
 left join mb.units u on u.id=bm.unit_id
 where bm.account_id=v_acc.id and bm.membership_status='active';

 begin
   v_legacy:=public.app_login(p_login=>p_username,p_password=>p_password);
   if coalesce((v_legacy->>'success')::boolean,false) then
     v_legacy_token:=nullif(v_legacy->>'token','')::uuid;
   end if;
 exception when others then
   v_legacy_token:=null;
 end;

 return jsonb_build_object(
   'success',true,'token',v_token,'legacy_token',v_legacy_token,
   'account_id',v_acc.id,'username',v_acc.username,'full_name',v_acc.full_name,
   'is_superadmin',v_acc.is_superadmin,'must_change_password',v_acc.must_change_password,
   'memberships',v_memberships
 );
end;
$function$;

CREATE OR REPLACE FUNCTION public.mb_app_logout_all(p_token uuid, p_legacy_token uuid DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform public.mb_app_logout(p_token);
 if p_legacy_token is not null then
   perform public.app_logout(p_legacy_token);
 end if;
 return jsonb_build_object('success',true);
end;
$function$;

commit;
