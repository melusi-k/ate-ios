from pathlib import Path
import json,re,subprocess,unittest
ROOT=Path(__file__).resolve().parents[2]
class LocalRoadmapContracts(unittest.TestCase):
    def test_bundled_catalog_is_unique_honest_and_separate_from_release_tour(self):
        catalog=json.loads((ROOT/'Ate/Resources/ProductUpdates/roadmap.json').read_text())
        self.assertEqual(catalog['schemaVersion'],1)
        self.assertTrue(catalog['cards'])
        self.assertEqual(len(catalog['cards']),len({c['id'] for c in catalog['cards']}))
        for card in catalog['cards']:
            self.assertRegex(card['id'],r'^[a-z0-9-]+$')
            for field in ['title','summary','detail']:self.assertTrue(card[field].strip())
            self.assertEqual(card['status'],'considering')
            self.assertNotIn('votes',card);self.assertNotIn('count',card)
        self.assertIn('path: Ate/Resources/ProductUpdates\n        type: folder\n        buildPhase: resources',(ROOT/'project.yml').read_text())
    def test_always_on_settings_route_and_accessible_detail(self):
        settings=(ROOT/'Ate/Views/SettingsView.swift').read_text()
        product=settings.split('Section("Product") {',1)[1].split('Section("Diagnostics")',1)[0]
        self.assertIn('RoadmapView()',product)
        self.assertNotIn('if ',product)
        ui=(ROOT/'Ate/Views/RoadmapView.swift').read_text()
        for token in ['roadmap.unavailable','roadmap.empty','roadmap.localOnly','roadmap.voteStatus','roadmap.votesUnavailable',
                      '.accessibilityLabel(','.accessibilityValue(','.accessibilityHint(', 'height: 48','It is not submitted to Ate']:
            self.assertIn(token,ui)
        for forbidden in ['URLSession','Supabase','AuthSheet','ProductWhatsNew','withAnimation','communityCount']:
            self.assertNotIn(forbidden,ui)
    def test_card_metadata_stays_on_actionable_navigation_link(self):
        source=(ROOT/'Ate/Views/RoadmapView.swift').read_text()
        cards=source.split('ForEach(catalog.cards) { card in',1)[1].split('            } else {',1)[0]
        self.assertIn('NavigationLink { RoadmapDetailView(card: card, votes: votes) } label:',cards)
        # A synthetic .ignore container produced an identified Other around an unidentified Button.
        # Keep the native link as the element receiving all metadata and the explicit button trait.
        self.assertNotIn('.accessibilityElement(',cards)
        modifiers=cards.split('.buttonStyle(.plain)',1)[1]
        for token in ['.accessibilityAddTraits(.isButton)', '.accessibilityLabel(',
                      '.accessibilityValue(', '.accessibilityHint(', '.accessibilityIdentifier("roadmap.card.']:
            self.assertIn(token,modifiers)
        self.assertEqual(modifiers.count('.accessibilityIdentifier('),1)
    def test_real_local_storage_set_and_catalog_fail_closed(self):
        source=(ROOT/'Ate/Logic/Roadmap.swift').read_text()
        for token in ['Set(stored)','updated.remove(id)','updated.insert(id)','updated.sorted()',
                      'defaults.set(data','allowedIDs.contains(id)','guard error == nil','Voting is unavailable',
                      'catalog.schemaVersion == 1','CatalogError.invalid','subdirectory: "ProductUpdates"']:
            self.assertIn(token,source)
        for forbidden in ['URLSession','Supabase','Keychain','UUID','synchronize()']:
            self.assertNotIn(forbidden,source)
    def test_native_acceptance_sources_do_not_fake_network_or_votes(self):
        unit=(ROOT/'AteTests/RoadmapTests.swift').read_text()
        ui=(ROOT/'AteUITests/RoadmapUITests.swift').read_text()
        for token in ['testActualBundledCatalogLoadsWithoutNetwork','testCorruptLocalPreferences','testVoteUnvoteAndRelaunchPersistence','XCTAssertThrowsError']:
            self.assertIn(token,unit)
        self.assertGreaterEqual(ui.count('app.terminate()'),2)
        self.assertIn('XCTAssertGreaterThanOrEqual(vote.frame.height, 44)',ui)
        for token in ['Mock','-qaRoadmap','launchEnvironment','sleep(']:self.assertNotIn(token,ui)
        # Lane retired 2026-11-18 (workflow cleanup call 2): unit selection lives in
        # Compile's focused step, the UI journey in Dogfood's folded group 11.
        compile_wf=(ROOT/'.github/workflows/compile-check.yml').read_text()
        dogfood=(ROOT/'.github/workflows/dogfood-qualification.yml').read_text()
        self.assertIn('-only-testing:AteTests/RoadmapTests',compile_wf)
        self.assertIn('-only-testing:AteUITests/RoadmapUITests',dogfood)
        # The no-retry contract applies to this lane's own folded block (group 11);
        # the full Dogfood file legitimately names retry-lifecycle diagnostics elsewhere.
        group11=dogfood.split('Folded group 11',1)[1].split('Record qualification metadata',1)[0]
        self.assertNotIn('retry',group11)
        # Time boundary (packet-13-r2 ruling): the retired lane's 30m job ceiling becomes
        # explicit 30m caps on the two focused roadmap steps; no job timeout is raised.
        self.assertIn('timeout-minutes: 30',group11)
        roadmap_step=compile_wf.split('Roadmap and product-updates unit tests (retired lane contract)',1)[1].split('Retain full unit diagnostics',1)[0]
        self.assertIn('timeout-minutes: 30',roadmap_step)
