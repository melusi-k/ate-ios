import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('focus', SCRIPTS / 'build-focus.py')
focus = importlib.util.module_from_spec(spec)
spec.loader.exec_module(focus)


class BuildFocusTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git('init', '-q')
        self.git('config', 'user.name', 'Fixture')
        self.git('config', 'user.email', 'fixture@localhost')
        p = self.root / 'Ate' / 'App.swift'
        p.parent.mkdir()
        p.write_text('// actual app source')
        self.git('add', '.')
        self.git('commit', '-qm', 'runtime source')
        self.anchor = self.git('rev-parse', 'HEAD')
        self.blob = self.git('rev-parse', self.anchor + ':Ate/App.swift')
        self.record = {'title': 'Journal focus', 'summary': 'Source included; device acceptance pending.',
                       'source_commit': self.anchor, 'evidence': [{'path': 'Ate/App.swift', 'blob': self.blob}]}

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.root), *args], text=True).strip()

    def commit_record(self):
        p = self.root / 'docs' / 'build-focus.json'
        p.parent.mkdir(exist_ok=True)
        p.write_text(json.dumps(self.record))
        self.git('add', '.')
        self.git('commit', '-qm', 'reviewed focus')
        return self.git('rev-parse', 'HEAD')

    def render(self, sha):
        return subprocess.run(['python3', str(SCRIPTS / 'build-focus.py'), sha], cwd=self.root,
                              text=True, capture_output=True)

    def test_valid_focus(self):
        out = self.render(self.commit_record())
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn('### Main feature focus\n\nJournal focus', out.stdout)
        self.assertIn('device acceptance pending', out.stdout)

    def test_old_source_does_not_read_newer_checkout_record(self):
        self.commit_record()
        out = self.render(self.anchor)
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn('No main feature focus was recorded', out.stdout)
        self.assertNotIn('Journal focus', out.stdout)

    def test_changed_runtime_blob_fails_closed(self):
        self.commit_record()
        (self.root / 'Ate' / 'App.swift').write_text('// changed runtime')
        self.git('add', '.')
        self.git('commit', '-qm', 'changed runtime')
        out = self.render(self.git('rev-parse', 'HEAD'))
        self.assertNotEqual(out.returncode, 0)
        self.assertIn('evidence changed', out.stderr)

    def test_wrong_blob_fails(self):
        self.record['evidence'][0]['blob'] = 'a' * 40
        self.assertNotEqual(self.render(self.commit_record()).returncode, 0)

    def test_test_only_evidence_fails(self):
        self.record['evidence'][0]['path'] = 'AteTests/Test.swift'
        out = self.render(self.commit_record())
        self.assertNotEqual(out.returncode, 0)
        self.assertIn('app Swift source path', out.stderr)

    def test_unmerged_anchor_fails(self):
        self.git('checkout', '-qb', 'unmerged')
        (self.root / 'other').write_text('unmerged')
        self.git('add', '.')
        self.git('commit', '-qm', 'unmerged')
        self.record['source_commit'] = self.git('rev-parse', 'HEAD')
        self.git('checkout', '--detach', self.anchor)
        self.assertNotEqual(self.render(self.commit_record()).returncode, 0)

    def test_invalid_record_not_silent_fallback(self):
        self.record['title'] = 'two\nlines'
        self.assertNotEqual(self.render(self.commit_record()).returncode, 0)

    def test_invalid_sha_fails(self):
        self.assertNotEqual(self.render('HEAD').returncode, 0)

    def test_release_notes_focus_before_all_sections(self):
        sha = self.commit_record()
        out = subprocess.run(['bash', str(SCRIPTS / 'release-notes.sh'), '0.1.2', '2', sha,
                              'https://example.invalid/run', 'Ate-0.1.2-build2.ipa', 'unsigned'],
                             cwd=self.root, text=True, capture_output=True)
        self.assertEqual(out.returncode, 0, out.stderr)
        for heading in ['### Source changes', '### What to test', '### How to test']:
            self.assertLess(out.stdout.index('### Main feature focus'), out.stdout.index(heading))

    def test_about_notes_reuse_identical_focus(self):
        self.commit_record()
        out = subprocess.run(['python3', str(SCRIPTS / 'gen-build-notes.py')], cwd=self.root,
                             text=True, capture_output=True)
        self.assertEqual(out.returncode, 0, out.stderr)
        text = (self.root / 'Ate' / 'Resources' / 'BuildNotes.md').read_text()
        self.assertTrue(text.startswith('Build notes\n\nMain feature focus\n\nJournal focus\n\nSource included; device acceptance pending.'))
        self.assertLess(text.index('Main feature focus'), text.index('Changes in this build'))

    def test_shallow_checkout_rejects_unverifiable_anchor(self):
        sha = self.commit_record()
        shallow = self.root / 'shallow-clone'
        subprocess.run(['git', 'clone', '-q', '--depth', '1', self.root.as_uri(), str(shallow)], check=True)
        out = subprocess.run(['python3', str(SCRIPTS / 'build-focus.py'), sha], cwd=shallow, text=True, capture_output=True)
        self.assertNotEqual(out.returncode, 0)
        self.assertNotIn('Journal focus', out.stdout)

    def test_full_history_repairs_anchor_without_relaxing_checks(self):
        sha = self.commit_record()
        shallow = self.root / 'shallow-clone'
        subprocess.run(['git', 'clone', '-q', '--depth', '1', self.root.as_uri(), str(shallow)], check=True)
        subprocess.run(['git', '-C', str(shallow), 'fetch', '-q', '--unshallow'], check=True)
        out = subprocess.run(['python3', str(SCRIPTS / 'build-focus.py'), sha], cwd=shallow, text=True, capture_output=True)
        self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn('Journal focus', out.stdout)
