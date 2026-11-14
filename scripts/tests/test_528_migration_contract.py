"""Static #528 safety contract. Not a substitute for authenticated Postgres tests."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class AccountGenerationMigrationTests(unittest.TestCase):
    def test_privilege_boundary_and_owner_rpc_contract(self):
        sql = (ROOT / 'supabase/migrations/20261113063400_account_data_generation.sql').read_text()
        for contract in ['create table public.account_data_generation',
                         'alter table public.account_data_generation enable row level security',
                         'revoke all on public.account_data_generation from public, anon, authenticated',
                         'revoke insert, update, delete on public.user_recipes from public, anon, authenticated',
                         'create function public.account_data_snapshot()',
                         'create function public.put_user_recipe(p_caller_generation bigint',
                         'create function public.clear_account_data(request_id uuid, expected_generation bigint)',
                         "owner_id uuid := auth.uid()", "security definer set search_path = ''",
                         "errcode = 'PT409'", "errcode = '22023'", "errcode = '42501'",
                         'current_generation = expected_generation + 1', 'for update', 'for share']:
            self.assertIn(contract, sql)
        self.assertEqual(sql.count('grant execute on function public.'), 3)
        self.assertNotIn('grant all', sql.lower())

    def test_permanent_conflicts_do_not_raise_serialization_retry_codes(self):
        import re
        for path in [ROOT / 'supabase/migrations/20261113063400_account_data_generation.sql',
                     ROOT / 'docs/implementation/clear-all/account_data_reset.sql']:
            sql = path.read_text()
            self.assertNotRegex(sql, r"errcode\s*=\s*'40[0-9A-Z]{3}'")
            self.assertIn("errcode = 'PT409'", sql)
        client = (ROOT / 'Ate/Store/AccountDataResetService.swift').read_text()
        self.assertIn('pgcode == "PT409"', client)
        self.assertNotIn('pgcode == "40001"', client)

    def test_rollback_refuses_after_reset_and_native_parameter_names_match(self):
        rollback = (ROOT / 'supabase/rollback/20261113063400_account_data_generation.sql').read_text()
        self.assertIn('generation <> 0 or last_reset_request is not null', rollback)
        self.assertLess(rollback.index('Unsafe rollback'), rollback.index('drop function'))
        client = (ROOT / 'Ate/Store/AccountDataResetService.swift').read_text()
        for field in ['p_caller_generation','p_kind','p_id','p_data','p_updated_at','p_deleted',
                      'request_id','expected_generation']:
            self.assertIn('"'+field+'"',client)
