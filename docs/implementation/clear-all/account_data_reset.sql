-- CANDIDATE ONLY. NOT deployed. Coordinated iOS + watch protocol upgrade required.
-- No account deletion, public-share deletion, billing or telemetry mutation.
-- Do NOT deploy independently of reset-aware clients + rollout/recovery UX.
-- K810 revision (2026-11-05): generation enforcement is a PRIVILEGE boundary, not a
-- column comparison. Authenticated clients cannot INSERT/UPDATE/DELETE user_recipes
-- directly at all; every write carries an explicit caller generation through the
-- RPCs below. Rollout consequence: deploying the revokes breaks direct-write clients
-- (permission denied), so reset-aware clients ship first and old clients must show
-- update-required. That is deliberate: silent stale writes are the failure being removed.
begin;
create table public.account_data_generation (
  user_id uuid primary key references auth.users(id) on delete cascade,
  generation bigint not null default 0 check (generation >= 0),
  last_reset_request uuid
);
alter table public.account_data_generation enable row level security;
revoke all on public.account_data_generation from public, anon, authenticated;
alter table public.user_recipes add column data_generation bigint not null default 0;

-- K810: NEW-column comparison cannot identify stale caller intent (an ordinary stale
-- UPDATE inherits the fresh row's generation in NEW). Remove the direct-write path
-- instead: no authenticated INSERT/UPDATE/DELETE on the table, no owner write policies.
revoke insert, update, delete on public.user_recipes from authenticated;
drop policy if exists "user_recipes insert own" on public.user_recipes;
drop policy if exists "user_recipes update own" on public.user_recipes;
drop policy if exists "user_recipes delete own" on public.user_recipes;

-- Physical delete runs only from definer/service roles: the reset RPC (security
-- definer, so current_user is the function owner) and service/admin cascades such as
-- auth.users account deletion. The boundary is current_user plus the revoked DELETE
-- grant; current_user cannot be forged with set_config and no transaction flag is used
-- as authority. Absence of JWT claims (auth.uid() is null) is NOT treated as service
-- identity: it proves nothing about who is calling.
-- DEPLOY-TIME CHECK (fail closed until done): verify the actual migration/service/
-- auth-admin role names in the target project and correct this list. A wrong list either
-- blocks account deletion or silently disables the fence.
create function public.user_recipes_delete_fence() returns trigger
language plpgsql set search_path = '' as $$
begin
  if current_user in ('postgres', 'service_role', 'supabase_admin', 'supabase_auth_admin') then
    return old;
  end if;
  raise exception 'Direct delete is disabled; use a tombstone write or account reset'
    using errcode = '42501';
end $$;
create trigger user_recipes_delete_fence before delete on public.user_recipes
for each row execute function public.user_recipes_delete_fence();
revoke all on function public.user_recipes_delete_fence() from public, anon, authenticated;

-- Defense in depth behind the revoked grants: any write that somehow reaches the table
-- still must carry the account's current generation.
create function public.enforce_account_data_generation() returns trigger
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
      using errcode = '40001';
  end if;
  return new;
end $$;
create trigger account_data_generation_fence before insert or update on public.user_recipes
for each row execute function public.enforce_account_data_generation();
revoke all on function public.enforce_account_data_generation() from public, anon, authenticated;

-- The ONLY client write path. The caller's generation is an explicit parameter checked
-- under the account state row lock; a stale caller (including an ordinary update that
-- never knew about generations) is rejected, never silently inherited.
-- Covers tombstones: pass deleted=true. Last-write-wins on updated_at stays client-side.
-- Parameters are p_-prefixed so no PL/pgSQL variable/column ambiguity is possible in
-- the INSERT column list or the ON CONFLICT target (K810: unqualified kind/id collide).
create function public.put_user_recipe(p_caller_generation bigint, p_kind text, p_id text,
                                       p_data jsonb, p_updated_at bigint, p_deleted boolean)
returns void
language plpgsql security definer set search_path = '' as $$
declare owner_id uuid := auth.uid(); current_generation bigint;
begin
  if owner_id is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if p_caller_generation is null or p_caller_generation < 0 then
    raise exception 'Invalid generation' using errcode = '22023';
  end if;
  insert into public.account_data_generation(user_id) values(owner_id) on conflict do nothing;
  select generation into current_generation from public.account_data_generation
    where user_id = owner_id for share;
  if p_caller_generation <> current_generation then
    raise exception 'Account data was cleared; discard old local data and fetch a fresh snapshot'
      using errcode = '40001';
  end if;
  insert into public.user_recipes as r (user_id, kind, id, data, updated_at, deleted, data_generation)
  values (owner_id, p_kind, p_id, p_data, p_updated_at, p_deleted, p_caller_generation)
  on conflict (user_id, kind, id) do update
    set data = excluded.data, updated_at = excluded.updated_at,
        deleted = excluded.deleted, data_generation = excluded.data_generation;
end $$;
revoke all on function public.put_user_recipe(bigint,text,text,jsonb,bigint,boolean) from public, anon;
grant execute on function public.put_user_recipe(bigint,text,text,jsonb,bigint,boolean) to authenticated;

-- An owner-scoped consistent snapshot, NOT a separate epoch GET + rows GET race.
create function public.account_data_snapshot() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare owner_id uuid := auth.uid(); current_generation bigint; rows_json jsonb;
begin
  if owner_id is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  insert into public.account_data_generation(user_id) values(owner_id) on conflict do nothing;
  select generation into current_generation from public.account_data_generation where user_id=owner_id for share;
  select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb) into rows_json
    from public.user_recipes r where r.user_id=owner_id and r.data_generation=current_generation;
  return jsonb_build_object('generation', current_generation, 'rows', rows_json);
end $$;
revoke all on function public.account_data_snapshot() from public, anon;
grant execute on function public.account_data_snapshot() to authenticated;

-- Idempotent only while this is the most recent request. expected_generation
-- prevents a stale retry deleting new data after a later, distinct reset.
create function public.clear_account_data(request_id uuid, expected_generation bigint) returns bigint
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
  if previous_request=request_id then return current_generation; end if;
  if current_generation <> expected_generation then
    raise exception 'Reset generation changed; verify status before another reset' using errcode='40001';
  end if;
  update public.account_data_generation set generation=generation+1,last_reset_request=request_id where user_id=owner_id
    returning generation into current_generation;
  -- Physical delete as the function owner (security definer): passes the delete fence.
  delete from public.user_recipes where user_id=owner_id;
  return current_generation;
end $$;
revoke all on function public.clear_account_data(uuid,bigint) from public, anon;
grant execute on function public.clear_account_data(uuid,bigint) to authenticated;
commit;
