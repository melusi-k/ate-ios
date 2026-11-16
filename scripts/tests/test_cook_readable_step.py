"""#481 exact source/readability routing. Native pixels remain required."""
from pathlib import Path
import hashlib,unittest,json
ROOT=Path(__file__).resolve().parents[2]
FIXTURE=Path(__file__).with_name('cook_readable_step_delta.json')
FIXTURE_SHA='e9111fcc7a07c0ab7ecff34934de6ac8810cd3b66a34da5b9cf8906d6c030e7b'
def restore_readable_step(file, raw):
    from audit_cook_retry_delta import restore
    raw=restore(file,raw)
    payload=FIXTURE.read_bytes()
    assert hashlib.sha256(payload).hexdigest()==FIXTURE_SHA
    spec=json.loads(payload)[file]
    for new,old in spec['inverse']:
        assert raw.count(new)==1, 'Missing, changed or duplicated readable step delta'
        raw=raw.replace(new,old,1)
    assert hashlib.sha256(raw.encode()).hexdigest()==spec['base_sha256']
    return raw
class CookReadableStepContracts(unittest.TestCase):
    def test_exact_parent_reconstruction_and_delta_mutants(self):
        for file,spec in json.loads(FIXTURE.read_bytes()).items():
            raw=(ROOT/file).read_text()
            self.assertEqual(hashlib.sha256(restore_readable_step(file,raw).encode()).hexdigest(),spec['base_sha256'])
            for new,old in spec['inverse']:
                for changed in [raw.replace(new,'',1), raw+new]:
                    with self.assertRaises(AssertionError): restore_readable_step(file,changed)
    def test_instruction_has_fixed_size_scroll_and_no_shrink(self):
        s=(ROOT/'Ate/Views/CookModeView.swift').read_text()
        self.assertNotIn('.minimumScaleFactor(0.5)',s)
        for token in ['GeometryReader { viewport in','ScrollView(.vertical)',
                      '.fixedSize(horizontal: false, vertical: true)', 'minHeight: viewport.size.height',
                      '.scrollBounceBehavior(.basedOnSize)', '.id(index)',
                      '.accessibilityIdentifier("cookStepText")', '.accessibilityIdentifier("cookStepScroll")']:
            self.assertEqual(s.count(token),1,token)
        self.assertIn('AteFont.display(UIScreen.main.bounds.width > 400 ? 34 : 30)',s)
        self.assertLess(s.index('.id(index)'),s.index('if let secs = s.timeSeconds'))
        self.assertLess(s.index('.id(index)'),s.index('.safeAreaInset(edge: .bottom'))
    def test_fixture_is_flagged_and_exact_real_route(self):
        s=(ROOT/'Ate/App/CookReadableStepQAFixture.swift').read_text()
        self.assertIn('#if DEBUG',s)
        self.assertIn('guard AppConfig.isUITesting,',s)
        self.assertIn('-qaCookReadableStep',s)
        self.assertIn('store.cookTarget = CookTarget(id: recipe.id)',s)
        self.assertIn('Final check: serve the stew while warm.',s)
        app=(ROOT/'Ate/App/AteApp.swift').read_text()
        self.assertEqual(app.count('CookReadableStepQAFixture.prepare(st)'),1)
    def test_native_and_ci_require_long_step_case(self):
        native=(ROOT/'AteUITests/CookReadableStepUITests.swift').read_text()
        for name in ['cook-long-step-top-normal-text','cook-long-step-end-normal-text',
                     'cook-short-next-step-normal-text','cook-return-to-long-step-start-normal-text']:
            self.assertIn(name,native)
        self.assertIn('XCTAssertEqual(next.frame, controlFrame',native)
        ci=(ROOT/'.github/workflows/compile-check.yml').read_text()
        self.assertIn('-only-testing:AteUITests/CookReadableStepUITests',ci)
        self.assertIn('CookReadableStepUITests testLongInstructionScrollsWithoutMovingStepControls',ci)
    def test_existing_cook_native_inputs_and_allowances_remain(self):
        for file,digest in ORIGINALS.items():
            self.assertEqual(hashlib.sha256((ROOT/file).read_bytes()).hexdigest(),digest,file)
ORIGINALS={'AteUITests/KeyFlowsQATests.swift': 'c07bdfa3a5a831f9fac67e546a6ab6607e73f141f7f6793cd8d1d6c6bb69d629', 'AteUITests/CookSharedStepUITests.swift': 'b0952721702e3e991110faeb4f62af9e2171e26f8c5b356923458fb548394f43', 'AteUITests/CookIngredientsUITests.swift': 'be36a27eba7049f3b7d439625516edc090b516027daf26a227220e8a5e76aedb'}
