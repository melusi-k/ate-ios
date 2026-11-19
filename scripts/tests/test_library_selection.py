"""Source guards are not Swift compilation or native visual qualification."""
import hashlib
import json
from pathlib import Path
import unittest
from library_selection_delta import restore, PARENT_SHA
from add_recipe_scan_delta import restore as restore_scan
from stitch_cook_delta import restore as restore_cook
from stitch_detail_delta import restore as restore_detail

ROOT = Path(__file__).resolve().parents[2]

class LibrarySelectionSourceTests(unittest.TestCase):
    def setUp(self):
        self.view = (ROOT / 'Ate/Views/LibraryView.swift').read_text()
        self.logic = (ROOT / 'Ate/Logic/LibrarySelection.swift').read_text()
    def test_exact_inverse_preserves_parent_and_ignores_other_keys(self):
        result = restore('main:Ate/Views/LibraryView.swift', self.view)
        self.assertEqual(hashlib.sha256(result.encode()).hexdigest(), PARENT_SHA)
        self.assertEqual(restore('other', self.view), self.view)
        self.assertIsInstance(restore('main:Ate/Views/LibraryView.swift', self.view.encode()), bytes)
    def test_modified_or_duplicate_selection_fragment_cannot_pass_inverse(self):
        fragments = json.loads((ROOT / 'scripts/tests/library_selection_inverse.json').read_text())['Ate/Views/LibraryView.swift']['fragments']
        fragment = fragments[0]['selected_fragment']
        for invalid in [self.view.replace(fragment, '', 1), self.view + fragment]:
            with self.assertRaises(AssertionError):
                restore('main:Ate/Views/LibraryView.swift', invalid)
    def test_selection_is_view_local_and_has_no_write_or_bulk_claims(self):
        for token in ['Set<String>', 'guard isSelecting', 'formIntersection(savedIDs)', '.sorted { $0.id < $1.id }', 'addingReportingOverflow']:
            self.assertIn(token, self.logic)
        for token in ['UserDefaults', 'AppStore', 'deleteWithUndo', 'Meal Plan', 'Task {', 'NotificationCenter']:
            self.assertNotIn(token, self.logic)
        for token in ['ShareLink(item:', 'RecipeLogic.text(for:', 'No active-prep estimate.', 'total saved recipe servings', '.onChange(of: store.session?.userID)']:
            self.assertIn(token, self.view)
        self.assertNotIn('summary.timeMinutes', self.view)
    def test_flag_default_on_qa_off_is_uitest_guarded(self):
        self.assertIn('if isUITesting && arguments.contains("-qaStitchLibraryMultiSelectOff")', self.logic)
        self.assertIn('return configured ?? true', self.logic)
        self.assertIn('StitchFeatureFlags.stitchLibraryMultiSelectEnabled', self.view)
        self.assertIn('selection.isSelecting || !store.recipes.isEmpty', self.view)
    def test_native_source_has_on_off_empty_landscape_and_required_unit_names(self):
        ui = (ROOT / 'AteUITests/LibrarySelectionUITests.swift').read_text()
        for token in ['testOnSelectToggleDeselectCancelAndOriginalDetailRoute', 'testOffHasOriginalCardsWithoutSelectionControls', 'testLandscapeSelectionAndAccessibilityLabels', 'testEmptyLibraryHasNoSelectionOrShare', 'ActivityListView', '.keepAlways']:
            self.assertIn(token, ui)
        units = (ROOT / 'AteTests/LibrarySelectionTests.swift').read_text()
        required = (ROOT / 'scripts/full-unit-required.txt').read_text()
        import re
        for method in re.findall(r'    func (test\w+)\(', units):
            self.assertIn('LibrarySelectionTests/' + method, required)

    def test_grid_hides_all_discovery_and_explicit_native_selection_is_wired(self):
        grid = self.view.split('private func grid(', 1)[1].split('@ViewBuilder private func gridCell', 1)[0]
        self.assertIn('if !selection.isSelecting {\n                    TodayJournalHubCard()\n                    TodayHealthCard()\n                    recipeRediscovery\n                }', grid)
        ui = (ROOT / 'AteUITests/LibrarySelectionUITests.swift').read_text()
        self.assertIn('app.scrollViews["libraryGrid"].waitForExistence', ui)
        self.assertIn('-qaLibrarySelectionRediscovery', ui)
        workflow = (ROOT / '.github/workflows/compile-check.yml').read_text()
        self.assertIn('-only-testing:AteUITests/LibrarySelectionUITests', workflow)
        import re
        for method in re.findall(r'    func (test\w+)\(', ui):
            self.assertIn(method, workflow)
        self.assertEqual(hashlib.sha256(restore('main:.github/workflows/compile-check.yml', restore_scan('main:.github/workflows/compile-check.yml', restore_detail('main:.github/workflows/compile-check.yml', restore_cook('main:.github/workflows/compile-check.yml', workflow)))).encode()).hexdigest(), json.loads((ROOT / 'scripts/tests/library_selection_inverse.json').read_text())['.github/workflows/compile-check.yml']['parent_sha'])
