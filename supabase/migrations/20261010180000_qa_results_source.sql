-- ate beta: CI results live next to device results. source = 'device' (in-app Beta screen) | 'ci' (backend-e2e / simulator).
-- Only the service role may write 'ci' rows; the owner can read both.
alter table public.qa_results add column if not exists source text not null default 'device';
alter table public.qa_results drop constraint if exists qa_results_source_check;
alter table public.qa_results add constraint qa_results_source_check check (source in ('device', 'ci'));
alter table public.qa_results add column if not exists run_url text;
alter table public.qa_results drop constraint if exists qa_results_pkey;
alter table public.qa_results add primary key (user_id, build, item_id, source);
drop policy if exists "qa_results insert own" on public.qa_results;
drop policy if exists "qa_results update own" on public.qa_results;
drop policy if exists "qa_results delete own" on public.qa_results;
create policy "qa_results insert own" on public.qa_results for insert to authenticated
  with check (auth.uid() = user_id and source = 'device');
create policy "qa_results update own" on public.qa_results for update to authenticated
  using (auth.uid() = user_id and source = 'device') with check (auth.uid() = user_id and source = 'device');
create policy "qa_results delete own" on public.qa_results for delete to authenticated
  using (auth.uid() = user_id and source = 'device');
grant all on public.qa_results to service_role;
create index if not exists qa_results_ci_idx on public.qa_results (user_id, source, ts desc);
