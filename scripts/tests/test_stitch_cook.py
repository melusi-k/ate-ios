"""Cook presentation boundaries only; native execution remains required."""
from pathlib import Path
import hashlib
import json
import re
import unittest
from stitch_cook_delta import restore
ROOT = Path(__file__).resolve().parents[2]

class StitchCookSourceTests(unittest.TestCase):
    def test_exact_base_inverse_rejects_missing_changed_duplicate_fragments(self):
        contracts = json.loads((ROOT / 'scripts/tests/stitch_cook_inverse.json').read_text())
        for path, contract in contracts.items():
            raw = (ROOT / path).read_text()
            self.assertEqual(hashlib.sha256(restore('main:' + path, raw).encode()).hexdigest(), contract['parent_sha'])
            for fragment in contract['fragments']:
                for invalid in [raw.replace(fragment['slice'], '', 1), raw + fragment['slice']]:
                    with self.assertRaises(AssertionError): restore('main:' + path, invalid)
    def test_scroll_is_inside_footer_and_keeps_full_size_text_without_timer_effects(self):
        source = (ROOT / 'Ate/Views/CookModeView.swift').read_text()
        self.assertLess(source.index('.modifier(CookStepScroll(enabled: stitchCook))'), source.index('.safeAreaInset(edge: .bottom'))
        self.assertIn('.minimumScaleFactor(stitchCook ? 1 : 0.5)', source)
        self.assertIn('.fixedSize(horizontal: false, vertical: stitchCook)', source)
        self.assertIn('.padding(.bottom, footerChromeReserve)', source)
        modifier = source.split('private struct CookStepScroll:', 1)[1].split('/// Compact session', 1)[0]
        self.assertIn('if enabled {', modifier)
        self.assertIn('else { content }', modifier)
        for forbidden in ['store.', 'timers.', 'voice.', 'finish(', 'Task', 'onAppear']:
            self.assertNotIn(forbidden, modifier)
    def test_flag_is_presentation_only_default_on_with_guarded_off(self):
        logic = (ROOT / 'Ate/Logic/CookModeFeature.swift').read_text()
        self.assertIn('return configured ?? true', logic)
        self.assertIn('if isUITesting && arguments.contains("-qaStitchCookModeOff")', logic)
        for forbidden in ['Timer(', 'VoiceController', 'AppStore', 'UserDefaults', 'finish(', 'rescue']:
            self.assertNotIn(forbidden, logic)
    def test_native_methods_have_existing_lane_route_and_required_unit_names(self):
        ui = (ROOT / 'AteUITests/StitchCookModeUITests.swift').read_text()
        workflow = (ROOT / '.github/workflows/compile-check.yml').read_text()
        self.assertIn('-only-testing:AteUITests/StitchCookModeUITests', workflow)
        for method in re.findall(r'    func (test\w+)\(', ui): self.assertIn(method, workflow)
        for token in ['Start timer', 'Pause timer', 'Exit/reentry must not pause', 'cookFinish', 'text.frame.maxY, next.frame.minY']:
            self.assertIn(token, ui)
        required = (ROOT / 'scripts/full-unit-required.txt').read_text()
        for method in re.findall(r'    func (test\w+)\(', (ROOT / 'AteTests/CookModeFeatureTests.swift').read_text()):
            self.assertIn('CookModeFeatureTests/' + method, required)
