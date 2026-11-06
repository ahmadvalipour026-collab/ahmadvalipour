-- Secure single-building management handover workflow for Negin 2
create table if not exists public.management_transfer_requests (
  id bigint generated always as identity primary key,
  building_id integer not null references public.buildings(id),
  requested_by uuid not null references public.accounts(id),
  target_account_id uuid not null references public.accounts(id),
  status text not null default 'pending'
    check (status in ('pending','accepted','rejected','cancelled')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  constraint management_transfer_not_self check (requested_by <> target_account_id)
);

create unique index if not exists management_transfer_one_pending_per_building
  on public.management_transfer_requests(building_id) where status = 'pending';

alter table public.management_transfer_requests enable row level security;
revoke all on public.management_transfer_requests from anon, authenticated;

create or replace function public.app_management_transfer_info(p_token uuid)
returns jsonb language plpgsql security definer set search_path = 'pg_catalog', 'public'
as $function$
declare me public.accounts; v_outgoing jsonb := null; v_incoming jsonb := null; v_candidates jsonb := '[]'::jsonb;
begin
  me := public.bm_auth(p_token);
  if me.is_admin then
    select jsonb_build_object('id', r.id, 'status', r.status, 'created_at', r.created_at,
      'target_account_id', r.target_account_id, 'target_name', coalesce(a.full_name, a.username), 'target_unit', a.unit_no)
    into v_outgoing from public.management_transfer_requests r
    join public.accounts a on a.id = r.target_account_id
    where r.building_id = me.building_id and r.requested_by = me.id
    order by r.created_at desc limit 1;
    select coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'name', coalesce(a.full_name, a.username),
      'username', a.username, 'unit_no', a.unit_no) order by a.unit_no, a.full_name), '[]'::jsonb)
    into v_candidates from public.accounts a
    where a.building_id = me.building_id and a.is_active = true and a.is_admin = false;
  else
    select jsonb_build_object('id', r.id, 'created_at', r.created_at,
      'manager_name', coalesce(a.full_name, a.username), 'manager_unit', a.unit_no)
    into v_incoming from public.management_transfer_requests r
    join public.accounts a on a.id = r.requested_by
    where r.building_id = me.building_id and r.target_account_id = me.id and r.status = 'pending'
    order by r.created_at desc limit 1;
  end if;
  return jsonb_build_object('is_admin', me.is_admin, 'outgoing', v_outgoing,
    'incoming', v_incoming, 'candidates', v_candidates);
end;
$function$;

create or replace function public.app_management_transfer_create(p_token uuid, p_target_account_id uuid)
returns jsonb language plpgsql security definer set search_path = 'pg_catalog', 'public'
as $function$
declare me public.accounts; target public.accounts; v_id bigint;
begin
  me := public.bm_admin(p_token);
  select * into target from public.accounts where id = p_target_account_id for update;
  if not found or target.is_active is not true or target.is_admin is true
     or target.building_id is distinct from me.building_id or target.id = me.id then
    raise exception 'جانشین انتخاب‌شده معتبر نیست؛ فقط ساکن فعال همین ساختمان قابل انتخاب است';
  end if;
  insert into public.management_transfer_requests(building_id, requested_by, target_account_id)
  values(me.building_id, me.id, target.id) returning id into v_id;
  return jsonb_build_object('ok', true, 'request_id', v_id);
exception when unique_violation then raise exception 'یک درخواست انتقال مدیریت در حال بررسی است';
end;
$function$;

create or replace function public.app_management_transfer_cancel(p_token uuid)
returns jsonb language plpgsql security definer set search_path = 'pg_catalog', 'public'
as $function$
declare me public.accounts; v_id bigint;
begin
  me := public.bm_admin(p_token);
  update public.management_transfer_requests set status='cancelled', responded_at=now()
  where building_id=me.building_id and requested_by=me.id and status='pending' returning id into v_id;
  if v_id is null then raise exception 'درخواست در حال انتظاری برای لغو وجود ندارد'; end if;
  return jsonb_build_object('ok',true);
end;
$function$;

create or replace function public.app_management_transfer_respond(p_token uuid, p_request_id bigint, p_accept boolean)
returns jsonb language plpgsql security definer set search_path = 'pg_catalog', 'public'
as $function$
declare me public.accounts; req public.management_transfer_requests; old_manager public.accounts;
begin
  me := public.bm_auth(p_token);
  select * into req from public.management_transfer_requests
  where id=p_request_id and target_account_id=me.id and status='pending' for update;
  if not found then raise exception 'درخواست معتبر یا در حال انتظاری برای شما وجود ندارد'; end if;
  if me.is_admin or req.building_id is distinct from me.building_id then
    raise exception 'این درخواست برای حساب شما معتبر نیست';
  end if;
  if not p_accept then
    update public.management_transfer_requests set status='rejected', responded_at=now() where id=req.id;
    return jsonb_build_object('ok',true,'status','rejected');
  end if;
  select * into old_manager from public.accounts
  where id=req.requested_by and building_id=req.building_id for update;
  if not found or old_manager.is_admin is not true then raise exception 'مدیر فعلی تغییر کرده است؛ انتقال انجام نشد'; end if;
  update public.accounts set is_admin=false, updated_at=now() where id=old_manager.id;
  update public.accounts set is_admin=true, updated_at=now() where id=me.id and is_active=true;
  update public.management_transfer_requests set status='accepted', responded_at=now() where id=req.id;
  insert into public.activity_logs(account_id,unit_no,full_name,action,details,actor_id,building_id)
  values(me.id,me.unit_no,me.full_name,'انتقال مدیریت','مدیریت ساختمان با پذیرش درخواست به این حساب منتقل شد',old_manager.id,me.building_id);
  return jsonb_build_object('ok',true,'status','accepted');
end;
$function$;

revoke all on function public.app_management_transfer_info(uuid) from public;
revoke all on function public.app_management_transfer_create(uuid,uuid) from public;
revoke all on function public.app_management_transfer_cancel(uuid) from public;
revoke all on function public.app_management_transfer_respond(uuid,bigint,boolean) from public;
grant execute on function public.app_management_transfer_info(uuid) to anon, authenticated;
grant execute on function public.app_management_transfer_create(uuid,uuid) to anon, authenticated;
grant execute on function public.app_management_transfer_cancel(uuid) to anon, authenticated;
grant execute on function public.app_management_transfer_respond(uuid,bigint,boolean) to anon, authenticated;
