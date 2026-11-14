-- #528 REVIEW ONLY. NOT a data restore. Requires maintenance/write quiescence.
-- Forward-disable reset/sync clients FIRST. Re-enabling direct writes discards the
-- stale-client fence and is unsafe once any reset has committed. Prefer forward fix.
-- This script refuses rollback after a reset, preserving generation evidence.
begin;
lock table public.account_data_generation, public.user_recipes in access exclusive mode;
do $$ begin
  if exists (select 1 from public.account_data_generation where generation <> 0 or last_reset_request is not null) then
    raise exception 'Unsafe rollback: a reset committed; use a forward repair and preserve generation evidence';
  end if;
end $$;
drop function public.account_data_snapshot();
drop function public.put_user_recipe(bigint,text,text,jsonb,bigint,boolean);
drop function public.clear_account_data(uuid,bigint);
drop trigger account_data_generation_fence on public.user_recipes;
drop function public.enforce_account_data_generation();
drop trigger user_recipes_delete_fence on public.user_recipes;
drop function public.user_recipes_delete_fence();
alter table public.user_recipes drop column data_generation;
drop table public.account_data_generation;
create policy "user_recipes insert own" on public.user_recipes
  for insert to authenticated with check (auth.uid() = user_id);
create policy "user_recipes update own" on public.user_recipes
  for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "user_recipes delete own" on public.user_recipes
  for delete to authenticated using (auth.uid() = user_id);
grant select, insert, update, delete on public.user_recipes to authenticated;
notify pgrst, 'reload schema';
commit;
