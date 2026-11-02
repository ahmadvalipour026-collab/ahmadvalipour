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
  v_super_token uuid;
  v_bridge jsonb;
  v_reset jsonb;
  v_login jsonb;
  v_legacy_reset text;
  v_legacy_forgot jsonb;
  v_account_id uuid;
  v_phone text;
  v_invalid boolean;
  v_manager_membership uuid;
  v_test_expense uuid;
  v_test_allocation uuid;
  v_financial_summary jsonb;
  v_payment_result jsonb;
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
  if not exists(select 1 from mb.app_accounts
    where id='f37d021f-2fb2-4911-956f-2371d4ae71a1'::uuid
      and username='admin' and is_superadmin and account_status='active') then
    raise exception 'FAIL: original global super-admin identity was not preserved';
  end if;
  if exists(select 1 from mb.building_memberships bm
    join mb.app_accounts a on a.id=bm.account_id
    where bm.building_id=v_building and bm.access_role='manager' and a.is_superadmin) then
    raise exception 'FAIL: Negin 2 building manager was incorrectly promoted to super-admin';
  end if;
  if not exists(select 1 from mb.buildings where id=v_building
    and building_status='active') then
    raise exception 'FAIL: Negin 2 must be imported as an already-approved active building';
  end if;

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

  -- Check net opening balances against the legacy billing engine.
  -- Positive balances are materialized as charge items; negative balances stay as account credit.
  if exists(
    with recursive months(account_id,unit_no,occupancy,ym) as (
      select a.id,a.unit_no,a.occupancy,coalesce(a.start_ym,140406)
      from public.accounts a where a.building_id=1 and a.is_active
      union all
      select m.account_id,m.unit_no,m.occupancy,public.bm_next_ym(m.ym)
      from months m where m.ym<140508
    ),
    dues as (
      select m.account_id,
        sum(coalesce(d.charge,0)+coalesce(d.water,0)+coalesce(d.gas,0)
          +coalesce(d.repair,0)+coalesce(d.parking,0))::numeric total_due
      from months m cross join lateral public.bm_account_month_due(m.account_id,m.ym) d
      group by m.account_id
    ),
    paid as (
      select a.id account_id,coalesce(sum(t.amount),0)::numeric total_paid
      from public.accounts a left join public.transactions t
        on t.unit_no=a.unit_no and t.occupancy=a.occupancy
       and t.tx_type='درآمد' and t.building_id=1
      where a.building_id=1 group by a.id
    ),
    expected as (
      select a.id account_id,
        case when a.is_admin or a.occupancy='مستأجر'
          then coalesce(d.total_due,0)-coalesce(p.total_paid,0) else 0 end net_balance
      from public.accounts a left join dues d on d.account_id=a.id
      left join paid p on p.account_id=a.id where a.building_id=1
    )
    select 1
    from expected x
    join mb.building_memberships bm on bm.account_id=x.account_id and bm.building_id=v_building
    where (x.net_balance<=0 and bm.opening_debt is distinct from x.net_balance)
       or (x.net_balance>0 and (
         bm.opening_debt<>0 or
         round(coalesce((select sum(ea.amount) from mb.building_expense_allocations ea
           join mb.building_expenses e on e.id=ea.expense_id
           where ea.membership_id=bm.id and e.description='مانده بدهی انتقالی #'||bm.id::text),0),2)
           <>round(x.net_balance,2)
       ))
  ) then raise exception 'FAIL: opening debt/credit ledger differs from legacy net balance'; end if;

  -- Test the bridge using a temporary legacy session.
  select id into v_admin_id from public.accounts where building_id=1 and is_admin=true limit 1;
  insert into public.sessions(account_id) values(v_admin_id) returning token into v_legacy_token;
  v_bridge:=public.mb_app_bridge_legacy_session(v_legacy_token);
  if coalesce((v_bridge->>'success')::boolean,false) is not true then
    raise exception 'FAIL: legacy-to-multi-building session bridge failed';
  end if;
  v_multi_token:=(v_bridge->>'token')::uuid;

  -- Use a transaction-local session for the original global super-admin.
  v_super_token:=gen_random_uuid();
  insert into mb.app_sessions(token_hash,account_id)
  values(encode(extensions.digest(v_super_token::text,'sha256'),'hex'),
    'f37d021f-2fb2-4911-956f-2371d4ae71a1'::uuid);

  -- Regression test: keep each charge visible and subtract carried credit only once at the final total.
  select id into v_manager_membership from mb.building_memberships
  where building_id=v_building and access_role='manager' and membership_status='active' limit 1;
  update mb.building_memberships set opening_debt=-300 where id=v_manager_membership;
  insert into mb.building_expenses(building_id,description,amount,expense_date,allocation_method,tx_type,category,expense_status)
  values(v_building,'Regression test charge',1000,current_date,'direct','هزینه','سایر','active')
  returning id into v_test_expense;
  insert into mb.building_expense_allocations(building_id,expense_id,membership_id,amount)
  values(v_building,v_test_expense,v_manager_membership,1000)
  returning id into v_test_allocation;

  v_financial_summary:=public.mb_app_resident_get_financial_summary(v_multi_token,v_building,v_manager_membership);
  if (v_financial_summary->>'account_balance')::numeric<>700
     or (v_financial_summary->>'debt_balance')::numeric<>700
     or (v_financial_summary->>'credit_applied')::numeric<>300
     or (v_financial_summary->>'credit_balance')::numeric<>0
     or ((v_financial_summary->'charges'->0->>'amount')::numeric)<>1000
     or ((v_financial_summary->'charges'->0->>'outstanding_amount')::numeric)<>1000 then
    raise exception 'FAIL: credit must be deducted at the final total while the original charge remains visible';
  end if;
  v_payment_result:=public.mb_app_submit_itemized_payment(
    v_multi_token,v_building,v_manager_membership,current_date,'Regression test payment',
    jsonb_build_array(jsonb_build_object('type','expense','id',v_test_allocation::text,'amount',700)),700
  );
  if coalesce((v_payment_result->>'success')::boolean,false) is not true then
    raise exception 'FAIL: net itemized payment after credit deduction was not accepted';
  end if;

  -- Verify the old Negin 2 account-management RPCs enforce the same rule.
  select id,phone into v_account_id,v_phone
  from public.accounts where username='negin1';
  v_legacy_reset:=public.app_admin_reset_password(v_legacy_token,v_account_id);
  if v_legacy_reset !~ '^[0-9]{6}$' then
    raise exception 'FAIL: legacy manager reset password is not six numeric digits';
  end if;
  v_legacy_forgot:=public.app_reset_password('negin1',v_phone,'abcd');
  if coalesce((v_legacy_forgot->>'ok')::boolean,true) then
    raise exception 'FAIL: legacy forgot-password accepted a non-numeric password';
  end if;
  v_invalid:=false;
  begin
    perform public.app_admin_save_account(
      v_legacy_token,null,10,'invaliduser','Test User',null,'مالک ساکن',
      false,false,'abcd',140406
    );
  exception when others then
    v_invalid:=true;
  end;
  if not v_invalid then raise exception 'FAIL: legacy manager accepted an invalid initial password'; end if;

  v_reset:=public.mb_app_admin_reset_manager_password(v_super_token,v_building);
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
