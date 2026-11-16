import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import yaml
ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('golden', ROOT / 'scripts/cook-golden-matrix.py')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

class CookGoldenMatrixTests(unittest.TestCase):
    def test_dispatch_only_no_standard_cancellation_and_shell_valid(self):
        raw = (ROOT / '.github/workflows/cook-golden-matrix.yml').read_text()
        workflow = yaml.safe_load(raw)
        self.assertEqual(workflow[True], {'workflow_dispatch': None})
        self.assertFalse(workflow['concurrency']['cancel-in-progress'])
        self.assertIn('github.run_id', workflow['concurrency']['group'])
        self.assertIn('-default-test-execution-time-allowance 180 -maximum-test-execution-time-allowance 240', raw)
        self.assertNotIn('retry', raw.lower())
        for step in workflow['jobs']['cook-goldens']['steps']:
            if 'run' in step:
                self.assertEqual(subprocess.run(['bash', '-n'], input=step['run'], text=True, capture_output=True).returncode, 0)

    def test_only_new_tests_are_opted_in_and_detents_are_not_text_sizes(self):
        source = (ROOT / 'AteUITests/CookGoldenCaptureUITests.swift').read_text()
        self.assertIn('environment["ATE_COOK_GOLDENS"] == "1"', source)
        self.assertIn('UICTContentSizeCategoryL', source)
        self.assertNotIn('AccessibilityXXXL', source)
        self.assertIn('recipeSheet.expandFully', source)
        self.assertIn('ask.frame.maxY, cook.frame.minY', source)
        self.assertIn('scroll.swipeUp()', source)
        for case in list(m.CASES)[:3]:
            self.assertIn('func ' + case.split('/')[1] + '()', source)

    def test_xctestrun_opt_in_only_ui_and_fail_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / 'run.xctestrun'
            p.write_bytes(plistlib.dumps({'TestConfigurations': [{'TestTargets': [{'IsUITestBundle': True}, {'IsUITestBundle': False}]}]}))
            m.configure(p)
            targets = plistlib.loads(p.read_bytes())['TestConfigurations'][0]['TestTargets']
            self.assertEqual(targets[0]['EnvironmentVariables'], {'ATE_COOK_GOLDENS': '1'})
            self.assertNotIn('EnvironmentVariables', targets[1])
            p.write_bytes(plistlib.dumps({}))
            with self.assertRaises(ValueError): m.configure(p)

    def test_missing_pass_capture_corrupt_png_and_cross_test_capture_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            raw = Path(tmp); log = raw / 'test.log'; out = raw / 'named'
            case = next(iter(m.CASES)); cls, method = case.split('/')
            name = m.CASES[case][0]
            log.write_text(f"{cls} {method}]' passed")
            png = raw / 'shot.png'; png.write_bytes(b'\x89PNG\r\n\x1a\nfixture')
            manifest = [{'testIdentifier': case + '()', 'attachments': [{'exportedFileName': 'shot.png', 'suggestedHumanReadableName': name + '_0_UUID.png'}]}]
            (raw / 'manifest.json').write_text(json.dumps(manifest))
            decoded = subprocess.CompletedProcess([], 0, 'pixelWidth: 1206\npixelHeight: 2622\n')
            with patch.object(m, 'CASES', {case: [name]}), patch.object(m.subprocess, 'run', return_value=decoded):
                m.verify(raw, log, out)
                self.assertEqual((out / (name + '.png')).read_bytes(), png.read_bytes())
                log.write_text('')
                with self.assertRaises(ValueError): m.verify(raw, log, out)
                log.write_text(f"{cls} {method}]' passed")
                png.write_bytes(b'bad')
                with self.assertRaises(ValueError): m.verify(raw, log, out)
                manifest[0]['testIdentifier'] = 'Other/test()'
                (raw / 'manifest.json').write_text(json.dumps(manifest))
                with self.assertRaises(ValueError): m.verify(raw, log, out)
