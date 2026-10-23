-- Server-side abuse controls and scheduled retention for public telemetry ingestion.
-- The endpoint stores only a one-way hash of the platform-provided client address in this table;
-- raw addresses are never stored. Counts are bounded to 300 requests/hour and 2,000 requests/day.
create table if not exists public.app_telemetry_rate_limits (
  key_hash text primary key check (key_hash ~ '^[0-9a-f]{64}$'),
  hour_started_at timestamptz not null,
  hourly_count integer not null check (hourly_count >= 0),
  day_started_at timestamptz not null,
  daily_count integer not null check (daily_count >= 0),
  last_seen_at timestamptz not null default now()
);

alter table public.app_telemetry_rate_limits enable row level security;
revoke all on public.app_telemetry_rate_limits from anon, authenticated;
grant all on public.app_telemetry_rate_limits to service_role;

create or replace function public.consume_telemetry_rate_limit(p_key_hash text)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  allowed boolean := false;
  current_time timestamptz := clock_timestamp();
begin
  if p_key_hash is null or p_key_hash !~ '^[0-9a-f]{64}$' then
    return false;
  end if;

  insert into public.app_telemetry_rate_limits (
    key_hash, hour_started_at, hourly_count, day_started_at, daily_count, last_seen_at
  ) values (
    p_key_hash, date_trunc('hour', current_time), 1,
    date_trunc('day', current_time), 1, current_time
  )
  on conflict (key_hash) do update set
    hour_started_at = case
      when public.app_telemetry_rate_limits.hour_started_at <= current_time - interval '1 hour'
      then date_trunc('hour', current_time)
      else public.app_telemetry_rate_limits.hour_started_at
    end,
    hourly_count = case
      when public.app_telemetry_rate_limits.hour_started_at <= current_time - interval '1 hour'
      then 1 else public.app_telemetry_rate_limits.hourly_count + 1
    end,
    day_started_at = case
      when public.app_telemetry_rate_limits.day_started_at::date < current_time::date
      then date_trunc('day', current_time)
      else public.app_telemetry_rate_limits.day_started_at
    end,
    daily_count = case
      when public.app_telemetry_rate_limits.day_started_at::date < current_time::date
      then 1 else public.app_telemetry_rate_limits.daily_count + 1
    end,
    last_seen_at = current_time
  where
    (case
      when public.app_telemetry_rate_limits.hour_started_at <= current_time - interval '1 hour'
      then 0 else public.app_telemetry_rate_limits.hourly_count
    end) < 300
    and
    (case
      when public.app_telemetry_rate_limits.day_started_at::date < current_time::date
      then 0 else public.app_telemetry_rate_limits.daily_count
    end) < 2000
  returning true into allowed;

  return coalesce(allowed, false);
end;
$$;

revoke all on function public.consume_telemetry_rate_limit(text) from public, anon, authenticated;
grant execute on function public.consume_telemetry_rate_limit(text) to service_role;

-- Supabase's pg_cron scheduler enforces the published 30-day retention bound even if ingestion stops.
create extension if not exists pg_cron with schema pg_catalog;
select cron.schedule(
  'ate-telemetry-retention-daily',
  '17 3 * * *',
  $$delete from public.app_telemetry_events where received_at < now() - interval '30 days';$$
);

-- Discard stale hashed rate-limit keys; this table contains no raw client addresses.
select cron.schedule(
  'ate-telemetry-rate-limit-cleanup-daily',
  '27 3 * * *',
  $$delete from public.app_telemetry_rate_limits where last_seen_at < now() - interval '2 days';$$
);
