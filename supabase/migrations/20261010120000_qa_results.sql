-- ate beta: on-device Tier A results uploaded from More › Beta testing.
create table if not exists public.qa_results (
  user_id  uuid not null references auth.users (id) on delete cascade,
  build    text not null,
  item_id  text not null,
  status   text not null check (status in ('untested', 'pass', 'fail', 'skip')),
  note     text not null default '',
  auto     boolean not null default false,
  ts       timestamptz not null default now(),
  primary key (user_id, build, item_id)
);
alter table public.qa_results enable row level security;
drop policy if exists "qa_results select own" on public.qa_results;
drop policy if exists "qa_results insert own" on public.qa_results;
drop policy if exists "qa_results update own" on public.qa_results;
drop policy if exists "qa_results delete own" on public.qa_results;
create policy "qa_results select own" on public.qa_results for select to authenticated using (auth.uid() = user_id);
create policy "qa_results insert own" on public.qa_results for insert to authenticated with check (auth.uid() = user_id);
create policy "qa_results update own" on public.qa_results for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "qa_results delete own" on public.qa_results for delete to authenticated using (auth.uid() = user_id);
grant select, insert, update, delete on public.qa_results to authenticated;
