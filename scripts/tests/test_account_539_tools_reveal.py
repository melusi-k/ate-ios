"""Source-only reveal contract. Native compile and acceptance UNRUN."""
from pathlib import Path
import hashlib,json,unittest
from account_539_tools_reveal_delta import restore,FIXTURE
ROOT=Path(__file__).resolve().parents[2]
UNCHANGED={'.github/workflows/compile-check.yml': '9f838368cbefef34b3ec3a8537b667e1404cc4190a4398e2973bef19186f5988', 'AteUITests/KeyFlowsQATests.swift': '9085fc97e340f248bd5b101a479b02d451ddfdac42a7e8c216709ef88d2c930c', 'AteUITests/ShoppingSyncCaptureUITests.swift': 'd7e6358820b5952bae8184e9fb43b54051c49e6372977bfc21dd8c7494b9bc23', 'Ate/Views/AuthSheet.swift': '358ba3909ea2cc10a1c9868ddcfe4aaa8d7dc6f077612e8106fd11c1286b3945', 'Ate/Store/AppStore.swift': '281e20b8c4d65b2cf7e7aecc4e3b300b897174ccff9b9c99de83142b7ef06670'}
class Account539ToolsReveal(unittest.TestCase):
    def test_exact_ui_inverse_and_mutants(self):
        spec=json.loads(FIXTURE.read_bytes());raw=(ROOT/spec['path']).read_text()
        self.assertEqual(hashlib.sha256(restore('source:'+spec['path'],raw).encode()).hexdigest(),spec['before_sha256'])
        for changed in [raw.replace(spec['new'],'',1),raw+spec['new'],raw.replace('timeout: 2','timeout: 3',1),raw.replace('XCTAssertTrue(settings.buttons["settings.import"].exists)','XCTAssertFalse(settings.buttons["settings.import"].exists)',1)]:
            with self.assertRaises(AssertionError):restore('source:'+spec['path'],changed)
    def test_each_retained_assertion_has_its_own_existing_scroll(self):
        raw=(ROOT/'AteUITests/CoverageUITests.swift').read_text()
        section=raw.split('let settings = settingsContent()',1)[1].split('shot("settings-tools")',1)[0]
        for identifier in ['settings.import','settings.replayOnboarding']:
            reveal='scrollTo(settings.buttons["'+identifier+'"])'
            assertion='XCTAssertTrue(settings.buttons["'+identifier+'"].exists)'
            self.assertEqual(section.count(reveal),1)
            self.assertEqual(section.count(assertion),1)
            self.assertLess(section.index(reveal),section.index(assertion))
        for forbidden in ['sleep(', 'timeout:', 'max:', 'waitFor', '.tap(']:self.assertNotIn(forbidden,section)
    def test_no_workflow_auth_or_shopping_changes(self):
        for file,digest in UNCHANGED.items():self.assertEqual(hashlib.sha256((ROOT/file).read_bytes()).hexdigest(),digest,file)
