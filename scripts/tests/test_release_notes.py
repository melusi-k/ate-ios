import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "release-notes.sh"


class ReleaseNotesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.git("init", "-q")
        self.git("config", "user.name", "Fixture")
        self.git("config", "user.email", "fixture@localhost")
        self.first = self.commit("root source")
        self.git("tag", "build-1-TierA")
        self.second = self.commit("second source")
        self.git("tag", "build-2-TierA")
        self.head = self.commit("current source")

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.root), *args], text=True).strip()

    def commit(self, title):
        (self.root / "source.txt").write_text(title)
        self.git("add", "source.txt")
        self.git("commit", "-qm", title)
        return self.git("rev-parse", "HEAD")

    def notes(self, build=3, channel="TierA", sha=None, ipa=None):
        version = "0.1." + str(build)
        suffix = "-" + channel if channel else ""
        return subprocess.run(["bash", str(SCRIPT), version, str(build), sha or self.head,
                               "https://example.invalid/run", ipa or "Ate-" + version + "-build" + str(build) + suffix + ".ipa", "unsigned"],
                              cwd=self.root, text=True, capture_output=True)

    def test_same_channel_lower_ancestor_is_baseline(self):
        out = self.notes(); self.assertEqual(out.returncode, 0, out.stderr)
        self.assertIn('Baseline: `build-2-TierA`', out.stdout)
        self.assertIn('- current source', out.stdout)
        self.assertNotIn('- second source', out.stdout.split('### Recent-build catch-up')[0])
        self.assertIn('- second source', out.stdout.split('### Recent-build catch-up')[1])

    def test_test_sections_are_always_present_and_do_not_claim_pass(self):
        out = self.notes()
        self.assertIn('### What to test', out.stdout)
        self.assertIn('### How to test', out.stdout)
        self.assertIn('No mapped app journey changed', out.stdout)
        self.assertIn('source inclusion is not device acceptance', out.stdout)

    def test_changed_journal_path_adds_concrete_device_steps(self):
        path = self.root / 'Ate' / 'Views' / 'JournalViews.swift'
        path.parent.mkdir(parents=True)
        path.write_text('// fixture source')
        self.git('add', '.')
        self.git('commit', '-qm', 'Journal fixture')
        out = self.notes(sha=self.git('rev-parse', 'HEAD'))
        self.assertIn('Open the Journal tab, then Insights & Cooking History', out.stdout)
        self.assertIn('do not reset or clear all data', out.stdout)

    def test_catchup_is_channel_bound_and_excludes_unmerged_work(self):
        self.git('checkout', '-qb', 'unmerged', self.first)
        self.commit('UNMERGED must stay absent')
        self.git('tag', 'build-20-Other')
        self.git('checkout', '--detach', self.head)
        out = self.notes(build=30)
        self.assertIn('For upgrades from `build-1-TierA`', out.stdout)
        self.assertNotIn('UNMERGED must stay absent', out.stdout)
        self.assertNotIn('build-20-Other', out.stdout)

    def test_unrelated_branch_tag_cannot_hide_current_changes(self):
        self.git("checkout", "-qb", "unrelated", self.first)
        self.commit("unrelated work"); self.git("tag", "build-99-TierA")
        self.git("checkout", "--detach", self.head)
        out = self.notes(build=100)
        self.assertIn('Baseline: `build-2-TierA`', out.stdout)
        self.assertNotIn('unrelated work', out.stdout)

    def test_different_channel_does_not_replace_baseline(self):
        self.git("tag", "build-8-Production", self.second)
        out = self.notes(build=9)
        self.assertIn('Baseline: `build-2-TierA`', out.stdout)

    def test_no_same_channel_ancestor_is_explicit_full_history(self):
        out = self.notes(channel="TierB")
        self.assertIn('not a previous-release delta', out.stdout)
        self.assertIn('- root source', out.stdout)
        self.assertIn('- second source', out.stdout)
        self.assertIn('- current source', out.stdout)

    def test_unsuffixed_legacy_channel_remains_distinct(self):
        self.git("tag", "build-1", self.second)
        out = self.notes(channel="")
        self.assertIn('Baseline: `build-1`', out.stdout)
        self.assertNotIn('Baseline: `build-2-TierA`', out.stdout)

    def test_current_and_future_build_tags_are_not_previous(self):
        self.git("tag", "build-3-TierA", self.head)
        self.git("tag", "build-999-TierA", self.head)
        out = self.notes()
        self.assertIn('Baseline: `build-2-TierA`', out.stdout)
        self.assertIn('- current source', out.stdout)

    def test_exact_build_exclusion_does_not_hide_prefix_build(self):
        self.git("tag", "build-30-TierA", self.second)
        out = self.notes(build=31)
        self.assertIn('Baseline: `build-30-TierA`', out.stdout)

    def test_same_commit_prior_build_has_explicit_empty_delta(self):
        self.git("tag", "build-4-TierA", self.head)
        out = self.notes(build=5)
        self.assertIn('No new non-merge source commits since `build-4-TierA`.', out.stdout)

    def test_annotated_build_tag_resolves_as_ancestor(self):
        self.git("tag", "-a", "build-4-TierA", self.second, "-m", "fixture")
        out = self.notes(build=5)
        self.assertIn('Baseline: `build-4-TierA`', out.stdout)

    def test_invalid_target_fails_without_head_fallback(self):
        out = self.notes(sha="deadbeef")
        self.assertNotEqual(out.returncode, 0)
        self.assertNotIn('current source', out.stdout)
        self.assertNotIn('### Source changes', out.stdout)

    def test_ipa_identity_mismatch_fails(self):
        out = self.notes(ipa="Ate-0.1.3-build4-TierA.ipa")
        self.assertNotEqual(out.returncode, 0)
        self.assertIn('does not match', out.stderr)

    def test_no_twenty_commit_truncation_on_first_channel(self):
        for i in range(25): self.commit("extra-" + str(i))
        out = self.notes(channel="TierC", sha=self.git("rev-parse", "HEAD"))
        self.assertIn('- root source', out.stdout)
        self.assertIn('- extra-24', out.stdout)

    def test_checkout_head_does_not_change_target_notes(self):
        self.commit("later checkout source")
        out = self.notes()
        self.assertIn('- current source', out.stdout)
        self.assertNotIn('later checkout source', out.stdout)
        self.assertIn(self.head, out.stdout)

    def test_shallow_checkout_fails_closed(self):
        clone = self.root / "shallow"
        subprocess.run(["git", "clone", "-q", "--depth", "1", self.root.as_uri(), str(clone)], check=True)
        old = self.root; self.root = clone
        try: out = self.notes()
        finally: self.root = old
        self.assertNotEqual(out.returncode, 0)
        self.assertIn('Full git history', out.stderr)

    def test_prefix_and_malformed_tags_do_not_match_channel(self):
        self.git("tag", "build-9-TierAB", self.second)
        self.git("tag", "build-8-TierA-extra", self.second)
        self.git("tag", "build-07-TierA", self.second)
        out = self.notes(build=10)
        self.assertIn('Baseline: `build-2-TierA`', out.stdout)

    def test_symbolic_target_not_accepted_as_exact_source(self):
        out = self.notes(sha="HEAD")
        self.assertNotEqual(out.returncode, 0)
        self.assertIn('full source commit SHA', out.stderr)

    def test_noncommit_full_object_id_fails(self):
        blob = self.git("rev-parse", "HEAD:source.txt")
        out = self.notes(sha=blob)
        self.assertNotEqual(out.returncode, 0)
        self.assertNotIn('### Source changes', out.stdout)

    def test_custom_dash_dot_underscore_channel_preserved_exactly(self):
        for channel in ("Internal-QA", "Internal.QA", "Internal_QA"):
            self.git("tag", "build-2-" + channel, self.second)
            out = self.notes(channel=channel)
            self.assertEqual(out.returncode, 0, out.stderr)
            self.assertIn('Baseline: `build-2-' + channel + '`', out.stdout)

    def test_git_invalid_channel_fails_before_notes(self):
        out = self.notes(channel="Internal..QA")
        self.assertNotEqual(out.returncode, 0)
        self.assertNotIn('### Source changes', out.stdout)

    def test_all_documented_channels_accepted(self):
        for channel in ("Production", "TierA", "TierB", "TierC"):
            out = self.notes(channel=channel)
            self.assertEqual(out.returncode, 0, out.stderr)


if __name__ == "__main__":
    unittest.main()
