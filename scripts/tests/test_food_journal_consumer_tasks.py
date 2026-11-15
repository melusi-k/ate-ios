"""Captured-owner task effects, not native qualification."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class OwnedConsumerTasksTests(unittest.TestCase):
    def test_registration_precedes_launch_and_drain_awaits_actual_result(self):
        source = (ROOT / 'Ate/Store/FoodJournalConsumerTasks.swift').read_text()
        self.assertLess(source.index('try lifecycle.register('), source.index('let task = Task'))
        self.assertIn('_ = await task.result', source)
        self.assertIn('onCancel: { task.cancel() }', source)
        self.assertEqual(source.count('try lifecycle.validate()'), 2)
        self.assertEqual(source.count('try Task.checkCancellation()'), 2)

    def test_async_services_capture_owner_and_validator_not_late_global(self):
        cover = (ROOT / 'Ate/Services/CoverStore.swift').read_text()
        self.assertIn('consumerTasks.run', cover)
        self.assertIn('consumerTasks.launch(operation)', cover)
        self.assertIn('boundary: boundary, validate: validate', cover)
        self.assertNotIn('try? validateWriter()', cover)
        widgets = (ROOT / 'Ate/Services/WidgetBridge.swift').read_text()
        self.assertIn('let owner = consumerTasks', widgets)
        self.assertIn('let boundary = store.capturedSharedBoundary', widgets)
        self.assertIn('publishNow(store, boundary: boundary)', widgets)
        self.assertIn('try validate()', widgets)
        live = (ROOT / 'Ate/Services/TimerCenter.swift').read_text().split('enum LiveActivities {', 1)[1]
        self.assertNotIn('try? validateWriter()', live)
        self.assertEqual(live.count('let validate = validateWriter'), 2)
        self.assertIn('consumerTasks.launch(operation)', live)

    def test_draft_is_an_immutable_owner_value_in_actual_consumers(self):
        draft = (ROOT / 'Ate/Services/DraftStore.swift').read_text()
        self.assertIn('private let writerBoundary:', draft)
        self.assertEqual(draft.count('try? writerBoundary.withEffect'), 4)
        for file in ['Ate/Store/AppStore.swift', 'Ate/Views/AddRecipeSheet.swift']:
            self.assertNotIn('DraftStore.shared', (ROOT / file).read_text())
