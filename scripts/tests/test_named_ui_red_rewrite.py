"""Exact delta contracts and observable progress subprocesses, not native proof."""
from pathlib import Path
import hashlib, importlib.util, json, subprocess, sys, tempfile, unittest
from named_ui_red_rewrite_delta import restore
from today_tab_ui_delta import restore as restore_today_tab_ui
ROOT = Path(__file__).resolve().parents[2]


class NamedRedRewriteTests(unittest.TestCase):
    def test_only_named_methods_change_and_exact_inverse_rejects_mutants(self):
        contracts = json.loads((ROOT/'scripts/tests/named_ui_red_rewrite_inverse.json').read_text())
        expected = {
            'AteUITests/AteUITests.swift': ['test06_CookMode', 'testCookModeCompletionRecordsCookingDay'],
            'AteUITests/CoverageUITests.swift': ['test32_MoreCollectionsToolsAbout', 'testBottomBarsDoNotOverlapRecipeDetail'],
            'AteUITests/LibraryProteinGroupingUITests.swift': ['testPorkLedRibsAppearUnderPorkAtNormalText']}
        for path, c in contracts.items():
            source = restore_today_tab_ui(path, (ROOT/path).read_text())
            self.assertEqual(hashlib.sha256(source.encode()).hexdigest(), c['current_sha'])
            self.assertEqual(hashlib.sha256(restore(path, source).encode()).hexdigest(), c['parent_sha'])
            self.assertEqual(sorted(f['old'].split('func ',1)[1].split('(',1)[0] for f in c['fragments']), sorted(expected[path]))
            for f in c['fragments']:
                for mutant in [source.replace(f['new'],'',1),source+f['new'],source.replace(f['new'],f['new']+'// unrelated',1)]:
                    with self.assertRaises(AssertionError):
                        normalized=restore(path,mutant)
                        assert hashlib.sha256(normalized.encode()).hexdigest()==c['parent_sha']

    def test_receipts_are_flushed_before_actions_and_no_retry_or_wait_changes(self):
        helper=(ROOT/'AteUITests/NamedRedReceipt.swift').read_text()
        self.assertLess(helper.index('emit("BEGIN step='),helper.index('let result = action()'))
        self.assertIn('FileHandle.standardOutput.write',helper)
        self.assertIn('capture=phase-only',helper)
        for query in ['element.exists', 'element.frame', 'element.identifier', 'element.label']:
            self.assertNotIn(query,helper)
        self.assertIn('XCTAttachment(screenshot:',helper)
        for token in ['sleep(', 'waitFor', 'launch()', 'terminate()', '.tap()']:
            self.assertNotIn(token,helper)
        contracts=json.loads((ROOT/'scripts/tests/named_ui_red_rewrite_inverse.json').read_text())
        for c in contracts.values():
            for f in c['fragments']:
                # Existing explicit timeout constants retained; no retry API added.
                for token in ['timeout: 10','timeout: 5','readinessBudget: TimeInterval = 2','steps < 6','swipes < 25','swipes < 50']:
                    self.assertEqual(f['new'].count(token),f['old'].count(token))
        completion=next(f['new'] for f in contracts['AteUITests/AteUITests.swift']['fragments'] if 'func test06_CookMode()' in f['new'])
        self.assertLess(completion.index('cookCompletion.recorded'),completion.index('done.tap()'))


