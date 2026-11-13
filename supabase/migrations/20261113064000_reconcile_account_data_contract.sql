-- #528 FORWARD RECONCILIATION REVIEW CANDIDATE. No production execution here.
-- Targets existing recorded migrations20261113042539 +20261113042557, not create-only v6.
-- Replaces three existing function bodies. No grants, table/trigger/policy changes,
-- row rewrites, reset, identity creation/deletion, or object drops. Rerunnable.
-- Permanent conflicts are PT409 (HTTP409), not retryable class40 SQLSTATEs.
-- Existing cloud-write gap is retained. Activation remains a separate qualified step.
-- Run only after Reviewer rechecks live preconditions and cutover/backup authority.
begin;
do $reconcile$
declare
  fn regprocedure;
  col record;
  client text;
  before_functions jsonb;
  after_functions jsonb;
  untouched_functions jsonb;
  after_untouched jsonb;
  before_tables jsonb;
  after_tables jsonb;
  signatures constant text[] := array[
    'public.account_data_snapshot()',
    'public.clear_account_data(uuid,bigint)',
    'public.enforce_account_data_generation()',
    'public.put_user_recipe(bigint,text,text,jsonb,bigint,boolean)',
    'public.user_recipes_delete_fence()'];
  allowed constant text[] := array['postgres','service_role','supabase_admin','supabase_auth_admin'];
begin
  -- The attached live capture establishes postgres ownership, RLS, existing
  -- triggers and current ACLs. Refuse drift; do not silently create or repair.
  if current_user <> 'postgres' or auth.uid() is not null then
    raise exception 'Reconciliation requires postgres without an end-user JWT';
  end if;
  if to_regclass('public.account_data_generation') is null
     or to_regclass('public.user_recipes') is null then
    raise exception 'Existing generation schema required; do not use this as initial migration';
  end if;
  if exists (select 1 from pg_catalog.pg_roles r
      where r.rolname = any(allowed) and
       (pg_catalog.pg_has_role('authenticated',r.oid,'MEMBER')
        or pg_catalog.pg_has_role('anon',r.oid,'MEMBER'))) then
    raise exception 'Client inherits privileged role';
  end if;
  foreach client in array array['anon','authenticated'] loop
    if pg_catalog.has_table_privilege(client,'public.account_data_generation','SELECT,INSERT,UPDATE,DELETE')
       or pg_catalog.has_table_privilege(client,'public.user_recipes','INSERT,UPDATE,DELETE') then
      raise exception 'Unexpected effective direct privileges for %',client;
    end if;
    for col in select attname from pg_catalog.pg_attribute
        where attrelid='public.user_recipes'::regclass and attnum>0 and not attisdropped loop
      if pg_catalog.has_column_privilege(client,'public.user_recipes',col.attname,'INSERT')
         or pg_catalog.has_column_privilege(client,'public.user_recipes',col.attname,'UPDATE') then
        raise exception 'Unexpected column write privilege for %.%',client,col.attname;
      end if;
    end loop;
  end loop;
  if not pg_catalog.has_table_privilege('authenticated','public.user_recipes','SELECT')
     or pg_catalog.has_table_privilege('anon','public.user_recipes','SELECT') then
    raise exception 'Unexpected recipe read grants';
  end if;
  foreach fn in array array[
    'public.account_data_snapshot()'::regprocedure,
    'public.clear_account_data(uuid,bigint)'::regprocedure,
    'public.enforce_account_data_generation()'::regprocedure,
    'public.put_user_recipe(bigint,text,text,jsonb,bigint,boolean)'::regprocedure,
    'public.user_recipes_delete_fence()'::regprocedure] loop
    if (select pg_catalog.pg_get_userbyid(proowner) from pg_catalog.pg_proc where oid=fn) <> 'postgres'
       or pg_catalog.has_function_privilege('anon',fn,'EXECUTE')
       or not pg_catalog.has_function_privilege('service_role',fn,'EXECUTE') then
      raise exception 'Unexpected owner/anon/service ACL for %',fn;
    end if;
    if pg_catalog.has_function_privilege('authenticated',fn,'EXECUTE') <>
       (fn = any(array['public.account_data_snapshot()'::regprocedure,
                      'public.clear_account_data(uuid,bigint)'::regprocedure,
                      'public.put_user_recipe(bigint,text,text,jsonb,bigint,boolean)'::regprocedure])) then
      raise exception 'Unexpected authenticated RPC ACL for %',fn;
    end if;
  end loop;
  if (select count(*) from pg_catalog.pg_class where oid=any(array[
       'public.user_recipes'::regclass,'public.account_data_generation'::regclass])
       and relrowsecurity and relowner='postgres'::regrole) <> 2 then
    raise exception 'Unexpected RLS/table ownership';
  end if;
  if not exists (select 1 from pg_catalog.pg_trigger
      where tgrelid='public.user_recipes'::regclass and tgname='account_data_generation_fence'
        and tgfoid='public.enforce_account_data_generation()'::regprocedure and tgenabled='O' and tgtype=23)
     or not exists (select 1 from pg_catalog.pg_trigger
      where tgrelid='public.user_recipes'::regclass and tgname='user_recipes_delete_fence'
        and tgfoid='public.user_recipes_delete_fence()'::regprocedure and tgenabled='O' and tgtype=11) then
    raise exception 'Expected generation/delete triggers missing or changed';
  end if;
  -- Snapshot exact object identities/ACLs/config, not just effective booleans.
  select jsonb_agg(jsonb_build_array(p.oid,p.proowner,p.proacl,p.prosecdef,p.proconfig) order by p.oid)
    into before_functions from pg_catalog.pg_proc p
    where p.oid = any(array(select x::regprocedure::oid from unnest(signatures) x));
  select jsonb_agg(pg_catalog.pg_get_functiondef(x::regprocedure::oid) order by x)
    into untouched_functions from unnest(array['public.account_data_snapshot()',
       'public.user_recipes_delete_fence()']) x;
  select jsonb_agg(jsonb_build_array(oid,relowner,relacl,relrowsecurity) order by oid)
    into before_tables from pg_catalog.pg_class
    where oid=any(array['public.user_recipes'::regclass,'public.account_data_generation'::regclass]);
  execute $ddl$
