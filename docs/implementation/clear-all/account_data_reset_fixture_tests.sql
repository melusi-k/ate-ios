-- Hermetic ephemeral database ONLY. NOT production. Run after candidate migration.
-- Requires auth.users fixture helper to insert these TWO fake users if absent.
-- Does not create users in a real Supabase project. Every effect rolled back.
-- SQL tests NOT executed here. Use actual authenticated role, not superuser bypass.
-- NOTE: authenticated clients have no direct INSERT/UPDATE/DELETE on user_recipes, so
-- fixtures seed rows as the provisioning role and use put_user_recipe for client writes.
begin;
-- Harness must provision these UUIDs in its own throwaway auth.users fixture.
-- Seed generation-0 legacy rows as the provisioning role (no JWT claims present).
insert into public.user_recipes(user_id,kind,id,data,updated_at,deleted)
values ('11111111-1111-4111-8111-111111111111','recipe','remote-only','{"title":"fixture"}',100,false);
insert into public.user_recipes(user_id,kind,id,data,updated_at,deleted)
values ('22222222-2222-4222-8222-222222222222','shopping','preserve-b','{"name":"fixture"}',100,false);

set local role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111', true);

-- K810: direct table writes are not a client path at all, before any reset.
do $$ begin
  begin
    delete from public.user_recipes where user_id=auth.uid();
    raise exception 'pre-reset direct delete unexpectedly succeeded';
  exception when insufficient_privilege then null; end;
  begin
    update public.user_recipes set data='{}' where user_id=auth.uid();
    raise exception 'pre-reset direct update unexpectedly succeeded';
  exception when insufficient_privilege then null; end;
  begin
    insert into public.user_recipes(user_id,kind,id,data,updated_at,deleted)
    values (auth.uid(),'recipe','direct','{}',100,false);
    raise exception 'pre-reset direct insert unexpectedly succeeded';
  exception when insufficient_privilege then null; end;
end $$;

-- K810: a client-set transaction flag is not authority. Even replaying the retired
-- flag name, the revoked grant still denies the delete.
do $$ begin
  perform set_config('app.account_data_reset','on',true);
  begin
    delete from public.user_recipes where user_id=auth.uid();
    raise exception 'flag-armed direct delete unexpectedly succeeded';
  exception when insufficient_privilege then null; end;
end $$;

-- Pre-reset baseline: generation 0 is still current, so a legacy-generation write
-- through the RPC succeeds. After the reset below, the SAME caller generation must fail.
do $$ begin
  perform public.put_user_recipe(0,'recipe','remote-only','{"title":"stale"}',9999999999999,false);
end $$;

do $$ begin
  if public.clear_account_data('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',0) <> 1 then raise exception 'wrong generation'; end if;
  if (public.account_data_snapshot()->'rows') <> '[]'::jsonb then raise exception 'rows retained'; end if;
  -- Stale caller generation after reset: write, tombstone and delete all rejected.
  begin
    perform public.put_user_recipe(0,'recipe','stale','{}',9999999999999,false);
    raise exception 'stale-generation write unexpectedly succeeded';
  exception when serialization_failure then null; end;
  begin
    perform public.put_user_recipe(0,'recipe','stale-tomb','{}',9999999999999,true);
    raise exception 'stale-generation tombstone unexpectedly succeeded';
  exception when serialization_failure then null; end;
  begin
    delete from public.user_recipes where user_id=auth.uid();
    raise exception 'post-reset direct delete unexpectedly succeeded';
  exception when insufficient_privilege then null; end;
  -- Fresh write at the returned generation succeeds and survives an idempotent retry.
  perform public.put_user_recipe(1,'recipe','new','{}',101,false);
  if public.clear_account_data('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',0) <> 1 then raise exception 'retry not idempotent'; end if;
  if jsonb_array_length(public.account_data_snapshot()->'rows') <> 1 then raise exception 'retry erased new data'; end if;
  -- A second, distinct reset advances the generation; the stale first request is rejected.
  perform public.clear_account_data('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',1);
  begin
    perform public.clear_account_data('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',0);
    raise exception 'stale reset unexpectedly succeeded';
  exception when serialization_failure then null; end;
  -- Direct state tamper is denied.
  begin
    update public.account_data_generation set generation=0 where user_id=auth.uid();
    raise exception 'direct state tamper unexpectedly succeeded';
  exception when insufficient_privilege then null; end;
