from pathlib import Path
import unittest,hashlib,json
from ui_fixture_title_delta import restore
ROOT=Path(__file__).resolve().parents[2]
class UIFixtureTitle(unittest.TestCase):
    def test_exact_inverse_rejects_missing_duplicate_and_unrelated_mutants(self):
        for path,c in json.loads((ROOT/'scripts/tests/ui_fixture_title_inverse.json').read_text()).items():
            s=(ROOT/path).read_text()
            self.assertEqual(hashlib.sha256(restore(path,s).encode()).hexdigest(),c['parent_sha'])
            for f in c['fragments']:
                for mutant in [s.replace(f['new'],'',1),s+f['new'],s+'// unrelated\n']:
                    with self.assertRaises(AssertionError):restore(path,mutant)
    def test_ui_title_contract_is_debug_only_and_actual_backend_is_required(self):
        source=(ROOT/'Ate/Services/BackendService.swift').read_text()
        self.assertIn('#if DEBUG\n    // UI fixtures carry',source)
        self.assertIn('var usesSourceFixtureTitles = AppConfig.isUITesting',source)
        self.assertIn('if usesSourceFixtureTitles {',source)
        self.assertIn('.first { !$0.isEmpty } ?? ""',source)
        tests=(ROOT/'AteTests/PromptRecipeFixtureTests.swift').read_text()
        for token in ['let backend = MockBackend()', 'backend.usesSourceFixtureTitles = true',
                      'XCTAssertEqual(card.title, title)','XCTAssertEqual(card.source, .mock)',
                      'XCTAssertEqual(card.steps.map(\\.timeSeconds), [nil, nil, 600, 60])']:
            self.assertIn(token,tests)
        self.assertIn('PromptRecipeFixtureTests/testActualUIMockBackendKeepsFixtureFirstLineTitlesCardAndTimers',
                      (ROOT/'scripts/full-unit-required.txt').read_text().splitlines())
