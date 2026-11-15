from pathlib import Path
import importlib.util
import json
import re
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('release_history', ROOT / 'scripts/gen-release-history.py')
history = importlib.util.module_from_spec(spec)
spec.loader.exec_module(history)


class ReleaseHistoryTests(unittest.TestCase):
    def test_catalog_is_deterministic_snapshot_of_published_builds_only(self):
        published = json.loads(history.SNAPSHOT.read_text())['releases']
        sources = json.loads(history.PROVENANCE.read_text())
        source_by_tag = {r['tag']: r for r in sources['builds']}
        expected = []
        # Offline deterministic render: fail if this regression ever tries Git.
        with patch.object(history, 'git', side_effect=AssertionError('CI must not read historical Git objects')):
            for release in sorted(published, key=lambda r: int(re.search(r'\d+', r['tag'])[0]), reverse=True):
                source = source_by_tag[release['tag']]
                rendered, provenance = history.render_entry(release, source['previous_commit'],
                                                            source['recorded_changes'], source['source_version'])
                self.assertEqual(provenance, source)
                expected.append(rendered)
        actual = json.loads(history.CATALOG.read_text())
        self.assertEqual([r for r in actual['releases'] if 'buildNumber' in r], expected)
        expected = {'releases': expected}
        builds = [r for r in expected['releases'] if 'buildNumber' in r]
        self.assertEqual({r['id'] for r in builds}, {r['tag'] for r in published})
        self.assertEqual([r['buildNumber'] for r in builds], sorted((r['buildNumber'] for r in builds), reverse=True))
        self.assertEqual([r['buildNumber'] for r in builds[:5]], [445, 444, 443, 442, 441])
        self.assertNotIn('latest-build', {r['id'] for r in builds})
        self.assertGreater(len(builds), 1)

    def test_every_build_has_own_notes_and_verified_source(self):
        catalog = json.loads(history.CATALOG.read_text())
        sources = {r['tag']: r for r in json.loads(history.PROVENANCE.read_text())['builds']}
        for release in catalog['releases']:
            if 'buildNumber' not in release:
                continue
            self.assertEqual(release['minimumBuild'], release['buildNumber'])
            self.assertTrue(release['summary'])
            self.assertTrue(release['changes'])
            source = sources[release['id']]
            self.assertRegex(source['commit'], r'^[a-f0-9]{40}$')
            self.assertTrue(source['release_url'].startswith('https://github.com/melusi-k/ate-ios/releases/tag/'))
            for selected in source['selected']:
                self.assertEqual(history.readable_subject(selected['subject']), selected['text'])
                self.assertRegex(selected['commit'], r'^[a-f0-9]{40}$')
        self.assertEqual(sources['build-445-TierA']['commit'], 'a5c884f713eefefad52f25b659cbe43cd2cdceea')

    def test_real_442_crlf_body_keeps_its_main_feature_and_caveats(self):
        release = next(r for r in json.loads(history.SNAPSHOT.read_text())['releases']
                       if r['tag'] == 'build-442-Production')
        self.assertIn('\r\n', release['notes'])
        rendered, _ = history.render_entry(release, None, [], '0.1.0')
        self.assertEqual(rendered['summary'], 'Combined test build: Journal actions, Cook countdown and Settings tabs')
        copy = ' '.join(r['text'] for r in rendered['changes'])
        self.assertIn('native Journal delete', copy)
        self.assertIn('NOT API-compatible for cloud upload', copy)
        self.assertIn('Food Journal activation stays OFF', copy)
        self.assertNotIn('no readable feature summary', copy)

    def test_engineering_only_subjects_are_not_product_claims(self):
        for subject in ['Update AddRecipeSheet.swift', 'Fold reviewed Bundle A source 1/69',
                        'test: retain bounded cleanup fixture', 'CI: add recipe timeout',
                        'Clarify closed sync selector repair versus open quarantine re-admission',
                        'Replace dead PhotoGuess.prompt() with canDraft predicate (#253)']:
            self.assertIsNone(history.readable_subject(subject))
        self.assertEqual(history.readable_subject('fix: retain Journal reflection drafts'),
                         'Retain Journal reflection drafts')

    def test_initial_screen_uses_ten_rows_with_incremental_history(self):
        ui = (ROOT / 'Ate/Views/ProductUpdatesViews.swift').read_text()
        self.assertIn('@State private var visibleBuildCount = 10', ui)
        self.assertIn('builds.prefix(visibleBuildCount)', ui)
        self.assertIn('visibleBuildCount += 10', ui)
        self.assertIn('Show older releases', ui)
        self.assertIn('ProductReleaseDetailView(release: release)', ui)
