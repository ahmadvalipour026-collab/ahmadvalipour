-- Run after applying 202611030001 and 202611030002 in a staging copy.
-- This is read-only validation; it does not alter application data.
do $$
declare
  v_building uuid := 'c4f8b0de-4db5-4e3a-9a6f-2c98c3d4e201'::uuid;
  v_units integer;
  v_accounts integer;
  v_memberships integer;
  v_managers integer;
  v_superadmins integer;
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
  raise notice 'PASS: Negin 2 multi-building import baseline validated';
end $$;