class ProgressStreamTests(unittest.TestCase):
    def test_native_start_finish_and_heartbeat_elapsed(self):
        spec=importlib.util.spec_from_file_location('progress',ROOT/'scripts/stream-ui-test-progress.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        now=[10.0]; lines=[]
        p=module.Progress('nutrition-ui',clock=lambda:now[0],emit=lambda text,**_:lines.append(text))
        p.line("Test Case '-[AteUITests.NutritionDiaryUITests testFood]' started.\n")
        now[0]=43.5;p.receipt('heartbeat')
        self.assertIn('active_elapsed_s=33.5',lines[-1])
        p.line("Test Case '-[AteUITests.NutritionDiaryUITests testFood]' failed (33.500 seconds).\n")
        self.assertIn('native_duration_s=33.500',lines[-1])
        self.assertIsNone(p.active)

    def test_subprocess_lossless_log_partial_lines_and_pipefail(self):
        with tempfile.TemporaryDirectory() as directory:
            target=Path(directory)/'raw.log'
            raw=b"opaque stderr\nTest Case '-[Class testOne]' started.\nTest Case '-[Class testOne]' passed (1.200 seconds).\npartial\xff"
            run=subprocess.run([sys.executable,str(ROOT/'scripts/stream-ui-test-progress.py'),'--selection','ingredients','--log',str(target)],input=raw,capture_output=True,timeout=5)
            self.assertEqual(run.returncode,0)
            self.assertEqual(target.read_bytes(),raw)
            text=run.stdout.decode()
            self.assertIn('testOne',text);self.assertIn('event=started',text)
            self.assertIn('event=passed',text);self.assertIn('stream-closed-not-a-pass',text)
            command='set -o pipefail; (printf "runner-failure\\n"; exit 7) | '+sys.executable+' '+str(ROOT/'scripts/stream-ui-test-progress.py')+' --selection test --log '+str(target)
            failed=subprocess.run(['bash','-c',command],capture_output=True,timeout=5)
            self.assertEqual(failed.returncode,7)

    def test_cancel_emits_last_started_and_fails_without_pass(self):
        import signal
        with tempfile.TemporaryDirectory() as directory:
            target=Path(directory)/'raw.log'
            process=subprocess.Popen([sys.executable,'-u',str(ROOT/'scripts/stream-ui-test-progress.py'),'--selection','nutrition','--log',str(target)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
            try:
                self.assertIn(b'stream-open',process.stdout.readline())
                process.stdin.write(b"Test Case '-[Class testInterrupted]' started.\n");process.stdin.flush()
                self.assertIn(b'testInterrupted',process.stdout.readline())
                self.assertIn(b'event=started',process.stdout.readline())
                process.send_signal(signal.SIGTERM)
                output,error=process.communicate(timeout=5)
                self.assertEqual(process.returncode,143,error)
                self.assertIn(b'interrupted-signal-15',output)
                self.assertIn(b'testInterrupted',output)
                self.assertNotIn(b"event=passed",output)
                self.assertEqual(target.read_bytes(),b"Test Case '-[Class testInterrupted]' started.\n")
            finally:
                if process.poll() is None:process.kill();process.communicate()

    def test_workflow_only_streams_two_existing_commands(self):
        text=(ROOT/'.github/workflows/compile-check.yml').read_text()
        self.assertEqual(text.count('| python3 -u scripts/stream-ui-test-progress.py'),2)
        for name in ['nutrition-ui','cook-ingredients']:
            self.assertIn('--selection '+name,text)
        script=(ROOT/'scripts/stream-ui-test-progress.py').read_text()
        for forbidden in ['subprocess.', 'xcodebuild', 'os.kill(', 'os.system(']:
            self.assertNotIn(forbidden,script)
        self.assertIn("progress.receipt('heartbeat')",script)
        self.assertIn('signal.SIGTERM',script)


class ProteinHeadingIntentTests(unittest.TestCase):
    def test_owner_visibility_contract_not_header_tappability(self):
        source=(ROOT/'AteUITests/LibraryProteinGroupingUITests.swift').read_text()
        self.assertNotIn('pork.isHittable',source)
        for token in ['band.intersection(heading)', 'window.intersects(heading)', 'XCTAssertGreaterThan(fraction, 0', 'visibleFraction=', 'ribs.isHittable', 'chicken.frame.maxY, wings.frame.minY', 'wings.frame.maxY, pork.frame.minY', 'pork.frame.maxY, ribs.frame.minY']:
            self.assertIn(token,source)