create or replace function public.enforce_account_data_generation() returns trigger
language plpgsql security definer set search_path = '' as $$
declare current_generation bigint;
begin
  if auth.uid() is not null and auth.uid() <> new.user_id then
    raise exception 'Account owner required' using errcode = '42501';
  end if;
  insert into public.account_data_generation(user_id) values(new.user_id) on conflict do nothing;
  select generation into current_generation from public.account_data_generation
    where user_id = new.user_id for share;
  if new.data_generation <> current_generation then
    raise exception 'Account data was cleared; discard old local data and fetch a fresh snapshot'
      using errcode = 'PT409';
  end if;
  return new;
end $$;
$ddl$;

  execute $ddl$
create or replace function public.put_user_recipe(p_caller_generation bigint, p_kind text, p_id text,
                                       p_data jsonb, p_updated_at bigint, p_deleted boolean)
returns void
language plpgsql security definer set search_path = '' as $$
declare owner_id uuid := auth.uid(); current_generation bigint;
begin
  if owner_id is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if p_caller_generation is null or p_caller_generation < 0
     or p_kind is null or p_kind not in ('recipe', 'shopping')
     or p_id is null or length(p_id) = 0
     or p_updated_at is null or p_updated_at < 0 or p_deleted is null
     or (not p_deleted and p_data is null) then
    raise exception 'Invalid generation or record' using errcode = '22023';
  end if;
  insert into public.account_data_generation(user_id) values(owner_id) on conflict do nothing;
  select generation into current_generation from public.account_data_generation
    where user_id = owner_id for share;
  if p_caller_generation <> current_generation then
    raise exception 'Account data was cleared; discard old local data and fetch a fresh snapshot'
      using errcode = 'PT409';
  end if;
  insert into public.user_recipes as r (user_id, kind, id, data, updated_at, deleted, data_generation)
  values (owner_id, p_kind, p_id, p_data, p_updated_at, p_deleted, p_caller_generation)
  on conflict (user_id, kind, id) do update
    set data = excluded.data, updated_at = excluded.updated_at,
        deleted = excluded.deleted, data_generation = excluded.data_generation
    where excluded.updated_at > r.updated_at
       or (excluded.updated_at = r.updated_at and excluded.deleted and not r.deleted);
end $$;
$ddl$;

  execute $ddl$
create or replace function public.clear_account_data(request_id uuid, expected_generation bigint) returns bigint
language plpgsql security definer set search_path = '' as $$
declare owner_id uuid := auth.uid(); current_generation bigint; previous_request uuid;
begin
  if owner_id is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if request_id is null or expected_generation is null or expected_generation < 0 then
    raise exception 'Invalid reset request' using errcode = '22023';
  end if;
  insert into public.account_data_generation(user_id) values(owner_id) on conflict do nothing;
  select generation,last_reset_request into current_generation,previous_request
    from public.account_data_generation where user_id=owner_id for update;
  if previous_request=request_id then
    if expected_generation < 9223372036854775807 then
      if current_generation = expected_generation + 1 then return current_generation; end if;
    end if;
    raise exception 'Reset retry generation mismatch' using errcode='PT409';
  end if;
  if expected_generation = 9223372036854775807 then
    raise exception 'Reset generation exhausted' using errcode='22023';
  end if;
  if current_generation <> expected_generation then
    raise exception 'Reset generation changed; verify status before another reset' using errcode='PT409';
  end if;
  update public.account_data_generation set generation=generation+1,last_reset_request=request_id where user_id=owner_id
    returning generation into current_generation;
  -- Physical delete as the function owner (security definer): passes the delete fence.
  delete from public.user_recipes where user_id=owner_id;
  return current_generation;
end $$;
$ddl$;
  select jsonb_agg(jsonb_build_array(p.oid,p.proowner,p.proacl,p.prosecdef,p.proconfig) order by p.oid)
    into after_functions from pg_catalog.pg_proc p
    where p.oid = any(array(select x::regprocedure::oid from unnest(signatures) x));
  select jsonb_agg(pg_catalog.pg_get_functiondef(x::regprocedure::oid) order by x)
    into after_untouched from unnest(array['public.account_data_snapshot()',
       'public.user_recipes_delete_fence()']) x;
  select jsonb_agg(jsonb_build_array(oid,relowner,relacl,relrowsecurity) order by oid)
    into after_tables from pg_catalog.pg_class
    where oid=any(array['public.user_recipes'::regclass,'public.account_data_generation'::regclass]);
  if after_functions is distinct from before_functions
     or after_tables is distinct from before_tables
     or after_untouched is distinct from untouched_functions then
    raise exception 'Object identity, ACL, security config or untouched body changed; transaction aborted';
  end if;
end $reconcile$;
notify pgrst, 'reload schema';
commit;
