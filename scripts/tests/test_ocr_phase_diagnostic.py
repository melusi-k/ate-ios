"""Phase-only Vision timing does not change deadline, request quality or acceptance."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]

class OCRPhaseDiagnosticTests(unittest.TestCase):
    def test_original_deadline_and_vision_request_retained(self):
        s = (ROOT / 'Ate/Services/OnDeviceBackend.swift').read_text()
        self.assertIn('static let ocrDeadlineSeconds: TimeInterval = 10', s)
        self.assertIn('req.recognitionLevel = .accurate', s)
        self.assertIn('req.usesLanguageCorrection = true', s)
        self.assertIn('try VNImageRequestHandler(cgImage: cg).perform([req])', s)
        self.assertIn('diagnostic?.mark(.deadlineFired)', s)
        self.assertIn('diagnostic?.mark(.callerFailed)\n            throw error', s)
        self.assertIn('diagnostic?.mark(.callerReturned)\n            return text', s)
        self.assertIn('private static let log = Logger(subsystem: "com.melusik.ate", category: "photo-import-phases")', s)

    def test_only_two_explicit_synthetic_tests_enable_new_timing(self):
        s = (ROOT / 'AteTests/OCRTerminalResultTests.swift').read_text()
        self.assertEqual(s.count('diagnostic: .syntheticVisionFixture()'), 2)
        self.assertEqual(s.count('OnDeviceBackend.ocrDeadlineSeconds * 0.8'), 2)
        for expected in ['Pancakes', '2 eggs', 'Cook for 2 minutes', '200']:
            self.assertIn(expected, s)
