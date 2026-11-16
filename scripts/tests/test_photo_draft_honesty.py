"""#508 source regression contracts; not native or model/pixel proof."""
from pathlib import Path
import hashlib, unittest
ROOT=Path(__file__).resolve().parents[2]
CALL='        card = PhotoDraftHonesty.apply(card)\n'
def restore_photo_honesty_call(test, source):
    test.assertEqual(source.count(CALL),1)
    return source.replace(CALL,'',1)
class PhotoDraftHonestyContracts(unittest.TestCase):
    def test_exact_backend_base_reconstructs_and_call_is_after_calibration(self):
        source=(ROOT/'Ate/Services/OnDeviceBackend.swift').read_text()
        self.assertEqual(hashlib.sha256(restore_photo_honesty_call(self,source).encode()).hexdigest(),'1da295be73194c5719e75bb50142f4ceaa698c21da2071d2dbe31c86f9fbb2b0')
        self.assertLess(source.index('card.aiConfidence = PhotoGuess.calibratedConfidence'),source.index(CALL))
        self.assertLess(source.index(CALL),source.index('var normalized = RecipeLogic.normalize(card)'))
    def test_photo_only_threshold_and_metadata_scope(self):
        s=(ROOT/'Ate/Logic/PhotoDraftHonesty.swift').read_text()
        for token in ['original.source == .photoGuess','confidence < RecipeQuality.threshold','card.cuisine = nil','card.tags = []']:
            self.assertIn(token,s)
        for token in ['card.title =','card.ingredients =','card.steps =','card.aiConfidence =','card.source =']:
            self.assertNotIn(token,s)
    def test_ambiguous_copy_does_not_assert_multiple_dishes(self):
        s=(ROOT/'Ate/Logic/RecipePrompt.swift').read_text()
        self.assertNotIn('This looks like a spread of several dishes.',s)
        self.assertIn('There may be more than one dish here.',s)
    def test_original_ocr_assertions_and_budgets_unchanged(self):
        s=(ROOT/'AteTests/OCRTerminalResultTests.swift').read_bytes()
        self.assertEqual(hashlib.sha256(s).hexdigest(),'da0d9653ef2a33928536320a3da3435160fa7318eb7cfc606937178616ed8816')
    def test_call_missing_duplicate_and_changed_mutants_fail(self):
        source=(ROOT/'Ate/Services/OnDeviceBackend.swift').read_text()
        for value in [source.replace(CALL,''),source+CALL,source.replace(CALL,CALL.replace('apply(card)','apply(RecipeCard())'))]:
            with self.assertRaises(AssertionError): restore_photo_honesty_call(self,value)
