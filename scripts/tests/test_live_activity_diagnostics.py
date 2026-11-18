from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
SRC = (ROOT / 'Ate/Services/TimerCenter.swift').read_text()

class LiveActivityDiagnosticsContracts(unittest.TestCase):
    def test_started_line_carries_step_duration_and_end_time(self):
        # A reader must be able to tell whether an old activity should still be alive.
        self.assertIn('duration \\(t.total)s ends \\(', SRC)
        self.assertIn('step \\(t.stepIndex + 1)/\\(t.stepCount)', SRC)
        self.assertIn('formatted(date: .omitted, time: .standard)', SRC)

    def test_end_events_are_logged_both_paths(self):
        # Ends were previously silent, which made the historical log impossible to
        # reconcile with the live "Active activities" count.
        self.assertIn('record("end requested for \\(id), no matching active activity (already ended or dismissed)")', SRC)
        self.assertIn('record("ended \\(a.id.prefix(8)) timer \\(id) reason=\\(reason), remaining active \\(Activity<CookTimerAttributes>.activities.count)")', SRC)
        self.assertIn('let reason = finished == nil ? "stopped" : "finished"', SRC)

    def test_end_logging_stays_behind_the_writer_fence(self):
        # The record is a write: it must stay fenced like every post-await write.
        end_fn = SRC.split('static func end(', 1)[1]
        fence = end_fn.index('guard (try? validateWriter()) != nil else { return }')
        record = end_fn.index('record("ended')
        self.assertLess(fence, record)

    def test_attempt_and_error_lines_unchanged(self):
        self.assertIn('record("attempt:', SRC)
        self.assertIn('record("error:', SRC)
        self.assertIn('record("updated \\(a.id.prefix(8)) state=', SRC)

if __name__ == '__main__':
    unittest.main()
