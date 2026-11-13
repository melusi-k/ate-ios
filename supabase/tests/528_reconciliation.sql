-- DISPOSABLE LOCAL DATABASE ONLY. psql as postgres, ON_ERROR_STOP=1.
-- This file intentionally creates roles/schema and installs the captured prior
-- deployment; NEVER point it at Supabase production or any populated database.
\set ON_ERROR_STOP on
\ir 528_auth_shim.sql
-- Supabase's captured functions retain service_role EXECUTE. Model that existing
-- default here; this fixture grant is NOT part of the reconciliation migration.
alter default privileges for role postgres in schema public grant execute on functions to service_role;
\ir ../migrations/20261010000000_user_recipes.sql
\ir fixtures/528-production/20261113042539-recorded.sql
\ir fixtures/528-production/20261113042557-recorded.sql

-- Persistent local fixture spans reconciliation commits to prove rows kept.
insert into auth.users(id) values('00000000-0000-4000-8000-000000000530');
insert into public.account_data_generation(user_id,generation,last_reset_request)
 values('00000000-0000-4000-8000-000000000530',7,'00000000-0000-4000-8000-000000000007');
insert into public.user_recipes(user_id,kind,id,data,updated_at,deleted,data_generation)
 values('00000000-0000-4000-8000-000000000530','recipe','kept','{"fixture":"keep exactly"}',123,false,7);
create temporary table reconcile_rows_before as select to_jsonb(r) row from public.user_recipes r;
create temporary table reconcile_generation_before as select to_jsonb(r) row from public.account_data_generation r;
create temporary table reconcile_acl_before as
 select oid,proowner,proacl,prosecdef,proconfig from pg_proc where oid=any(array[
 'public.account_data_snapshot()'::regprocedure,'public.clear_account_data(uuid,bigint)'::regprocedure,
 'public.put_user_recipe(bigint,text,text,jsonb,bigint,boolean)'::regprocedure,
 'public.enforce_account_data_generation()'::regprocedure,'public.user_recipes_delete_fence()'::regprocedure]);
\ir ../migrations/20261113064000_reconcile_account_data_contract.sql
\ir ../migrations/20261113064000_reconcile_account_data_contract.sql
-- Twice applied: byte-equivalent logical rows, receipts, OIDs, ACLs unchanged.
do $test$
begin
 if exists ((select row from reconcile_rows_before except select to_jsonb(r) from public.user_recipes r)
    union all (select to_jsonb(r) from public.user_recipes r except select row from reconcile_rows_before))
 or exists ((select row from reconcile_generation_before except select to_jsonb(r) from public.account_data_generation r)
    union all (select to_jsonb(r) from public.account_data_generation r except select row from reconcile_generation_before)) then
   raise exception 'Reconciliation changed retained rows or generation receipts';
 end if;
 if exists(select 1 from reconcile_acl_before b left join pg_proc p using(oid)
    where p.oid is null or (p.proowner,p.proacl,p.prosecdef,p.proconfig)
      is distinct from (b.proowner,b.proacl,b.prosecdef,b.proconfig)) then
   raise exception 'Reconciliation changed function identities/security/grants';
 end if;
end $test$;
-- Existing full contract fixture covers LWW/tombstone, owner isolation, reset,
-- same-UUID wrong-expected/stale retries, anon denial and effective-grant probes.
\ir 528_account_data_generation.sql

begin;
create function pg_temp.reconcile_expect_error(statement text, expected text) returns void language plpgsql as $$
begin
 begin execute statement;
 exception when others then
   if sqlstate=expected then return; end if;
   raise exception 'wrong SQLSTATE %, expected %',sqlstate,expected;
 end;
 raise exception 'unexpected success: %',statement;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000530',true);
select pg_temp.reconcile_expect_error($q$select public.put_user_recipe(7,null,'bad','{}',1,false)$q$,'22023');
select pg_temp.reconcile_expect_error($q$select public.put_user_recipe(7,'other','bad','{}',1,false)$q$,'22023');
select pg_temp.reconcile_expect_error($q$select public.put_user_recipe(7,'recipe',null,'{}',1,false)$q$,'22023');
select pg_temp.reconcile_expect_error($q$select public.put_user_recipe(7,'recipe','bad','{}',null,false)$q$,'22023');
select pg_temp.reconcile_expect_error($q$select public.put_user_recipe(7,'recipe','bad','{}',-1,false)$q$,'22023');
select pg_temp.reconcile_expect_error($q$select public.put_user_recipe(7,'recipe','bad','{}',1,null)$q$,'22023');
select pg_temp.reconcile_expect_error($q$select public.put_user_recipe(null,'recipe','bad','{}',1,false)$q$,'22023');
select pg_temp.reconcile_expect_error($q$select public.put_user_recipe(6,'recipe','stale','{}',999,false)$q$,'PT409');
-- Same UUID whose actual receipt is7 only accepts expected6. expected7 is not a new reset.
select pg_temp.reconcile_expect_error($q$select public.clear_account_data('00000000-0000-4000-8000-000000000007',7)$q$,'PT409');
select public.clear_account_data('00000000-0000-4000-8000-000000000007',6);
reset role;
-- Trigger itself must use PT409 for a privileged stale write, independent of put.
select set_config('request.jwt.claim.sub','',true);
select pg_temp.reconcile_expect_error($q$insert into public.user_recipes(user_id,kind,id,data,updated_at,data_generation)
 values('00000000-0000-4000-8000-000000000530','recipe','trigger-stale','{}',1,6)$q$,'PT409');
-- Exhaustion fixture is local and rolled back. No bigint overflow evaluation.
update public.account_data_generation set generation=9223372036854775807 where user_id='00000000-0000-4000-8000-000000000530';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000530',true);
select pg_temp.reconcile_expect_error($q$select public.clear_account_data('00000000-0000-4000-8000-000000000008',9223372036854775807)$q$,'22023');
select pg_temp.reconcile_expect_error($q$select public.clear_account_data('00000000-0000-4000-8000-000000000007',9223372036854775807)$q$,'PT409');
rollback;
