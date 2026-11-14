"""Lifecycle markers are observations, never a replacement for genuine Files UI."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class MealBackupPickerDiagnosticsTests(unittest.TestCase):
    def test_real_picker_and_cancellation_stay_unchanged(self):
        source = (ROOT / 'Ate/Views/CanonicalNutritionDiaryView.swift').read_text()
        self.assertIn('UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: false)', source)
        self.assertIn('picker.allowsMultipleSelection = false', source)
        self.assertIn('picker.delegate = context.coordinator', source)
        self.assertIn('guard !finished else { return }', source)
        self.assertIn('finish(nil, outcome: "cancelled")', source)
        self.assertNotIn(': UIDocumentPickerViewController {', source)
        self.assertIn('guard let url else { return }', source)

    def test_marker_hooks_observe_without_driving_presentation(self):
        source = (ROOT / 'Ate/Views/CanonicalNutritionDiaryView.swift').read_text()
        self.assertIn('context.coordinator.trace("created")', source)
        self.assertIn('.onAppear { MealBackupDocumentPicker.Coordinator.traceSheetPresented() }', source)
        self.assertIn('MealBackupDocumentPicker.Coordinator.traceSheetDismissed()', source)
        self.assertIn('trace("cancelled")', source)
        for marker in ['phase=presented scope=sheet', 'phase=dismissed scope=sheet']:
            self.assertIn(marker, source)
        diagnostics = source.split('static func traceSheetPresented()', 1)[1]
        self.assertIn('logger.notice(', diagnostics)
        for forbidden in ['choosingMealBackup =', 'onFinish(', 'Task.sleep', 'DispatchQueue', 'fileSize', 'url.path']:
            self.assertNotIn(forbidden, diagnostics)
