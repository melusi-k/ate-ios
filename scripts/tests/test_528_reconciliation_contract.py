"""Offline structure only. PostgreSQL, PostgREST and production remain unproven."""
from pathlib import Path
import re
import unittest
ROOT=Path(__file__).resolve().parents[2]
class ReconciliationContractTests(unittest.TestCase):
    def setUp(self):
        self.sql=(ROOT/'supabase/migrations/20261113064000_reconcile_account_data_contract.sql').read_text()
    def test_only_existing_function_bodies_replaced(self):
        s=self.sql.lower()
        self.assertEqual(re.findall(r'create or replace function public\.(\w+)',s),
                         ['enforce_account_data_generation','put_user_recipe','clear_account_data'])
        self.assertNotRegex(s,r'(?m)^\s*(drop|alter|grant|revoke|truncate|create table|create trigger|create policy)\b')
        self.assertEqual(s.count('execute $ddl$'),3)
        self.assertIn("notify pgrst, 'reload schema'",s)
        self.assertTrue(s.rstrip().endswith('commit;'))
    def test_body_contract_matches_qualified_v6(self):
        v6=(ROOT/'supabase/migrations/20261113063400_account_data_generation.sql').read_text()
        for name in ['enforce_account_data_generation','put_user_recipe','clear_account_data']:
            source=re.search(r'create function public\.'+name+r'\(.*?end \$\$;',v6,re.S).group()
            self.assertIn(source.replace('create function','create or replace function',1),self.sql)
        self.assertNotRegex(self.sql,r"errcode\s*=\s*'40[0-9A-Z]{3}'")
        self.assertEqual(len(re.findall(r"errcode\s*=\s*'PT409'",self.sql)),4)
    def test_preflight_and_unchanged_security_guards(self):
        for text in ['before_functions','after_functions','before_tables','after_tables',
                     'untouched_functions','after_untouched','proacl','proowner','prosecdef','proconfig',
                     'has_column_privilege','has_function_privilege','has_table_privilege',
                     'pg_has_role','tgtype=23','tgtype=11',"current_user <> 'postgres'",'auth.uid() is not null']:
            self.assertIn(text,self.sql)
        self.assertLess(self.sql.index('Unexpected effective direct privileges'),self.sql.index('execute $ddl$'))
    def test_disposable_fixture_checks_repeat_and_rows_kept(self):
        fixture=(ROOT/'supabase/tests/528_reconciliation.sql').read_text()
        self.assertEqual(fixture.count('\\ir ../migrations/20261113064000_reconcile_account_data_contract.sql'),2)
        self.assertIn('reconcile_rows_before',fixture)
        self.assertIn('reconcile_generation_before',fixture)
        self.assertIn('reconcile_acl_before',fixture)
        self.assertIn('9223372036854775807',fixture)
