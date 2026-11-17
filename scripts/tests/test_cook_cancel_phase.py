from pathlib import Path
import json,unittest
from cook_cancel_phase_delta import restore,FIXTURE
ROOT=Path(__file__).resolve().parents[2]

class CookCancelPhaseContracts(unittest.TestCase):
    def test_exact_behavior_inverse_and_mutations(self):
        for path,spec in json.loads(FIXTURE.read_text()).items():
            source=(ROOT/path).read_text()
            self.assertEqual(source.count('.accessibilityValue(CookPlanCancelDiagnostic.summary)'),1 if 'Sheet' in path else 0)
            restore(path,source)
            for changed in [source+'// mutation\n',source.replace('CookPlanCancelDiagnostic','Changed',1)]:
                with self.assertRaises(AssertionError):restore(path,changed)
    def test_fixed_bounded_no_content_and_no_new_wait(self):
        source=(ROOT/'Ate/Services/CookPlanCancelDiagnostic.swift').read_text()
        self.assertIn('maximumEntries = 32',source)
        for forbidden in ['UserDefaults','URLSession','Task','async','recipeID','notificationID','@Observable']:
            self.assertNotIn(forbidden,source)
        for path,spec in json.loads(FIXTURE.read_text()).items():
            source=(ROOT/path).read_text()
            self.assertEqual(source.count('await '),restore(path,source).count('await '))
