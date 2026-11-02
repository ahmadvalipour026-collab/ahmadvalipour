-- Import Negin 2 as the first multi-building tenant.
-- This migration runs in the SAME database as the legacy app. It only writes to mb.*.
-- Legacy public.* data, RPCs, sessions, receipts and history remain untouched.
begin;

do $$
declare
  v_building_id uuid := 'c4f8b0de-4db5-4e3a-9a6f-2c98c3d4e201'::uuid;
  v_manager_id uuid;
begin
  if not exists (select 1 from mb.buildings where id=v_building_id) then
    insert into mb.buildings(id,name,building_status,unit_count)
    select v_building_id,b.name,'active',count(u.unit_no)::integer
    from public.buildings b
    join public.units u on u.building_id=b.id
    where b.id=1
    group by b.id,b.name;
  end if;

  if not exists (select 1 from mb.buildings where id=v_building_id and name='مجتمع نگین ۲') then
    raise exception 'Negin 2 building identity conflict; import aborted';
  end if;

  insert into mb.units(building_id,unit_no,area,resident_count)
  select v_building_id,u.unit_no,coalesce(u.area,0),greatest(coalesce(u.persons,1),1)
  from public.units u
  where u.building_id=1
  on conflict (building_id,unit_no) do update
    set area=excluded.area,resident_count=excluded.resident_count;

  -- Existing account UUIDs and password hashes are preserved.
  insert into mb.app_accounts(
    id,username,password_hash,full_name,phone,email,account_status,
    must_change_password,is_superadmin,created_at
  )
  select a.id,a.username,a.password_hash,coalesce(nullif(a.full_name,''),a.username),
         a.phone,a.email,
         case when a.is_active then 'active' else 'suspended' end,
         a.must_change_password,
         a.is_admin,
         coalesce(a.created_at,now())
  from public.accounts a
  where a.building_id=1
  on conflict (id) do nothing;

  -- Calculate the current unpaid amount from the legacy billing engine.
  -- Historical transactions/rates remain in public.*; only the current
  -- outstanding balance is carried into opening_debt.
  with recursive months(account_id,unit_no,occupancy,ym) as (
    select a.id,a.unit_no,a.occupancy,coalesce(a.start_ym,140406)
    from public.accounts a
    where a.building_id=1 and a.is_active
    union all
    select m.account_id,m.unit_no,m.occupancy,public.bm_next_ym(m.ym)
    from months m
    where m.ym<140508
  ),
  dues as (
    select m.account_id,m.unit_no,m.occupancy,m.ym,
           d.charge,d.water,d.gas,d.repair,d.parking
    from months m
    cross join lateral public.bm_account_month_due(m.account_id,m.ym) d
  ),
  paid as (
    select a.id account_id,t.year*100+t.month ym,
      coalesce(sum(t.amount) filter(where t.category='charge'),0) charge_paid,
      coalesce(sum(t.amount) filter(where t.category='water'),0) water_paid,
      coalesce(sum(t.amount) filter(where t.category='gas'),0) gas_paid,
      coalesce(sum(t.amount) filter(where t.category='repair'),0) repair_paid,
      coalesce(sum(t.amount) filter(where t.category='parking'),0) parking_paid
    from public.accounts a
    left join public.transactions t
      on t.unit_no=a.unit_no and t.occupancy=a.occupancy
     and t.tx_type='درآمد' and t.building_id=1
    where a.building_id=1
    group by a.id,t.year,t.month
  ),
  balances as (
    select d.account_id,
      sum(greatest(coalesce(d.charge,0)-coalesce(p.charge_paid,0),0)
         +greatest(coalesce(d.water,0)-coalesce(p.water_paid,0),0)
         +greatest(coalesce(d.gas,0)-coalesce(p.gas_paid,0),0)
         +greatest(coalesce(d.repair,0)-coalesce(p.repair_paid,0),0)
         +greatest(coalesce(d.parking,0)-coalesce(p.parking_paid,0),0))::numeric debt
    from dues d
    left join paid p on p.account_id=d.account_id and p.ym=d.ym
    group by d.account_id
  )
  insert into mb.building_memberships(
    building_id,account_id,unit_id,access_role,resident_type,
    membership_status,joined_at,opening_debt
  )
  select v_building_id,a.id,u.id,
    case when a.is_admin then 'manager' else 'resident' end,
    case a.occupancy when 'مالک' then 'owner'
      when 'مستأجر' then 'tenant' else 'owner_resident' end,
    case when a.is_active then 'active' else 'inactive' end,
    coalesce(a.created_at,now()),
    case when a.is_admin or a.occupancy='مستأجر' then coalesce(b.debt,0) else 0 end
  from public.accounts a
  join mb.units u on u.building_id=v_building_id and u.unit_no=a.unit_no
  left join balances b on b.account_id=a.id
  where a.building_id=1
    and not exists (
      select 1 from mb.building_memberships x
      where x.building_id=v_building_id and x.account_id=a.id
    );

  select bm.id into v_manager_id
  from mb.building_memberships bm
  where bm.building_id=v_building_id and bm.access_role='manager'
    and bm.membership_status='active'
  order by bm.joined_at
  limit 1;

  if v_manager_id is null then
    raise exception 'Active Negin 2 manager account was not found; import aborted';
  end if;

  update mb.buildings
  set current_manager_membership_id=v_manager_id
  where id=v_building_id;

  insert into mb.building_finance_settings(
    building_id,accounting_start_date,opening_balance,created_by,updated_by
  )
  select v_building_id,date '2025-08-23',
         coalesce((select nullif(value,'')::numeric from public.settings where key='opening_balance'),0),
         (select id from public.accounts where building_id=1 and is_admin=true limit 1),
         (select id from public.accounts where building_id=1 and is_admin=true limit 1)
  on conflict (building_id) do nothing;
end $$;

commit;
