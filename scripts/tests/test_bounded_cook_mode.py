from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[2]
class BoundedCookMode(unittest.TestCase):
    def test_split_keeps_timer_and_completion_contracts(self):
        s=(ROOT/'AteUITests/AteUITests.swift').read_text()
        first=s.split('func test06_CookMode()',1)[1].split('func test06b_',1)[0]
        last=s.split('func test06b_CookModeFinalStepAndFinish()',1)[1].split('func testCookModeExit',1)[0]
        for phrase in ['XCTAssertFalse(app.buttons["Back"].isEnabled)', 'timer should count down', 'Reset timer', 'cook-step1', 'cook-timer-running']:
            self.assertIn(phrase,first)
        for phrase in ['The final step should offer explicit completion', 'XCTAssertEqual(finish.label, "Finish cooking")', 'cook-last-step', 'finish.tap()', 'wait(app.buttons["Cook mode"], 5)']:
            self.assertIn(phrase,last)
        for test in [first,last]:self.assertIn('openSavedCookRecipe()',test)
        workflow=(ROOT/'.github/workflows/compile-check.yml').read_text()
        for name in ['test06_CookMode','test06b_CookModeFinalStepAndFinish']:
            self.assertIn('-only-testing:AteUITests/AteUITests/'+name,workflow)
        self.assertIn('for test in test06_CookMode test06b_CookModeFinalStepAndFinish',workflow)

    def test_fixture_is_data_only_and_footer_is_scroll_owned(self):
        fixture=(ROOT/'Ate/App/DogfoodSavedRecipeQAFixtures.swift').read_text()
        self.assertTrue(fixture.startswith('#if DEBUG'))
        self.assertIn('guard AppConfig.isUITesting',fixture)
        self.assertIn('contains("-qaSavedRecipeForCookMode")',fixture)
        cook=fixture.split('if cook {',1)[1].split('let first =',1)[0]
        for forbidden in ['cookSession','cookTarget','store.path','timers','finish','stepIndex']:
            self.assertNotIn(forbidden,cook)
        detail=(ROOT/'Ate/Views/RecipeDetailView.swift').read_text()
        scroll=detail.split('.accessibilityIdentifier("recipe.detail.scroll")',1)[1].split('RecipeNotFoundView',1)[0]
        self.assertIn('.safeAreaInset(edge: .bottom',scroll)
        self.assertIn('.padding(.bottom, footerChromeReserve)',scroll)
        self.assertIn('.background(Theme.background.ignoresSafeArea(edges: .bottom))',scroll)
