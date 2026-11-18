"""Every Swift source must have balanced conditional compilation. A Swift compile
blocker slipped past Python-green before (unmatched #endif outside a DEBUG guard),
so the balance is pinned here. Counts directives per file; native compile still owns
final acceptance."""
from pathlib import Path
import re
import unittest
ROOT = Path(__file__).resolve().parents[2]

DIRECTIVE = re.compile(r'^\s*#(if|endif|else|elseif)\b', re.M)

class ConditionalCompilationBalanceTests(unittest.TestCase):
    def test_every_swift_file_balances_if_and_endif(self):
        checked = 0
        for folder in ['Ate', 'AteTests', 'AteUITests']:
            for path in sorted((ROOT / folder).rglob('*.swift')):
                text = path.read_text()
                directives = DIRECTIVE.findall(text)
                opens = sum(1 for d in directives if d == 'if')
                closes = sum(1 for d in directives if d == 'endif')
                self.assertEqual(opens, closes,
                                 f'{path.relative_to(ROOT)}: #if={opens} #endif={closes}')
                checked += 1
        self.assertGreater(checked, 50)

    def test_debug_fixtures_keep_debug_only_code_inside_the_guard(self):
        # Regression: a DEBUG fixture enum once sat outside the closing #endif.
        text = (ROOT / 'Ate/App/DogfoodSavedRecipeQAFixtures.swift').read_text()
        open_idx = text.index('#if DEBUG')
        close_idx = text.index('#endif')
        for symbol in ['enum DogfoodSavedRecipeQAFixtures', 'enum AccountJourneyAnimationDiagnostics',
                       'enum JournalAnimationDiagnostics', 'import UIKit', 'import OSLog']:
            idx = text.index(symbol)
            self.assertTrue(open_idx < idx < close_idx, symbol)

if __name__ == '__main__':
    unittest.main()
