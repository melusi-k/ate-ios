-- CANDIDATE: review and staging race/RLS tests before production application.
-- Existing authenticated ownership policies remain authoritative. Do not widen
-- grants or bypass RLS. PostgreSQL locks the conflict row before BEFORE UPDATE,
-- making this guard atomic for concurrent PostgREST upserts of shopping rows.
create or replace function public.shopping_preserve_newer_sync()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.kind = 'shopping' and new.kind = 'shopping'
     and new.updated_at <= old.updated_at then
    -- Equal timestamp: first committed server row wins, including tombstones.
    -- Returning OLD is an accepted no-op, not proof the submitted value won.
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.shopping_preserve_newer_sync() from public, anon, authenticated;
drop trigger if exists shopping_preserve_newer_sync on public.user_recipes;
create trigger shopping_preserve_newer_sync
before update on public.user_recipes
for each row execute function public.shopping_preserve_newer_sync();