end $$;

-- Account B: untouched, and the legitimate upsert path works end to end.
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222', true);
do $$ begin
  if jsonb_array_length(public.account_data_snapshot()->'rows') <> 1 then raise exception 'account B affected'; end if;
  -- Real upsert: insert then update the same key; the fresh content must win.
  perform public.put_user_recipe(0,'recipe','upsert-a','{"v":1}',200,false);
  perform public.put_user_recipe(0,'recipe','upsert-a','{"v":2}',201,false);
  if jsonb_array_length(public.account_data_snapshot()->'rows') <> 2 then raise exception 'upsert duplicated rows'; end if;
  if not exists (
    select 1 from jsonb_array_elements(public.account_data_snapshot()->'rows') r
    where r->>'id' = 'upsert-a' and r->'data' = '{"v":2}'::jsonb
  ) then raise exception 'legitimate upsert did not apply'; end if;
  -- Tombstone through the same path is fenced and applied at the current generation.
  perform public.put_user_recipe(0,'recipe','upsert-a',null,202,true);
  if not exists (
    select 1 from jsonb_array_elements(public.account_data_snapshot()->'rows') r
    where r->>'id' = 'upsert-a' and (r->>'deleted')::boolean
  ) then raise exception 'legitimate tombstone did not apply'; end if;
end $$;

-- Trusted cleanup and account-deletion paths, as the provisioning role (stand-in for
-- the migration/service/auth-admin roles; the REAL role names are a deploy-time
-- verification item and the fence fails closed until they are confirmed).
reset role;
select set_config('request.jwt.claim.sub','', true);
-- Cleanup on a REAL row: the fence must let a trusted role delete it, and it must be gone.
-- Account A is at generation 2 after the two resets above, so the seeded row carries it.
insert into public.user_recipes(user_id,kind,id,data,updated_at,deleted,data_generation)
values ('11111111-1111-4111-8111-111111111111','recipe','cleanup-target','{}',300,false,2);
delete from public.user_recipes where user_id='11111111-1111-4111-8111-111111111111' and id='cleanup-target';
do $$ begin
  if exists (select 1 from public.user_recipes where id='cleanup-target') then raise exception 'trusted cleanup failed'; end if;
end $$;
-- Account deletion cascade stand-in: seed a SECOND surviving row first so the cascade
-- actually has child rows to fire on (an empty-child cascade would prove nothing).
-- Generation 2 matches account A's state after the two resets above.
insert into public.user_recipes(user_id,kind,id,data,updated_at,deleted,data_generation)
values ('11111111-1111-4111-8111-111111111111','recipe','cascade-target','{}',301,false,2);
-- Deleting the auth.users row must cascade through user_recipes and
-- account_data_generation without the fence blocking it, and must not touch account B.
delete from auth.users where id='11111111-1111-4111-8111-111111111111';
do $$ begin
  if exists (select 1 from public.user_recipes where user_id='11111111-1111-4111-8111-111111111111') then raise exception 'cascade left user_recipes incl. cascade-target'; end if;
  if exists (select 1 from public.account_data_generation where user_id='11111111-1111-4111-8111-111111111111') then raise exception 'cascade left generation state'; end if;
  if not exists (select 1 from public.user_recipes where user_id='22222222-2222-4222-8222-222222222222') then raise exception 'cascade hit account B'; end if;
end $$;
rollback;
-- REQUIRED separate two-connection concurrency suite is not replaced by these:
-- 1. hold old put_user_recipe tx open, launch reset, release write; all old rows gone.
-- 2. hold reset state lock, launch old put_user_recipe; after commit stale write rejects.
-- 3. interleave snapshot/reset; never return new generation with old rows.
-- 4. handle serialization/deadlock retry with SAME request ID.
-- 5. direct DELETE/tombstone are denied independent of timing; no concurrency case remains.
