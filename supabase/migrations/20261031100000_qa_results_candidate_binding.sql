-- Phase 3: bind uploaded QA evidence to the exact app commit and Build IPA workflow run.
-- Nullable columns preserve historical rows, but unbound rows must never count for a release candidate.
alter table public.qa_results
  add column if not exists commit_sha text,
  add column if not exists run_id bigint,
  add column if not exists run_number bigint;

create index if not exists qa_results_candidate_evidence_idx
  on public.qa_results (commit_sha, run_id, source, item_id, ts desc)
  where commit_sha is not null and run_id is not null;

comment on column public.qa_results.commit_sha is
  'Full Git commit SHA embedded in the tested app or supplied by the CI workflow.';
comment on column public.qa_results.run_id is
  'GitHub Actions Build IPA workflow run ID that produced the tested build.';
comment on column public.qa_results.run_number is
  'GitHub Actions workflow run number; used for human-readable evidence ordering.';
