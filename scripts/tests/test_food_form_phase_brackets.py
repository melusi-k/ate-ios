from pathlib import Path
import re,hashlib,unittest
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
        source=(ROOT/'AteUITests/NutritionDiaryUITests.swift').read_text()
        # Composed head: also reverse #536's keyboard-completion block exactly.
        kb = (ROOT/'scripts/tests/test_merge_536_kb_fragment.txt').read_text() if (ROOT/'scripts/tests/test_merge_536_kb_fragment.txt').exists() else None
        restored = restore_food_form_brackets(self,source)
        if kb is not None:
            self.assertEqual(restored.count(kb),1)
            restored = restored.replace(kb,'',1)
        self.assertEqual(hashlib.sha256(restored.encode()).hexdigest(), '908fabd0eafe8faae9f2fcf7e9623de0b9463eda05ee4f9075d7102c51be22b6')
    def test_helper_only_phase_name_and_uptime_no_ax_reads(self):
        source=(ROOT/'AteUITests/NutritionDiaryUITests.swift').read_text()
        helper=source.split('// FOOD-FORM-DIAGNOSTIC-BEGIN',1)[1].split('// FOOD-FORM-DIAGNOSTIC-END',1)[0]
        for word in ['.frame','.value','.exists','XCUIApplication','screenshot','sleep','Timer','retry','UserDefaults']:
            self.assertNotIn(word,helper)
        for phase in ['accessory-probe-start','fallback-add-return','geometry-nav-start','geometry-nav-validation-return','geometry-nav-frame-return','source-name-input-start','source-picker-tap-start','input-keyboard-start','input-keyboard-return']:
            self.assertIn('foodFormMark("'+phase+'")',source)
