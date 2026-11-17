"""Source contracts only. UIKit compilation and failure delivery need the single native cycle."""
from pathlib import Path
import json,hashlib,re,subprocess,unittest
from window_hit_failure_delta import restore,FIXTURE
ROOT=Path(__file__).resolve().parents[2]
class WindowHitFailureContracts(unittest.TestCase):
    def test_exact_inverse_and_tamper_rejection(self):
        for path,item in json.loads(FIXTURE.read_bytes()).items():
            current=(ROOT/path).read_text()
            self.assertEqual(current,item['new'])
            self.assertEqual(restore('source:'+path,current),item['old'])
            for mutant in [current+'\n',current[1:]]:
                with self.assertRaises(AssertionError):restore('source:'+path,mutant)
    def test_release_app_is_identical(self):
        def strip_debug(source):
            lines=[];stack=[];active=True
            for line in source.splitlines(keepends=True):
                directive=line.strip()
                if directive=='#if DEBUG':stack.append((active,True));active=False;continue
                if directive.startswith('#if '):stack.append((active,False));lines.append(line) if active else None;continue
                if directive=='#else' and stack and stack[-1][1]:active=stack[-1][0] and not active;continue
                if directive=='#endif' and stack:
                    parent,isdebug=stack.pop()
                    if not isdebug and active:lines.append(line)
                    active=parent;continue
                if active:lines.append(line)
            return ''.join(lines)
        item=json.loads(FIXTURE.read_bytes())['Ate/App/AteApp.swift']
        self.assertEqual([line for line in strip_debug(item['new']).splitlines() if line.strip()],
                         [line for line in strip_debug(item['old']).splitlines() if line.strip()])
    def test_probe_is_read_only_and_bounded(self):
        source=(ROOT/'Ate/App/AteApp.swift').read_text().split('enum WindowHitFailureDiagnostic {',1)[1].split('\n#endif',1)[0]
        for required in ['guard AppConfig.isUITesting','contains("-qaWindowHitFailure")','guard !captured','chain.count < 32','window.hitTest(local, with: nil)','window.windowLevel.rawValue','window.isKeyWindow','view.isHidden','view.alpha']:
            self.assertIn(required,source)
        for forbidden in ['makeKey','isHidden =','alpha =','removeFromSuperview','dismiss(','.tap(', 'sleep(', 'password', 'session.email']:
            self.assertNotIn(forbidden,source)
    def test_failure_request_has_no_actions_waits_or_retries(self):
        source=(ROOT/'AteUITests/ShoppingSyncCaptureUITests.swift').read_text().split('enum WindowHitFailureRequest {',1)[1]
        for forbidden in ['.tap(','.launch(','.activate(','.open(', 'sleep(', 'waitFor', 'while ', 'for _ in']:
            self.assertNotIn(forbidden,source)
        self.assertIn('notify_post(signal)',source)
        self.assertIn('owner.add(evidence)',source)
        self.assertIn('a request does not prove a response',source)
    def test_three_harvests_and_retention(self):
        source=(ROOT/'.github/workflows/compile-check.yml').read_text()
        for kind in ['shopping','account','navigation']:
            self.assertIn('Retain '+kind+' failure-only UIKit window probe',source)
        self.assertEqual(source.count('/ate-test-results/window-hit-failures-*'),2)
        self.assertEqual(source.count('No failure-only UIKit response file; do not infer a clear hit target.'),3)
