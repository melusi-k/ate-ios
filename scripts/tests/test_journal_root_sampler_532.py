from pathlib import Path
import hashlib
import unittest
ROOT=Path(__file__).resolve().parents[2]
class JournalRootSampler532Tests(unittest.TestCase):
    def test_original_journey_survives_diagnostic_insertions(self):
        source=(ROOT/'AteUITests/JournalOpenStateUITests.swift').read_text()
        body=source.split('    func testJournalRootAddAtNormalTextAndSidebarRoundTrip()',1)[1].split('\n    func ',1)[0]
        body=body.replace('"-qaJournalAnimationDiagnostic", ', '')
        for name in ['manual-09-normal-after-new-entry-tap','manual-09-normal-after-editor-tap']:
            body=body.replace('\n        shot("'+name+'")','')
        self.assertEqual(hashlib.sha256(body.encode()).hexdigest(), 'f3a6687acccc4c2188a82a3a51baac83e2b849b81cf53cd11dd2a8c9d003263b')
    def test_flag_scoped_bounded_sampler(self):
        source=(ROOT/'Ate/App/DogfoodSavedRecipeQAFixtures.swift').read_text()
        body=source.split('enum JournalAnimationDiagnostics {',1)[1]
        for token in ['-qaJournalAnimationDiagnostic','[15.0, 25, 45, 75, 105, 135, 165, 195, 225]','visited < 2048','emitted < 64','Task.sleep']:
            self.assertIn(token,body)
