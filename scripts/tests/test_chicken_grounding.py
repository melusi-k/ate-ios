from pathlib import Path
import hashlib,unittest
ROOT=Path(__file__).resolve().parents[2]
class ChickenGroundingContracts(unittest.TestCase):
    def test_shared_instructions_unchanged_and_existing_tests_unchanged(self):
        prompt=(ROOT/'Ate/Logic/RecipePrompt.swift').read_text()
        shared=prompt.split('static let instructions =',1)[1].split('static func instructions(',1)[0]
        self.assertEqual(hashlib.sha256(shared.encode()).hexdigest(),'2ab56304ee42916f7df177b4fd13e7d7f098498445c1a30a9dc0ea01efffb31d')
        tests=(ROOT/'AteTests/PantryDraftGapTests.swift').read_text()
        self.assertEqual(hashlib.sha256(tests.encode()).hexdigest(),'108a62a1621cd6ef4c605be10b20e76a6b8f629c291eca2d42f4ae0650231602')
    def test_named_photo_grounding_is_bounded_and_unnamed_cap_unchanged(self):
        prompt=(ROOT/'Ate/Logic/RecipePrompt.swift').read_text()
        self.assertEqual(prompt.count('return p + photoGrounding'),1)
        grounding=prompt.split('static let photoGrounding = "',1)[1].split('"',1)[0]
        self.assertLessEqual(len(grounding),400)
        for phrase in ['Keep the source dish name','omit unsupported cuisine claims','not only the note','Browning alone']:
            self.assertIn(phrase,grounding)

    def test_exact_chicken_fixture_is_separate(self):
        fixture=(ROOT/'AteTests/ChickenPhotoDraftTests.swift').read_text()
        for phrase in ['Chicken au Poivre','stops after browning','herb is not a measurement','XCTAssertThrowsError','not only the note']:
            self.assertIn(phrase,fixture)
