-- In-app beta feedback. Submissions are private and service-role-only; no client can read them.
create table if not exists public.beta_feedback (
  id bigint generated always as identity primary key,
  category text not null check (category in ('bug', 'feature', 'ux', 'general')),
  message text not null check (char_length(message) between 10 and 5000),
  contact_email text check (contact_email is null or char_length(contact_email) <= 254),
  app_version text not null check (char_length(app_version) <= 32),
  build_number text not null check (char_length(build_number) <= 32),
  channel text not null check (channel in ('TierA', 'TierB', 'TierC', 'Beta', 'QA', 'Internal', 'Development')),
  git_sha text not null check (char_length(git_sha) <= 16),
  platform text not null default 'iOS' check (platform = 'iOS'),
  submitted_at timestamptz not null default now()
);
comment on table public.beta_feedback is
  'User-submitted beta feedback. Contact email is optional and only stored when explicitly provided.';
alter table public.beta_feedback enable row level security;
revoke all on public.beta_feedback from anon, authenticated;
grant all on public.beta_feedback to service_role;

create index if not exists beta_feedback_submitted_at_idx on public.beta_feedback (submitted_at desc);
create index if not exists beta_feedback_category_submitted_idx on public.beta_feedback (category, submitted_at desc);

-- Independent, atomic IP-hash quota: 5 submissions/hour and 20/day.
create table if not exists public.beta_feedback_rate_limits (
  key_hash text primary key check (key_hash ~ '^[0-9a-f]{64}$'),
  window_started_at timestamptz not null,
  hourly_count integer not null check (hourly_count >= 0),
  day_started_at timestamptz not null,
  daily_count integer not null check (daily_count >= 0),
  last_seen_at timestamptz not null default now()
);
alter table public.beta_feedback_rate_limits enable row level security;
revoke all on public.beta_feedback_rate_limits from anon, authenticated;
grant all on public.beta_feedback_rate_limits to service_role;

create or replace function public.consume_beta_feedback_rate_limit(p_key_hash text)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now timestamptz := clock_timestamp();
  v_allowed boolean := false;
begin
  if p_key_hash is null or p_key_hash !~ '^[0-9a-f]{64}$' then return false; end if;
  insert into public.beta_feedback_rate_limits
    (key_hash, window_started_at, hourly_count, day_started_at, daily_count, last_seen_at)
  values (p_key_hash, v_now, 1, date_trunc('day', v_now), 1, v_now)
  on conflict (key_hash) do update set
    window_started_at = case when public.beta_feedback_rate_limits.window_started_at <= v_now - interval '1 hour' then v_now else public.beta_feedback_rate_limits.window_started_at end,
    hourly_count = case when public.beta_feedback_rate_limits.window_started_at <= v_now - interval '1 hour' then 1 else public.beta_feedback_rate_limits.hourly_count + 1 end,
    day_started_at = case when public.beta_feedback_rate_limits.day_started_at::date < v_now::date then date_trunc('day', v_now) else public.beta_feedback_rate_limits.day_started_at end,
    daily_count = case when public.beta_feedback_rate_limits.day_started_at::date < v_now::date then 1 else public.beta_feedback_rate_limits.daily_count + 1 end,
    last_seen_at = v_now
  where
    (case when public.beta_feedback_rate_limits.window_started_at <= v_now - interval '1 hour' then 0 else public.beta_feedback_rate_limits.hourly_count end) < 5
    and
    (case when public.beta_feedback_rate_limits.day_started_at::date < v_now::date then 0 else public.beta_feedback_rate_limits.daily_count end) < 20
  returning true into v_allowed;
  return coalesce(v_allowed, false);
end;
$$;
revoke all on function public.consume_beta_feedback_rate_limit(text) from public, anon, authenticated;
grant execute on function public.consume_beta_feedback_rate_limit(text) to service_role;

create extension if not exists pg_cron with schema pg_catalog;
select cron.schedule(
  'ate-beta-feedback-rate-limit-cleanup-daily',
  '37 3 * * *',
  $$delete from public.beta_feedback_rate_limits where last_seen_at < now() - interval '2 days';$$
);
