from pathlib import Path
import re,subprocess,unittest
ROOT=Path(__file__).resolve().parents[2]

def restore_food_form_brackets(test, source):
    helper='''    // FOOD-FORM-DIAGNOSTIC-BEGIN
    private func foodFormMark(_ phase: String) {
        guard name.contains("testFoodDiaryOpensAndExplicitlyLogsFoodWithUnavailableValues") else { return }
        print("FOOD-FORM phase=\\(phase) uptime=\\(ProcessInfo.processInfo.systemUptime)")
    }
    // FOOD-FORM-DIAGNOSTIC-END

'''
    test.assertEqual(source.count(helper),1)
    source=source.replace(helper,'',1)
    lines=source.splitlines(keepends=True)
    calls=[line for line in lines if 'foodFormMark(' in line]
    for line in calls:
        test.assertRegex(line,r'^\s*(?:defer \{ )?foodFormMark\("[a-z-]+"\)(?: \})?\n$')
    return ''.join(line for line in lines if 'foodFormMark(' not in line)

class FoodFormPhaseTests(unittest.TestCase):
    def test_original_entire_test_source_unchanged_except_brackets(self):
        baseline=subprocess.check_output(['git','show','5099f06e0a316d80add93c6d22d9c57454dd81db:AteUITests/NutritionDiaryUITests.swift'],cwd=ROOT,text=True)
        source=(ROOT/'AteUITests/NutritionDiaryUITests.swift').read_text()
        self.assertEqual(restore_food_form_brackets(self,source),baseline)
    def test_helper_only_phase_name_and_uptime_no_ax_reads(self):
        source=(ROOT/'AteUITests/NutritionDiaryUITests.swift').read_text()
        helper=source.split('// FOOD-FORM-DIAGNOSTIC-BEGIN',1)[1].split('// FOOD-FORM-DIAGNOSTIC-END',1)[0]
        for word in ['.frame','.value','.exists','XCUIApplication','screenshot','sleep','Timer','retry','UserDefaults']:
            self.assertNotIn(word,helper)
        for phase in ['accessory-probe-start','fallback-add-return','geometry-nav-start','geometry-nav-validation-return','geometry-nav-frame-return','source-name-input-start','source-picker-tap-start','input-keyboard-start','input-keyboard-return']:
            self.assertIn('foodFormMark("'+phase+'")',source)
