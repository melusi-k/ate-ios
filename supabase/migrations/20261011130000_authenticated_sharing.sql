-- Production MVP sharing: only authenticated users may publish; reads remain public by slug.
alter table public.shared_recipes
  add column if not exists owner_id uuid references auth.users (id) on delete cascade;

create index if not exists shared_recipes_owner_idx
  on public.shared_recipes (owner_id);

-- Existing anonymous rows remain readable and are retained until manually removed.
-- New rows are written only by the service-role Edge Function after JWT validation.
grant select on public.shared_recipes to anon;
grant select on public.shared_recipes to authenticated;
revoke insert, update, delete on public.shared_recipes from anon, authenticated;
grant all on public.shared_recipes to service_role;
