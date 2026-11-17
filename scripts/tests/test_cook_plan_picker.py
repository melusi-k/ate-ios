from pathlib import Path
import hashlib, unittest
ROOT = Path(__file__).resolve().parents[2]

class CookPlanPickerContracts(unittest.TestCase):
    def test_existing_plan_persistence_and_notification_editor_is_unchanged(self):
        pins = {'Ate/Views/CookPlanSheet.swift': '75fb68558b403342dcbd9d790c48e16410c2b1122f52fa93c020b8de6c182d9e', 'Ate/Logic/CookPlan.swift': '97c14a2662a86019778f400b048dbd19aca04e201537a18605cdd8d59123bbe2', 'Ate/Services/CookPlanNotifications.swift': '4948a4701ea465790e97d29a357d76e08d9031c25ca865aa051809aa1e1c2c55', 'AteUITests/CookPlanUITests.swift': '73ce8569fc98387a1118d579aeebe404299554617d421060487a1a77a70228ec'}
        for path, expected in pins.items():
            self.assertEqual(hashlib.sha256((ROOT/path).read_bytes()).hexdigest(),expected,path)
    def test_picker_handoff_is_dismissal_driven_and_not_a_second_plan_writer(self):
        source=(ROOT/'Ate/Views/CookPlanRecipePicker.swift').read_text()
        for token in ['onDismiss:', 'pendingID = nil', 'plan = PlanTarget(id: id)',
                      'CookPlanSheet(recipeID: target.id)', 'cookPlan.pickerCancel', 'No saved recipes']:
            self.assertIn(token,source)
        for forbidden in ['Task.sleep','asyncAfter','cookPlanStore.save','cookPlanNotifications','UserDefaults','store.completeCook','recordCooking']:
            self.assertNotIn(forbidden,source)
        self.assertIn('.sheet(item: $plan)',source)
        self.assertIn('CookPlanRecipeChoices.matches(store.recipes, query: query)',source)
    def test_both_library_and_calendar_have_named_entry(self):
        for path, token in [('Ate/Views/LibraryView.swift','library.planCook'),('Ate/Views/CookingTrackerView.swift','tracker.planCook')]:
            source=(ROOT/path).read_text()
            self.assertIn(token,source)
            self.assertIn('.cookPlanRecipePicker(isPresented: $showPlanPicker)',source)
        test=(ROOT/'AteUITests/CookPlanPickerUITests.swift').read_text()
        for token in ['testLibraryPickerCancelThenSaveReopenAndCancelPlan','testCalendarPickerUsesSamePlanEditor','cookPlan.savedDate','cookPlan.cancelPlan']:
            self.assertIn(token,test)
