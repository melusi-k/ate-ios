-- Marker only for a fresh disposable local Supabase stack. Never a shipping migration.
create table public.ate501_disposable(purpose text not null);
insert into public.ate501_disposable values ('shopping-conflict-proof-only');
alter table public.ate501_disposable enable row level security;
revoke all on public.ate501_disposable from public, anon, authenticated;
