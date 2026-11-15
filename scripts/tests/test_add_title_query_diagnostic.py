from approved_merge_537 import normalize
from pathlib import Path
import hashlib
import unittest
ROOT=Path(__file__).resolve().parents[2]
class AddTitleQueryDiagnosticTests(unittest.TestCase):
    def test_all_original_tests_and_helpers_preserved(self):
        source=normalize('main:AteUITests/AteUITests.swift', (ROOT/'AteUITests/AteUITests.swift').read_text())
        source=source.replace('    private var captureAddTitleQuery = false\n','')
        source=source.replace('        captureAddTitleQuery = true\n        defer { captureAddTitleQuery = false }\n        launch(["-qaAddTitleQueryDiagnostic"])','        launch()')
        source=source.replace('        if captureAddTitleQuery { shot("cook-completion-before-add-title-query") }\n','')
        self.assertEqual(hashlib.sha256(source.encode()).hexdigest(),'5484221d8e4c89265c1d6601413fa74abe7c3c67e8093ec85e09a220fa243ad9')
    def test_debug_flagged_bounded_task(self):
        source=normalize('main:Ate/Views/AddRecipeSheet.swift', (ROOT/'Ate/Views/AddRecipeSheet.swift').read_text()).split('private enum AddTitleQueryDiagnostic {',1)[1]
        for token in ['AppConfig.isUITesting','-qaAddTitleQueryDiagnostic','@MainActor','[0.0, 15, 30, 60, 90, 120, 150]','Task.sleep','Task.isCancelled']:
            self.assertIn(token,source)
        for token in ['UserDefaults','accessibility','draft','while ']:self.assertNotIn(token,source)
