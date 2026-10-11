-- Security review 2026-10-11 (docs/SECURITY_REVIEW.md). Defence in depth; no behaviour change for the app.
-- NOT yet applied to ploncuhexmwydjxljuhe: apply from the SQL editor or `supabase db push`.

-- F-03: deny by default. RLS already blocks anon, but anon should not hold table privileges at all.
revoke all on public.user_recipes from anon;
revoke all on public.qa_results  from anon;
alter default privileges in schema public revoke all on tables from anon;

-- F-04: a fixed search_path for the trigger function (Supabase linter 0011).
create or replace function public.user_recipes_touch() returns trigger
  language plpgsql set search_path = '' as $$
begin new.server_updated_at := now(); return new; end $$;

-- F-05: shared_recipes is written only by publish-recipe (service role). Make that explicit.
revoke insert, update, delete on public.shared_recipes from anon, authenticated;

-- F-06: bound qa_results free text.
alter table public.qa_results drop constraint if exists qa_results_note_len;
alter table public.qa_results add constraint qa_results_note_len check (char_length(note) <= 2000 and char_length(build) <= 100 and char_length(item_id) <= 40);
