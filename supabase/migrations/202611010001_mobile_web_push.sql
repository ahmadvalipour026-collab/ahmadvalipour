-- Mobile Web Push notifications
-- Run this file in Supabase SQL Editor.

create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  account_id uuid not null references public.accounts(id) on delete cascade,
  building_id integer not null,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  user_agent text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists push_subscriptions_account_idx
  on public.push_subscriptions(account_id);
create index if not exists push_subscriptions_building_idx
  on public.push_subscriptions(building_id);

alter table public.push_subscriptions enable row level security;

create or replace function public.app_push_save_subscription(
  p_token uuid,
  p_endpoint text,
  p_p256dh text,
  p_auth text,
  p_user_agent text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account public.accounts;
  v_rows integer;
begin
  v_account := public.bm_auth(p_token);
  if v_account.id is null or coalesce(v_account.is_active, false) = false then
    raise exception 'AUTH_REQUIRED: نشست معتبر نیست';
  end if;
  if length(coalesce(p_endpoint, '')) < 20 or length(p_endpoint) > 2048
     or length(coalesce(p_p256dh, '')) < 20 or length(p_p256dh) > 256
     or length(coalesce(p_auth, '')) < 8 or length(p_auth) > 256 then
    raise exception 'اطلاعات اشتراک اعلان نامعتبر است';
  end if;

  insert into public.push_subscriptions
    (account_id, building_id, endpoint, p256dh, auth, user_agent, updated_at)
  values
    (v_account.id, v_account.building_id, p_endpoint, p_p256dh, p_auth,
     left(coalesce(p_user_agent, ''), 500), now())
  on conflict (endpoint) do update set
    account_id = excluded.account_id,
    building_id = excluded.building_id,
    p256dh = excluded.p256dh,
    auth = excluded.auth,
    user_agent = excluded.user_agent,
    updated_at = now()
  where public.push_subscriptions.account_id = excluded.account_id;

  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    raise exception 'این اشتراک اعلان به حساب دیگری تعلق دارد';
  end if;

  return jsonb_build_object('ok', true);
end;
$$;

create or replace function public.app_push_delete_subscription(
  p_token uuid,
  p_endpoint text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account public.accounts;
begin
  v_account := public.bm_auth(p_token);
  if v_account.id is null or coalesce(v_account.is_active, false) = false then
    raise exception 'AUTH_REQUIRED: نشست معتبر نیست';
  end if;

  delete from public.push_subscriptions
   where account_id = v_account.id and endpoint = p_endpoint;

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on public.push_subscriptions from public, anon, authenticated;
revoke all on function public.app_push_save_subscription(uuid,text,text,text,text) from public;
revoke all on function public.app_push_delete_subscription(uuid,text) from public;
grant execute on function public.app_push_save_subscription(uuid,text,text,text,text) to anon, authenticated;
grant execute on function public.app_push_delete_subscription(uuid,text) to anon, authenticated;
