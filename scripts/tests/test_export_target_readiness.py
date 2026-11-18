"""Exact source preservation and targeting guards; native execution remains required."""
from pathlib import Path
import hashlib
import unittest
from unittest.mock import patch
from export_target_readiness_delta import restore, NEW
ROOT = Path(__file__).resolve().parents[2]
KEY = 'source:AteUITests/CoverageUITests.swift'

class ExportTargetReadinessTests(unittest.TestCase):
    def test_whole_file_reconstructs_exact_failed_candidate(self):
        source = (ROOT / 'AteUITests/CoverageUITests.swift').read_text()
        restored = restore(KEY, source)
        # Composed head: also reverse #536's three test32c/32d deltas exactly.
        import json as _json
        for _f in _json.loads((ROOT/'scripts/tests/approved_merge_536_inverses.json').read_text())['contracts']['main:AteUITests/CoverageUITests.swift']['inverse_fragments']:
            self.assertEqual(restored.count(_f['merged_fragment']), 1)
            restored = restored.replace(_f['merged_fragment'], _f['parent_fragment'], 1)
        self.assertEqual(hashlib.sha256(restored.encode()).hexdigest(), 'aa498d8e7b5909b94e480367a1f9f8cc3287b04a47178954d43ded5f0a1c159a')
        for mutation in [source.replace(NEW, '', 1), source + NEW, source.replace('first.clear.contains(first.row)', 'true', 1)]:
            with self.assertRaises(AssertionError):
                restore(KEY, mutation)

    def test_target_checks_clearance_identity_stability_and_unchanged_swipe_limits(self):
        for token in ['export.elementType == .button', 'export.identifier == "settings.export"',
                      'first.clear.contains(first.row)', 'second.clear.contains(second.row)',
                      'first.row == second.row', 'first.clear == second.clear',
                      'frame.minY - 8', 'frame.minY - 16', 'nav.maxY', 'tab.minY',
                      'exportSwipes < 25', 'exportSwipes < 50', 'export.waitForExistence(timeout: 2)',
                      'shot("settings-export-before-original-tap")',
                      'guard exportClear, exportFullyClear() else', 'SETTINGS-EXPORT-PRETAP']:
            self.assertIn(token, NEW)
        source = (ROOT / 'AteUITests/CoverageUITests.swift').read_text()
        test = source.split('func test32_MoreCollectionsToolsAbout()', 1)[1].split('// MARK: photo dish step', 1)[0]
        self.assertEqual(test.count('export.tap()'), 1)
        self.assertIn('let readinessBudget: TimeInterval = 2', test)
        self.assertIn('XCTFail("Export ActivityListView must present")', test)
        self.assertIn('exportActivity.exists && !exportActivity.frame.isEmpty', test)
        self.assertNotIn('sleep(', NEW)
        self.assertNotIn('app.swipe', NEW)

    def test_original_frozen_guard_still_rejects_export_assertion_mutant(self):
        from test_about_targeting import AboutTargetingTests
        target = ROOT / 'AteUITests/CoverageUITests.swift'
        read = Path.read_text
        source = read(target)
        changed = source.replace('XCTFail("Export ActivityListView must present")', 'print("Export missing")', 1)
        self.assertNotEqual(changed, source)
        with patch.object(Path, 'read_text', lambda p,*a,**kw: changed if p == target else read(p,*a,**kw)):
            case = AboutTargetingTests('test_every_original_line_preserved_except_targeting')
            with self.assertRaises(AssertionError):
                case.test_every_original_line_preserved_except_targeting()
