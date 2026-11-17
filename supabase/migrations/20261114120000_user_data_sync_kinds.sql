-- ate iOS issue #34: sync ALL user data (Food Journal, insight lifecycle states, nutrition
-- goals) to Supabase, alongside the existing recipe/shopping kinds.
--
-- STATUS: DRAFT FILE ONLY - NOT APPLIED. Production applies only on the owner's explicit
-- yes, and this file must first be reconciled against the live schema of project
-- ploncuhexmwydjxljuhe (the #528/v6 reset-contract deploy may have renamed or replaced the
-- objects referenced below). Client builds tolerate the unmigrated backend: a 23514
-- check-violation or a missing RPC contract degrades the new families to local-only.
--
-- What this changes and why:
--   user_recipes.kind has CHECK (kind in ('recipe','shopping')) since 2026-10-10. The new
--   families reuse the same table (one RLS surface, one LWW clock, one tombstone model,
--   clear_account_data already deletes every kind for the owner), so the allow-list widens:
--     'journal'  - one row per JournalEntry (meal or reflection), full-fidelity payload;
--                  media bytes are NOT synced (file names only, phase 1)
--     'insight'  - one row per insight id: InsightLifecycleRecord verbatim
--     'goals'    - one row ('current'): DailyNutritionGoals verbatim
--   RLS policies, the 200 KB row cap, the server_updated_at trigger and grants are
--   unchanged and already cover the new kinds.
--
-- Deploy-time checks (fail closed until done):
--   1. Confirm the actual constraint name:
--        select conname from pg_constraint
--        where conrelid = 'public.user_recipes'::regclass and contype = 'c';
--      Adjust the DROP below if the name differs (default: user_recipes_kind_check).
--   2. Confirm no rows exist with other kind values (should be impossible under the old
--      CHECK, but verify before widening): select distinct kind from public.user_recipes;
--   3. If the reset contract (account_data_generation / put_user_recipe / delete fence) is
--      deployed, confirm put_user_recipe does not re-validate kind against the old list.

begin;

alter table public.user_recipes
  drop constraint if exists user_recipes_kind_check;

alter table public.user_recipes
  add constraint user_recipes_kind_check
  check (kind in ('recipe', 'shopping', 'journal', 'insight', 'goals'));

commit;
