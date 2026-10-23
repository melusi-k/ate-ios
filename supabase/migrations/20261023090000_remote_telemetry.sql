-- Remote telemetry: category-only, non-production events. Apply to the ate Supabase project.
-- No user/account/device identifiers or user-provided content are stored.
create table if not exists public.app_telemetry_events (
  id bigint generated always as identity primary key,
  event_kind text not null check (event_kind in (
    'appLaunched', 'appForegrounded', 'appBackgrounded',
    'storeOpenFailed', 'storeRecovered', 'storeInMemoryFallback', 'saveFailed',
    'recipeImportSucceeded', 'recipeImportFailed', 'recipeSaved',
    'cookingSessionCompleted', 'insightViewed', 'insightActionSelected',
    'syncSucceeded', 'syncFailed'
  )),
  channel text not null check (channel in ('TierA', 'TierB', 'TierC', 'Beta', 'QA', 'Internal', 'Development')),
  app_version text not null check (char_length(app_version) <= 32),
  build_number text not null check (char_length(build_number) <= 32),
  git_sha text not null check (char_length(git_sha) <= 16),
  platform text not null default 'iOS' check (platform = 'iOS'),
  occurred_at timestamptz not null,
  received_at timestamptz not null default now()
);

comment on table public.app_telemetry_events is
  'Privacy-safe non-production telemetry. Category and coarse build metadata only; no user, account, or device identifiers.';
revoke all on public.app_telemetry_events from anon, authenticated;
grant all on public.app_telemetry_events to service_role;
alter table public.app_telemetry_events enable row level security;

create index if not exists app_telemetry_events_received_at_idx
  on public.app_telemetry_events (received_at);
create index if not exists app_telemetry_events_channel_kind_idx
  on public.app_telemetry_events (channel, event_kind, received_at);

-- 30-day retention is enforced by the ingestion function on each accepted batch.
