from pathlib import Path
import json,re,unittest,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
class ProductUpdatesLaunchContracts(unittest.TestCase):
    def test_offline_and_current_version_only(self):
        files=['Ate/Logic/ProductUpdates.swift','Ate/Logic/ProductUpdatesSeenStore.swift','Ate/Views/ProductUpdatesLaunchHost.swift','Ate/Views/ProductUpdatesViews.swift']
        code='\n'.join((ROOT/p).read_text() for p in files)
        for bad in ['URLSession','Supabase','https://','AsyncImage','Net.','import Notelet']:
            self.assertNotIn(bad,code)
        data=json.loads((ROOT/'Ate/Resources/ProductUpdates/catalog.json').read_text())
        version=re.search('MARKETING_VERSION: "([^"]+)"',(ROOT/'project.yml').read_text()).group(1)
        self.assertEqual({r['version'] for r in data['releases']},{version})
        for r in data['releases']:
            self.assertTrue(r['whatToTest']);self.assertTrue(r['howToTest'])
            self.assertIn('Pilot candidate',r['stage'])
        self.assertIn('CFBundleShortVersionString',(ROOT/'Ate/Services/BackendService.swift').read_text())
    def test_seen_only_on_dismiss_and_review_not_for_selection(self):
        model=(ROOT/'Ate/Logic/ProductUpdatesSeenStore.swift').read_text()
        self.assertIn('$0.version == version && !$0.slides.isEmpty',model)
        self.assertIn('!hasSeen(version)',model)
        host=(ROOT/'Ate/Views/ProductUpdatesLaunchHost.swift').read_text()
        self.assertIn('scenePhase == .active, !blocked',host)
        self.assertIn('version: AppConfig.appVersion',host)
        self.assertLess(host.index('onDismiss:'),host.index('seen.markSeen(version)'))
        self.assertIn('if !incoming, let version',host)
        self.assertLess(host.index('seen.markSeen(version)'),host.index('requestReview()'))
        self.assertIn('.modifier(ProductUpdatesLaunchHost())',(ROOT/'Ate/App/AteApp.swift').read_text())
        self.assertIn('struct ProductUpdatesCatalog: Codable',(ROOT/'Ate/Logic/ProductUpdates.swift').read_text())
    def test_native_acceptance_covers_relaunch_and_real_swipe(self):
        unit=(ROOT/'AteTests/ProductUpdatesLaunchTests.swift').read_text()
        for text in ['testUnseenOnlyAndSeenPersistenceAcrossNewStoreAndDefaultsInstance','testMissingUnknownFutureAndNoSlideCatalogsNeverInventLaunchRelease','JSONEncoder().encode(local)']:
            self.assertIn(text,unit)
        ui=(ROOT/'AteUITests/ProductUpdatesLaunchUITests.swift').read_text()
        for text in ['app.swipeLeft()','app.terminate()','app.launch()','XCTAssertFalse(page.exists','Seen release remains replayable']:
            self.assertIn(text,ui)

    def test_real_handlers_share_incoming_priority_and_workflow_runs_class(self):
        app=(ROOT/'Ate/App/AteApp.swift').read_text()
        store=(ROOT/'Ate/Store/AppStore.swift').read_text()
        self.assertIn('.onOpenURL { store.handle(url: $0) }',app)
        self.assertIn('if let u = a.webpageURL { store.handle(url: u) }',app)
        self.assertIn('guard productUpdatesIncomingWork.receive(url) else { return }',store)
        workflow=(ROOT/'.github/workflows/product-updates-ui.yml').read_text()
        for term in ['timeout-minutes: 60','runs-on: xcode-27','-only-testing:AteUITests/ProductUpdatesLaunchUITests','verify-product-updates-results.py']:
            self.assertIn(term,workflow)
        ui=(ROOT/'AteUITests/ProductUpdatesLaunchUITests.swift').read_text()
        self.assertIn('app.open(URL(string: "ate://shopping")!)',ui)
        self.assertIn('testOnboardingHandoffPresentsUnseenTourOnlyAfterContinue',ui)

    def test_required_named_pass_verifier_rejects_missing_or_zero_execution(self):
        rows=[]
        for folder,file in [('AteTests','ProductUpdatesTests.swift'),('AteTests','ProductUpdatesLaunchTests.swift'),('AteUITests','ProductUpdatesLaunchUITests.swift')]:
            suite=file.removesuffix('.swift')
            for match in re.finditer(r'(?:final class|extension) (\w+)[^{]*\{|func (test\w+)\(', (ROOT/folder/file).read_text()):
                if match.group(1): suite=match.group(1)
                else: rows.append(f"Test Case '-[{folder}.{suite} {match.group(2)}]' passed (1.0 seconds).")
        rows.append("Test Case '-[AteUITests.InsightsPresentationUITests testSettingsReleaseNotesAndReplayableTourAtNormalText]' passed (1.0 seconds).")
        with tempfile.TemporaryDirectory() as tmp:
            log=Path(tmp)/'test.log'
            for payload,ok in [('\n'.join(rows),True),('\n'.join(rows[:-1]),False),('Executed 0 tests',False)]:
                log.write_text(payload)
                result=subprocess.run(['python3',str(ROOT/'scripts/verify-product-updates-results.py'),str(log)],capture_output=True,text=True)
                self.assertEqual(result.returncode == 0,ok,result.stdout+result.stderr)
