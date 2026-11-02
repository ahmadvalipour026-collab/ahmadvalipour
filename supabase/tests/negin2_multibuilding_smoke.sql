-- Run after applying both migrations in a staging copy.
-- This test is safe to execute inside a transaction and roll back.
do $$
declare
  v_building uuid := 'c4f8b0de-4db5-4e3a-9a6f-2c98c3d4e201'::uuid;
  v_units integer;
  v_accounts integer;
  v_memberships integer;
  v_managers integer;
  v_superadmins integer;
  v_admin_id uuid;
  v_legacy_token uuid;
  v_multi_token uuid;
  v_bridge jsonb;
  v_reset jsonb;
  v_login jsonb;
  v_invalid boolean;
begin
  select count(*) into v_units from mb.units where building_id=v_building;
  select count(*) into v_accounts
  from mb.app_accounts a
  join mb.building_memberships bm on bm.account_id=a.id
  where bm.building_id=v_building;
  select count(*) into v_memberships
  from mb.building_memberships where building_id=v_building;
  select count(*) into v_managers
  from mb.building_memberships
  where building_id=v_building and membership_status='active' and access_role='manager';
  select count(*) into v_superadmins
  from mb.app_accounts a
  where a.is_superadmin and a.account_status='active';

  if not exists(select 1 from mb.buildings where id=v_building and name='مجتمع نگین ۲') then
    raise exception 'FAIL: Negin 2 building row missing';
  end if;
  if v_units<>10 then raise exception 'FAIL: expected 10 units, found %',v_units; end if;
  if v_accounts<>12 then raise exception 'FAIL: expected 12 linked accounts, found %',v_accounts; end if;
  if v_memberships<>12 then raise exception 'FAIL: expected 12 memberships, found %',v_memberships; end if;
  if v_managers<>1 then raise exception 'FAIL: expected exactly one active manager, found %',v_managers; end if;
  if v_superadmins<>1 then raise exception 'FAIL: expected exactly one active super-admin, found %',v_superadmins; end if;

  if not exists(
    select 1 from mb.buildings b
    join mb.building_memberships m on m.id=b.current_manager_membership_id
    where b.id=v_building and m.access_role='manager' and m.membership_status='active'
  ) then raise exception 'FAIL: current manager pointer is invalid'; end if;

  if exists(
    select 1 from mb.building_memberships
    where building_id=v_building and resident_type in ('owner','owner_resident')
      and access_role<>'manager' and opening_debt<>0
  ) then raise exception 'FAIL: owner debt should not be carried into the new debt ledger'; end if;

  if to_regprocedure('public.app_login(text,text)') is null
     or to_regprocedure('public.app_logout(uuid)') is null then
    raise exception 'FAIL: legacy Negin 2 login/logout RPCs were replaced';
  end if;
  if to_regprocedure('public.mb_app_login(text,text)') is null
     or to_regprocedure('public.mb_app_bridge_legacy_session(uuid)') is null then
    raise exception 'FAIL: multi-building login bridge RPCs are missing';
  end if;
  if (select count(*) from pg_tables where schemaname='mb' and rowsecurity)<>14 then
    raise exception 'FAIL: not all 14 isolated tables have RLS enabled';
  end if;
  if has_table_privilege('anon','mb.app_accounts','SELECT')
     or has_table_privilege('authenticated','mb.app_accounts','SELECT') then
    raise exception 'FAIL: direct client access to isolated account table is not revoked';
  end if;
  if exists(
    select 1 from public.accounts a
    join mb.app_accounts m on m.id=a.id
    where a.building_id=1
      and (m.username is distinct from a.username
        or m.password_hash is distinct from a.password_hash)
  ) then raise exception 'FAIL: legacy account identity/hash was not preserved'; end if;

  -- Check that opening debt exactly matches the legacy billing engine.
  if exists(
    with recursive months(account_id,unit_no,occupancy,ym) as (
      select a.id,a.unit_no,a.occupancy,coalesce(a.start_ym,140406)
      from public.accounts a where a.building_id=1 and a.is_active
      union all
      select m.account_id,m.unit_no,m.occupancy,public.bm_next_ym(m.ym)
      from months m where m.ym<140508
    ),
    dues as (
      select m.account_id,m.ym,d.charge,d.water,d.gas,d.repair,d.parking
      from months m cross join lateral public.bm_account_month_due(m.account_id,m.ym) d
    ),
    paid as (
      select a.id account_id,t.year*100+t.month ym,
        coalesce(sum(t.amount) filter(where t.category='charge'),0) charge_paid,
        coalesce(sum(t.amount) filter(where t.category='water'),0) water_paid,
        coalesce(sum(t.amount) filter(where t.category='gas'),0) gas_paid,
        coalesce(sum(t.amount) filter(where t.category='repair'),0) repair_paid,
        coalesce(sum(t.amount) filter(where t.category='parking'),0) parking_paid
      from public.accounts a
      left join public.transactions t on t.unit_no=a.unit_no and t.occupancy=a.occupancy
        and t.tx_type='درآمد' and t.building_id=1
      where a.building_id=1 group by a.id,t.year,t.month
    ),
    balances as (
      select d.account_id,
        sum(greatest(coalesce(d.charge,0)-coalesce(p.charge_paid,0),0)
          +greatest(coalesce(d.water,0)-coalesce(p.water_paid,0),0)
          +greatest(coalesce(d.gas,0)-coalesce(p.gas_paid,0),0)
          +greatest(coalesce(d.repair,0)-coalesce(p.repair_paid,0),0)
          +greatest(coalesce(d.parking,0)-coalesce(p.parking_paid,0),0))::numeric debt
      from dues d left join paid p on p.account_id=d.account_id and p.ym=d.ym
      group by d.account_id
    )
    select 1
    from public.accounts a
    join mb.building_memberships bm on bm.account_id=a.id and bm.building_id=v_building
    left join balances b on b.account_id=a.id
    where bm.opening_debt is distinct from
      case when a.is_admin or a.occupancy='مستأجر' then coalesce(b.debt,0) else 0 end
  ) then raise exception 'FAIL: imported opening debt differs from the legacy billing engine'; end if;

  -- Test the bridge using a temporary legacy session.
  select id into v_admin_id from public.accounts where building_id=1 and is_admin=true limit 1;
  insert into public.sessions(account_id) values(v_admin_id) returning token into v_legacy_token;
  v_bridge:=public.mb_app_bridge_legacy_session(v_legacy_token);
  if coalesce((v_bridge->>'success')::boolean,false) is not true then
    raise exception 'FAIL: legacy-to-multi-building session bridge failed';
  end if;
  v_multi_token:=(v_bridge->>'token')::uuid;

  v_reset:=public.mb_app_admin_reset_manager_password(v_multi_token,v_building);
  if (v_reset->>'temp_password') !~ '^[0-9]{6}$' then
    raise exception 'FAIL: manager reset password is not six numeric digits';
  end if;

  v_invalid:=false;
  begin
    perform public.mb_app_change_password(v_multi_token,'abcd');
  exception when others then
    v_invalid:=true;
  end;
  if not v_invalid then raise exception 'FAIL: invalid password change was accepted'; end if;

  v_invalid:=false;
  begin
    perform public.mb_app_submit_registration(
      'invalid_user','abcd','Test User',null,null,'manager',
      null,null,null,null,'Test Building',1,'Test Address',1
    );
  exception when others then
    v_invalid:=true;
  end;
  if not v_invalid then raise exception 'FAIL: non-numeric registration password was accepted'; end if;

  -- Test direct login with a disposable account; the outer transaction rolls it back.
  insert into mb.app_accounts(id,username,password_hash,full_name,account_status,is_superadmin)
  values(gen_random_uuid(),'testmulti',extensions.crypt('1234',extensions.gen_salt('bf')),'Test Multi','active',false);
  v_login:=public.mb_app_login('testmulti','1234');
  if coalesce((v_login->>'success')::boolean,false) is not true
     or nullif(v_login->>'token','') is null then
    raise exception 'FAIL: direct multi-building login failed';
  end if;
  perform public.mb_app_logout((v_login->>'token')::uuid);
  perform public.mb_app_logout_all(v_multi_token,v_legacy_token);
  if exists(select 1 from public.sessions where token=v_legacy_token and revoked_at is null) then
    raise exception 'FAIL: legacy session was not revoked by combined logout';
  end if;

  raise notice 'PASS: Negin 2 multi-building import, security and session checks validated';
end $$;
