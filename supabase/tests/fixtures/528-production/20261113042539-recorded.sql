begin;

create table public.account_data_generation (
  user_id uuid primary key references auth.users(id) on delete cascade,
  generation bigint not null default 0 check (generation >= 0),
  last_reset_request uuid
);
alter table public.account_data_generation enable row level security;
revoke all on public.account_data_generation from public, anon, authenticated;
comment on table public.account_data_generation is
  'Private per-account generation fence for reset-aware synced-data clients.';

alter table public.user_recipes
  add column data_generation bigint not null default 0;
comment on column public.user_recipes.data_generation is
  'Account generation at which this synced row was written; enforced by reset RPCs.';

revoke insert, update, delete on public.user_recipes from authenticated;
drop policy if exists "user_recipes insert own" on public.user_recipes;
drop policy if exists "user_recipes update own" on public.user_recipes;
drop policy if exists "user_recipes delete own" on public.user_recipes;

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

create function public.put_user_recipe(
  p_caller_generation bigint,
  p_kind text,
  p_id text,
  p_data jsonb,
  p_updated_at bigint,
  p_deleted boolean
) returns void
language plpgsql security definer set search_path = '' as $$
declare owner_id uuid := auth.uid(); current_generation bigint;
begin
  if owner_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
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
  insert into public.user_recipes as r
    (user_id, kind, id, data, updated_at, deleted, data_generation)
  values
    (owner_id, p_kind, p_id, p_data, p_updated_at, p_deleted, p_caller_generation)
  on conflict (user_id, kind, id) do update set
    data = excluded.data,
    updated_at = excluded.updated_at,
    deleted = excluded.deleted,
    data_generation = excluded.data_generation;
end $$;
revoke all on function public.put_user_recipe(bigint, text, text, jsonb, bigint, boolean) from public, anon;
grant execute on function public.put_user_recipe(bigint, text, text, jsonb, bigint, boolean) to authenticated;

create function public.account_data_snapshot() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare owner_id uuid := auth.uid(); current_generation bigint; rows_json jsonb;
begin
  if owner_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  insert into public.account_data_generation(user_id) values(owner_id) on conflict do nothing;
  select generation into current_generation
    from public.account_data_generation where user_id = owner_id for share;
  select coalesce(jsonb_agg(to_jsonb(r)), '[]'::jsonb) into rows_json
    from public.user_recipes r
    where r.user_id = owner_id and r.data_generation = current_generation;
  return jsonb_build_object('generation', current_generation, 'rows', rows_json);
end $$;
revoke all on function public.account_data_snapshot() from public, anon;
grant execute on function public.account_data_snapshot() to authenticated;

create function public.clear_account_data(request_id uuid, expected_generation bigint)
returns bigint
language plpgsql security definer set search_path = '' as $$
declare owner_id uuid := auth.uid(); current_generation bigint; previous_request uuid;
begin
  if owner_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if request_id is null or expected_generation is null or expected_generation < 0 then
    raise exception 'Invalid reset request' using errcode = '22023';
  end if;
  insert into public.account_data_generation(user_id) values(owner_id) on conflict do nothing;
  select generation, last_reset_request into current_generation, previous_request
    from public.account_data_generation where user_id = owner_id for update;
  if previous_request = request_id then
    return current_generation;
  end if;
  if current_generation <> expected_generation then
    raise exception 'Reset generation changed; verify status before another reset'
      using errcode = '40001';
  end if;
  update public.account_data_generation
    set generation = generation + 1, last_reset_request = request_id
    where user_id = owner_id
    returning generation into current_generation;
  delete from public.user_recipes where user_id = owner_id;
  return current_generation;
end $$;
revoke all on function public.clear_account_data(uuid, bigint) from public, anon;
grant execute on function public.clear_account_data(uuid, bigint) to authenticated;
comment on function public.account_data_snapshot() is
  'Returns the authenticated account generation and rows at one consistent snapshot.';
comment on function public.put_user_recipe(bigint, text, text, jsonb, bigint, boolean) is
  'Generation-fenced authenticated upsert/tombstone path for user_recipes.';
comment on function public.clear_account_data(uuid, bigint) is
  'Atomically advances the authenticated account generation and removes its synced rows.';

commit;;
