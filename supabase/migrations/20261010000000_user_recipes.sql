-- ate iOS: per-user cloud sync for recipes and shopping-list items (last-write-wins).
-- Applied to project ploncuhexmwydjxljuhe on 2026-10-10.

create table if not exists public.user_recipes (
  user_id    uuid    not null references auth.users (id) on delete cascade,
  kind       text    not null check (kind in ('recipe', 'shopping')),
  id         text    not null,
  data       jsonb,
  updated_at bigint  not null,              -- client clock, ms since epoch (LWW)
  deleted    boolean not null default false, -- tombstone
  server_updated_at timestamptz not null default now(),
  primary key (user_id, kind, id),
  constraint data_size check (data is null or pg_column_size(data) < 200000)
);

create index if not exists user_recipes_user_idx on public.user_recipes (user_id, updated_at);

alter table public.user_recipes enable row level security;

create policy "user_recipes select own" on public.user_recipes
  for select to authenticated using (auth.uid() = user_id);
create policy "user_recipes insert own" on public.user_recipes
  for insert to authenticated with check (auth.uid() = user_id);
create policy "user_recipes update own" on public.user_recipes
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "user_recipes delete own" on public.user_recipes
  for delete to authenticated using (auth.uid() = user_id);

create or replace function public.user_recipes_touch() returns trigger language plpgsql as $$
begin new.server_updated_at := now(); return new; end $$;

drop trigger if exists user_recipes_touch on public.user_recipes;
create trigger user_recipes_touch before insert or update on public.user_recipes
  for each row execute function public.user_recipes_touch();

grant select, insert, update, delete on public.user_recipes to authenticated;
