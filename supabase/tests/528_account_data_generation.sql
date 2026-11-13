-- ISOLATED LOCAL/STAGING DATABASE ONLY, after migrations. Never production.
-- Run with psql -v ON_ERROR_STOP=1 -f ... as local postgres. Rolls fixtures back.
begin;


insert into auth.users(id) values
 ('00000000-0000-4000-8000-000000000528'),
 ('00000000-0000-4000-8000-000000000529');
create function pg_temp.require(ok boolean, message text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'FAIL: %', message; end if; end $$;
create function pg_temp.expect_error(statement text, expected text) returns void language plpgsql as $$
begin
  begin execute statement;
  exception when others then
    if sqlstate = expected then return; end if;
    raise exception 'wrong SQLSTATE %, expected %', sqlstate, expected;
  end;
  raise exception 'statement unexpectedly succeeded: %', statement;
end $$;
select pg_temp.require(not has_table_privilege('authenticated','public.user_recipes','INSERT'), 'direct insert revoked');
select pg_temp.require(not has_table_privilege('authenticated','public.user_recipes','UPDATE'), 'direct update revoked');
select pg_temp.require(not has_table_privilege('authenticated','public.user_recipes','DELETE'), 'direct delete revoked');
select pg_temp.require(not has_table_privilege('authenticated','public.account_data_generation','SELECT'), 'generation private');
select pg_temp.require(not has_function_privilege('anon','public.account_data_snapshot()','EXECUTE'), 'anon snapshot denied');
select pg_temp.require(not has_function_privilege('anon','public.clear_account_data(uuid,bigint)','EXECUTE'), 'anon reset denied');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000528',true);
select pg_temp.require((public.account_data_snapshot()->>'generation')::bigint=0, 'first generation zero');
select public.put_user_recipe(0,'recipe','r1','{"title":"fixture"}',10,false);
select public.put_user_recipe(0,'recipe','r1','{"title":"older"}',1,false);
select pg_temp.require(public.account_data_snapshot()->'rows'->0->'data'->>'title'='fixture', 'older write cannot overwrite');
select public.put_user_recipe(0,'recipe','r1','{"title":"z"}',10,false);
select pg_temp.require(public.account_data_snapshot()->'rows'->0->'data'->>'title'='fixture', 'equal timestamp retains server');
-- Reverse payload arrival on separate ID, then remove fixture using reset later.
select public.put_user_recipe(0,'shopping','tie-reverse','{"title":"z"}',10,false);
select public.put_user_recipe(0,'shopping','tie-reverse','{"title":"a"}',10,false);
select pg_temp.require((select data->>'title'='z' from public.user_recipes where id='tie-reverse'), 'reverse arrival retains first server payload');
select public.put_user_recipe(0,'shopping','tie-reverse',null,10,true);
select public.put_user_recipe(0,'shopping','tie-reverse','{"title":"live"}',10,false);
select pg_temp.require((select deleted from public.user_recipes where id='tie-reverse'), 'tombstone first then live stays deleted');
select public.put_user_recipe(0,'recipe','r1',null,10,true);
select public.put_user_recipe(0,'recipe','r1','{"title":"resurrect"}',10,false);
select pg_temp.require((public.account_data_snapshot()->'rows'->0->>'deleted')::boolean, 'equal timestamp tombstone wins');
-- Both owners have live records before isolation checks or either reset.
select public.put_user_recipe(0,'recipe','live-a','{"owner":"A"}',11,false);
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000529',true);
select public.put_user_recipe(0,'recipe','live-b','{"owner":"B"}',11,false);
select pg_temp.require((select count(*)=1 from public.user_recipes), 'B direct SELECT excludes A');
select pg_temp.require(jsonb_array_length(public.account_data_snapshot()->'rows')=1, 'B snapshot excludes A');
select pg_temp.require(public.account_data_snapshot()->'rows'->0->>'id'='live-b', 'B snapshot actual owner row');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000528',true);
select pg_temp.require((select count(*)=3 from public.user_recipes), 'A direct SELECT excludes B');
select pg_temp.require(not exists(select 1 from public.user_recipes where id='live-b'), 'A cannot SELECT B live row');
select pg_temp.require(not exists(select 1 from jsonb_array_elements(public.account_data_snapshot()->'rows') r where r->>'id'='live-b'), 'A snapshot excludes live B');
select pg_temp.require(jsonb_array_length(public.account_data_snapshot()->'rows')=3, 'snapshot row visible');
select pg_temp.require(public.account_data_snapshot()->'rows'->0->>'user_id'='00000000-0000-4000-8000-000000000528', 'owner scope');
select pg_temp.expect_error($q$insert into public.user_recipes(user_id,kind,id,updated_at) values ('00000000-0000-4000-8000-000000000528','recipe','bypass',1)$q$,'42501');
select pg_temp.expect_error($q$update public.user_recipes set updated_at=2$q$,'42501');
select pg_temp.expect_error($q$delete from public.user_recipes$q$,'42501');
select pg_temp.expect_error($q$select public.put_user_recipe(-1,'recipe','r1','{}',1,false)$q$,'22023');
select pg_temp.expect_error($q$select public.put_user_recipe(0,'recipe','','{}',1,false)$q$,'22023');
select pg_temp.expect_error($q$select public.put_user_recipe(0,'recipe','r1',null,1,false)$q$,'22023');
select pg_temp.require(public.clear_account_data('00000000-0000-4000-8000-000000000001',0)=1, 'reset returns next generation');
select pg_temp.require(jsonb_array_length(public.account_data_snapshot()->'rows')=0, 'reset removes owner rows');
select pg_temp.require(public.clear_account_data('00000000-0000-4000-8000-000000000001',0)=1, 'same reset idempotent');
select pg_temp.expect_error($q$select public.clear_account_data('00000000-0000-4000-8000-000000000001',1)$q$,'40001');
select pg_temp.expect_error($q$select public.put_user_recipe(0,'recipe','r1','{}',2,false)$q$,'40001');
select public.put_user_recipe(1,'shopping','s1','{"name":"rice"}',3,false);
select public.put_user_recipe(1,'shopping','s1',null,4,true);
select pg_temp.require((public.account_data_snapshot()->'rows'->0->>'deleted')::boolean, 'tombstone retained');
select pg_temp.require(public.clear_account_data('00000000-0000-4000-8000-000000000002',1)=2, 'second reset');
select pg_temp.expect_error($q$select public.clear_account_data('00000000-0000-4000-8000-000000000001',0)$q$,'40001');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000529',true);
select pg_temp.require((public.account_data_snapshot()->>'generation')::bigint=0, 'other owner unaffected');
select pg_temp.require(jsonb_array_length(public.account_data_snapshot()->'rows')=1, 'B live row survives A reset');
select set_config('request.jwt.claim.sub','',true);
select pg_temp.expect_error('select public.account_data_snapshot()','42501');
reset role;
set local role anon;
select pg_temp.expect_error('select public.account_data_snapshot()','42501');
select pg_temp.expect_error($q$select public.put_user_recipe(0,'recipe','anon','{}',1,false)$q$,'42501');
select pg_temp.expect_error($q$select public.clear_account_data('00000000-0000-4000-8000-000000000003',0)$q$,'42501');
reset role;
-- Bypass probes: effective checks must catch column grants and inherited grants.
-- Fixtures roll back locally; these grants must NEVER be made in production.
-- Re-run the exact migration guard under deliberately bad effective ACLs.
create function pg_temp.run_deployment_guard() returns void language plpgsql as $probe$
begin execute $statement$do $guard$
declare fn regprocedure; col record; fixture uuid := pg_catalog.gen_random_uuid();
        allowed constant text[] := array['postgres','service_role','supabase_admin','supabase_auth_admin'];
begin
  if not (current_user = any(allowed)) then
    raise exception 'Unreviewed migration/definer owner %', current_user;
  end if;
  if exists (select 1 from pg_catalog.pg_roles r
      where r.rolname = any(allowed) and
        (pg_catalog.pg_has_role('authenticated',r.oid,'MEMBER')
         or pg_catalog.pg_has_role('anon',r.oid,'MEMBER'))) then
    raise exception 'Client inherits a privileged delete-fence role';
  end if;
  if not exists(select 1 from pg_catalog.pg_roles where rolname='supabase_auth_admin') then
    raise exception 'Required cascade role absent';
  end if;
  foreach fn in array array['public.account_data_snapshot()'::regprocedure,
    'public.put_user_recipe(bigint,text,text,jsonb,bigint,boolean)'::regprocedure,
    'public.clear_account_data(uuid,bigint)'::regprocedure,
    'public.enforce_account_data_generation()'::regprocedure] loop
    if (select pg_catalog.pg_get_userbyid(proowner) from pg_catalog.pg_proc where oid=fn) <> current_user then
      raise exception 'Unexpected RPC owner %', fn;
    end if;
    if pg_catalog.has_function_privilege('anon',fn,'EXECUTE')
       or (fn <> 'public.enforce_account_data_generation()'::regprocedure and
           not pg_catalog.has_function_privilege('authenticated',fn,'EXECUTE'))
       or (fn = 'public.enforce_account_data_generation()'::regprocedure and
           pg_catalog.has_function_privilege('authenticated',fn,'EXECUTE')) then
      raise exception 'Unexpected effective RPC grants %', fn;
    end if;
  end loop;
  -- Effective checks include inherited/table/column grants, not only ACL text.
  for col in select attname from pg_catalog.pg_attribute
    where attrelid='public.user_recipes'::regclass and attnum>0 and not attisdropped loop
    if pg_catalog.has_column_privilege('authenticated','public.user_recipes',col.attname,'INSERT')
       or pg_catalog.has_column_privilege('authenticated','public.user_recipes',col.attname,'UPDATE')
       or pg_catalog.has_column_privilege('anon','public.user_recipes',col.attname,'INSERT')
       or pg_catalog.has_column_privilege('anon','public.user_recipes',col.attname,'UPDATE') then
      raise exception 'Direct column or inherited write grant remains: %',col.attname;
    end if;
  end loop;
  if pg_catalog.has_table_privilege('authenticated','public.user_recipes','DELETE')
     or pg_catalog.has_table_privilege('anon','public.user_recipes','DELETE')
     or pg_catalog.has_table_privilege('authenticated','public.account_data_generation','SELECT,INSERT,UPDATE,DELETE')
     or pg_catalog.has_table_privilege('anon','public.account_data_generation','SELECT,INSERT,UPDATE,DELETE') then
    raise exception 'Unexpected effective direct privileges';
  end if;
  -- Exercise actual cascade as auth-admin, not just the migration owner. These
  -- synthetic fixtures are deleted here; any failure aborts the entire migration.
  -- This can fire auth.users integration hooks: run only during approved cutover.
  if auth.uid() is not null then raise exception 'Migration must not carry an end-user JWT'; end if;
  insert into auth.users(id) values(fixture);
  insert into public.user_recipes(user_id,kind,id,data,updated_at)
    values(fixture,'recipe','528-deployment-probe','{}',0);
  execute 'set local role supabase_auth_admin';
  delete from auth.users where id=fixture;
  execute 'reset role';
  if exists(select 1 from public.user_recipes where user_id=fixture)
     or exists(select 1 from public.account_data_generation where user_id=fixture) then
    raise exception 'Auth-admin cascade/delete fence verification failed';
  end if;
end $guard$;$statement$; end $probe$;
savepoint bypass_column;
grant update(data) on public.user_recipes to authenticated;
select pg_temp.require(has_column_privilege('authenticated','public.user_recipes','data','UPDATE'), 'column grant bypass detectable');
select pg_temp.expect_error('select pg_temp.run_deployment_guard()','P0001');
rollback to bypass_column;
savepoint bypass_inherited;
create role qa_528_inherited nologin;
grant qa_528_inherited to authenticated;
grant insert on public.user_recipes to qa_528_inherited;
select pg_temp.require(has_table_privilege('authenticated','public.user_recipes','INSERT'), 'inherited grant bypass detectable');
select pg_temp.expect_error('select pg_temp.run_deployment_guard()','P0001');
rollback to bypass_inherited;
rollback;
