from group28_swipe_target_delta import restore as pre_swipe_target
"""Fixture audit and preservation checks, not native/UI qualification."""
from pathlib import Path
import hashlib,json,re,unittest,yaml
from all_ui_prompt_source_delta import restore
ROOT=Path(__file__).resolve().parents[2]
class AllUIPromptSourceTests(unittest.TestCase):
    def contracts(self):
        return json.loads((ROOT/'scripts/tests/all_ui_prompt_source_inverse.json').read_text())['contracts']

    def test_exact_parent_reconstruction_and_all_inverse_mutants(self):
        for path,contract in self.contracts().items():
            source=pre_swipe_target(path,(ROOT/path).read_text())
            self.assertEqual(hashlib.sha256(restore(path,source).encode()).hexdigest(),contract['parent_sha'])
            self.assertEqual(restore('source:'+path,source),restore('main:'+path,source))
            self.assertEqual(restore(path,source.encode()),restore(path,source).encode())
            for fragment in contract['fragments']:
                for mutant in [source.replace(fragment['new'],'',1),source+fragment['new'],source+'// unrelated\n']:
                    with self.assertRaises(AssertionError,msg=path):restore(path,mutant)

    def test_every_original_assertion_wait_launch_and_generate_remains(self):
        for path in self.contracts():
            if not path.endswith('.swift'):continue
            source=pre_swipe_target(path,(ROOT/path).read_text());parent=restore(path,source)
            # #642 rename slice: files outside the today-tab chain still carry the renamed text at
            # this stage (chain-covered files are restored to the pre-rename original by
            # pre_swipe_target); inverse-map the rename there so the audit compares like for like.
            if json.loads((ROOT/'scripts/tests/today_tab_ui_inverse.json').read_text()).get(path) is None:
                source=source.replace('tab("Today")','tab("Library")').replace('tabBars.buttons["Today"]','tabBars.buttons["Library"]').replace('"Recipes"','"Your Kitchen"')
            for token in ['XCTAssert','XCTFail','wait(','waitFor','launch(','launchArguments','generateButton','saveRecipe','repair.tap()','confirmDraft']:
                self.assertEqual([line for line in source.splitlines() if token in line],
                                 [line for line in parent.splitlines() if token in line],(path,token))
            # Exactly one fixture-wrapped typeText per old name-entry, no tap retries.
            if path.endswith('AteUITests.swift'):
                self.assertEqual(source.count('editor.tap(); editor.typeText(PromptRecipeFixture.salmonContinuation)'),1)
            else:
                self.assertEqual(source.count('.tap()'),parent.count('.tap()'),path)

    def test_complete_prompt_setup_inventory_and_deliberately_untouched_boundaries(self):
        expected={'AccessibilityAuditUITests.swift':1,'AteUITests.swift':6,'CookIngredientsUITests.swift':1,
                  'CookReflectionUITests.swift':1,'CookSharedStepUITests.swift':1,'CoverageUITests.swift':1,
                  'DraftQualityRepairUITests.swift':1,'ExploreUITests.swift':1,'InsightsAcceptanceUITests.swift':1,
                  'InsightsPresentationUITests.swift':1,'KeyFlowsQATests.swift':2}
        for filename,count in expected.items():
            s=(ROOT/'AteUITests'/filename).read_text()
            self.assertEqual(s.count('typeText(PromptRecipeFixture.'),count,filename)
        # Prompt sites with no generation remain unchanged: mode/deeplink selection,
        # failed social caption prefill, and first-recipe entry-point selection.
        s=(ROOT/'AteUITests/AteUITests.swift').read_text()
        self.assertIn('wait(text("Private mode is on"), 5)',s)
        self.assertIn('XCTAssertEqual(editor.value as? String, "zzz"',s)
        search=s.split('func testSearchDescribeSaveStaysOnSearchStack()',1)[1].split('\n    func ',1)[0]
        self.assertLess(search.index('XCTAssertEqual(editor.value'),search.index('PromptRecipeFixture.salmonContinuation'))
        self.assertLess(search.index('PromptRecipeFixture.salmonContinuation'),search.index('app.buttons["generateButton"].tap()'))

    def test_exact_shared_fixture_is_test_only_and_natively_checked(self):
        project=yaml.safe_load((ROOT/'project.yml').read_text())
        self.assertIn('AteUITests/PromptRecipeFixture.swift',project['targets']['AteTests']['sources'])
        self.assertEqual(project['targets']['AteUITests']['sources'],['AteUITests'])
        self.assertNotIn('AteUITests/PromptRecipeFixture.swift',str(project['targets']['Ate']['sources']))
        source=(ROOT/'AteTests/PromptRecipeFixtureTests.swift').read_text()
        for token in ['case .verified(let contract) = SourceRecipeFidelity.extraction(source)',
                      'AddPromptSourceImport.parse','backend.requests.count, 1','missingSourceMessage',
                      'PromptRecipeFixture.salmonContinuation','PromptRecipeFixture.breadSalad']:
            self.assertIn(token,source)
        fixture=(ROOT/'AteUITests/PromptRecipeFixture.swift').read_text()
        for token in ['2 salmon fillets','150 g rice','2 cloves garlic','2 slices bread','3. Toss the onion, tomatoes and bread with oil.']:
            self.assertIn(token,fixture)
