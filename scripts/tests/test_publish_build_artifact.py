import argparse
import importlib.util
from pathlib import Path
import tempfile
import json
import os
import unittest
from unittest.mock import patch

MODULE = Path(__file__).resolve().parents[1] / "publish-build-artifact.py"
spec = importlib.util.spec_from_file_location("publication", MODULE)
pub = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pub)
SHA = "a" * 40


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.ipa = Path(self.temp.name) / "Ate-0.1.353-build353-TierA.ipa"
        self.ipa.write_bytes(b"generic ipa test bytes")
        self.args = argparse.Namespace(ipa=str(self.ipa), tag="build-353-TierA", sha=SHA,
                                       title="Build", notes="notes.md", version="0.1.353", build=353, ref="refs/heads/main")
        self.calls = []
        origin_main = patch.object(pub, "run", return_value=SHA + "\trefs/heads/main")
        origin_main.start()
        self.addCleanup(origin_main.stop)

    def fake(self, *args):
        self.calls.append(args)
        if args[:3] == ("gh", "release", "download"):
            dest = Path(args[args.index("--dir") + 1])
            (dest / self.ipa.name).write_bytes(self.ipa.read_bytes())
            (dest / (self.ipa.name + ".sha256")).write_text(pub.digest(self.ipa) + "  " + self.ipa.name + "\n")
        return ""

    def existing(self):
        return {"draft": False, "prerelease": True,
                "assets": [{"name": self.ipa.name}, {"name": self.ipa.name + ".sha256"}]}

    def test_new_publication_is_downloaded_and_verified_before_return(self):
        with patch.object(pub, "tag_sha", return_value=None), patch.object(pub, "release", return_value=None), patch.object(pub, "run", side_effect=self.fake):
            self.assertEqual(pub.publish(self.args), pub.digest(self.ipa))
        self.assertTrue(any(x[:3] == ("gh", "release", "create") for x in self.calls))
        self.assertEqual(self.calls[-1][:2], ("bash", "scripts/verify-ipa.sh"))
        self.assertFalse(any("delete" in x or "--clobber" in x for x in self.calls))

    def test_same_tag_same_bytes_replay_has_no_mutation(self):
        with patch.object(pub, "tag_sha", return_value=SHA), patch.object(pub, "release", return_value=self.existing()), patch.object(pub, "run", side_effect=self.fake):
            pub.publish(self.args)
        self.assertFalse(any("create" in x or "push" in x or "delete" in x for x in self.calls))

    def test_conflicting_tag_fails_before_any_write(self):
        with patch.object(pub, "tag_sha", return_value="b" * 40), patch.object(pub, "run") as run:
            with self.assertRaises(pub.PublicationError):
                pub.publish(self.args)
            run.assert_not_called()

    def test_existing_asset_mismatch_fails_without_deletion(self):
        bad = self.existing(); bad["assets"] = []
        with patch.object(pub, "tag_sha", return_value=SHA), patch.object(pub, "release", return_value=bad), patch.object(pub, "run") as run:
            with self.assertRaises(pub.PublicationError):
                pub.publish(self.args)
            run.assert_not_called()

    def test_create_network_failure_is_not_already_exists(self):
        def fail(*args):
            if args[:3] == ("gh", "release", "create"):
                raise RuntimeError("network or permission failure")
            return self.fake(*args)
        with patch.object(pub, "tag_sha", return_value=SHA), patch.object(pub, "release", return_value=None), patch.object(pub, "run", side_effect=fail):
            with self.assertRaises(RuntimeError):
                pub.publish(self.args)
        self.assertFalse(any("download" in x or "delete" in x for x in self.calls))

    def test_downloaded_bytes_mismatch_keeps_history(self):
        def corrupt(*args):
            result = self.fake(*args)
            if args[:3] == ("gh", "release", "download"):
                dest = Path(args[args.index("--dir") + 1]); (dest / self.ipa.name).write_bytes(b"other bytes")
            return result
        with patch.object(pub, "tag_sha", return_value=SHA), patch.object(pub, "release", return_value=self.existing()), patch.object(pub, "run", side_effect=corrupt):
            with self.assertRaises(pub.PublicationError):
                pub.publish(self.args)
        self.assertFalse(any("delete" in x for x in self.calls))

    def test_tag_read_failure_is_not_missing_tag(self):
        with patch.object(pub, "run", side_effect=RuntimeError("origin unreachable")):
            with self.assertRaises(RuntimeError):
                pub.tag_sha("build-353-TierA")

    def test_off_main_never_changes_latest(self):
        with patch.object(pub, "release") as release:
            self.assertFalse(pub.rolling_allowed(353, SHA, "refs/heads/feature"))
            release.assert_not_called()

    def test_older_and_same_build_leave_alias_untouched(self):
        with patch.object(pub, "release", return_value=self.existing()), patch.object(pub, "tag_sha", return_value=SHA):
            self.assertFalse(pub.rolling_allowed(352, SHA, "refs/heads/main"))
            self.assertFalse(pub.rolling_allowed(353, SHA, "refs/heads/main"))
            self.assertTrue(pub.rolling_allowed(354, SHA, "refs/heads/main"))

    def test_unknown_alias_fails_closed(self):
        with patch.object(pub, "release", return_value={"assets": [{"name": "Ate.ipa"}]}):
            with self.assertRaises(pub.PublicationError):
                pub.rolling_allowed(354, SHA, "refs/heads/main")

    def test_same_build_other_sha_is_conflict(self):
        with patch.object(pub, "release", return_value=self.existing()), patch.object(pub, "tag_sha", return_value="b" * 40):
            with self.assertRaises(pub.PublicationError):
                pub.rolling_allowed(353, SHA, "refs/heads/main")

    def test_release_lookup_failure_is_not_absence(self):
        with patch.object(pub, "run", side_effect=RuntimeError("permission denied")):
            with self.assertRaises(RuntimeError):
                pub.release("latest-build")

    def test_alias_lookup_failure_never_deletes_anything(self):
        with patch.object(pub, "rolling_allowed", return_value=True), patch.object(pub, "release", side_effect=RuntimeError("read failure")), patch.object(pub, "run") as run:
            with self.assertRaises(RuntimeError):
                pub.update_latest(self.args)
            run.assert_not_called()

    def test_alias_update_deletes_only_mutable_alias(self):
        with patch.object(pub, "rolling_allowed", return_value=True), patch.object(pub, "release", return_value=self.existing()), patch.object(pub, "tag_sha", return_value=SHA), patch.object(pub, "run", side_effect=self.fake):
            Path(str(self.ipa) + ".sha256").write_text(pub.digest(self.ipa) + "  " + self.ipa.name + "\n")
            self.assertTrue(pub.update_latest(self.args))
        deleted = [x for x in self.calls if "delete" in x or ":refs/tags/" in " ".join(x)]
        self.assertEqual(deleted, [("gh", "release", "delete", "latest-build", "--yes"),
                                  ("git", "push", "origin", ":refs/tags/latest-build")])

    def test_smoke_verifier_failure_stops_before_alias(self):
        def fail(*args):
            if args[:2] == ("bash", "scripts/verify-ipa.sh"):
                raise RuntimeError("IPA contents invalid")
            return self.fake(*args)
        with patch.object(pub, "tag_sha", return_value=SHA), patch.object(pub, "release", return_value=self.existing()), patch.object(pub, "run", side_effect=fail):
            with self.assertRaises(RuntimeError):
                pub.publish(self.args)
        self.assertFalse(any("latest-build" in x or "delete" in x for x in self.calls))

    def test_entrypoint_never_updates_alias_when_publish_fails(self):
        argv = ["publish", "--tag", self.args.tag, "--sha", SHA, "--ipa", str(self.ipa),
                "--version", "0.1.353", "--build", "353", "--title", "Build",
                "--notes", "notes.md", "--ref", "refs/heads/main"]
        with patch("sys.argv", argv), patch.object(pub, "publish", side_effect=RuntimeError("bad download")), patch.object(pub, "update_latest") as update:
            with self.assertRaises(RuntimeError):
                pub.main()
            update.assert_not_called()

    def test_entrypoint_orders_publish_before_alias(self):
        argv = ["publish", "--tag", self.args.tag, "--sha", SHA, "--ipa", str(self.ipa),
                "--version", "0.1.353", "--build", "353", "--title", "Build",
                "--notes", "notes.md", "--ref", "refs/heads/main"]
        calls = []
        with patch("sys.argv", argv), patch.object(pub, "publish", side_effect=lambda _: calls.append("verified") or "hash"), patch.object(pub, "update_latest", side_effect=lambda _: calls.append("alias") or True):
            pub.main()
        self.assertEqual(calls, ["verified", "alias"])

    def test_workflow_has_one_writer_and_still_enforces_full_gates(self):
        root = MODULE.parents[1]
        workflow = (root / ".github/workflows/build-ipa.yml").read_text()
        self.assertIn("group: build-ipa-publication", workflow)
        self.assertIn("cancel-in-progress: false", workflow)
        self.assertIn("queue: max", workflow)
        self.assertIn("python3 scripts/publish-build-artifact.py", workflow)
        self.assertIn("artifact-ids: ${{ needs.release.outputs.publication_artifact_id }}", workflow)
        self.assertIn("digest-mismatch: error", workflow)
        self.assertNotIn("\nconcurrency:", workflow)
        self.assertIn("publication_manifest_sha256", workflow)
        self.assertNotIn("gh release delete latest-build", workflow)
        self.assertNotIn("gh release delete \"$TAG\"", workflow)
        self.assertIn("Enforce required focused full-validation gates", workflow)
        self.assertIn("needs: [release, publish-engineering, ui-suite, backend-e2e]", workflow)

    def test_new_build_number_for_old_main_cannot_move_alias(self):
        with patch.object(pub, "run", return_value="b" * 40 + "\trefs/heads/main"), patch.object(pub, "release") as release:
            self.assertFalse(pub.rolling_allowed(999, SHA, "refs/heads/main"))
            release.assert_not_called()

    def test_missing_main_ref_is_error_not_approval(self):
        with patch.object(pub, "run", return_value=""):
            with self.assertRaises(pub.PublicationError):
                pub.rolling_allowed(999, SHA, "refs/heads/main")

    def handoff(self):
        notes = Path(self.temp.name) / "source-notes.md"
        notes.write_text("Engineering, not qualification")
        self.args.notes = str(notes)
        self.args.run_id = "123"
        self.args.run_attempt = "2"
        output = Path(self.temp.name) / "outputs"
        # Handoff directory must contain only the intended four files.
        notes.unlink()
        notes = Path(self.temp.name).parent / (Path(self.temp.name).name + "-notes")
        notes.write_text("Engineering, not qualification")
        self.addCleanup(notes.unlink)
        self.args.notes = str(notes)
        with tempfile.NamedTemporaryFile() as out, patch.dict(os.environ, {"GITHUB_OUTPUT": out.name}):
            pub.prepare_handoff(self.args)
        return argparse.Namespace(handoff=self.temp.name, manifest_sha256=pub.digest(Path(self.temp.name) / "manifest.json"),
                                  sha=SHA, ref="refs/heads/main", run_id="123", run_attempt="2")

    def test_handoff_roundtrip_exact_source_run_and_bytes(self):
        handoff = self.handoff()
        restored = pub.load_handoff(handoff)
        self.assertEqual(restored.tag, self.args.tag)
        self.assertEqual(Path(restored.ipa).read_bytes(), self.ipa.read_bytes())
        self.assertEqual(restored.run_attempt, "2")

    def test_handoff_bad_manifest_digest_rejected(self):
        handoff = self.handoff(); handoff.manifest_sha256 = "0" * 64
        with self.assertRaises(pub.PublicationError): pub.load_handoff(handoff)

    def test_handoff_other_source_run_attempt_or_ref_rejected(self):
        for field in ("sha", "ref", "run_id", "run_attempt"):
            handoff = self.handoff() if field == "sha" else handoff
            old = getattr(handoff, field); setattr(handoff, field, "different")
            with self.assertRaises(pub.PublicationError): pub.load_handoff(handoff)
            setattr(handoff, field, old)

    def test_handoff_changed_ipa_fails_before_publish(self):
        handoff = self.handoff(); self.ipa.write_bytes(b"substitute")
        with self.assertRaises(pub.PublicationError): pub.load_handoff(handoff)

    def test_handoff_extra_file_rejected(self):
        handoff = self.handoff(); (self.ipa.parent / "other.ipa").write_bytes(b"other")
        with self.assertRaises(pub.PublicationError): pub.load_handoff(handoff)

    def test_paginated_release_lookup_finds_later_page(self):
        with patch.object(pub, "run", return_value=json.dumps([[{"tag_name": "other"}], [{"tag_name": "wanted"}]])) as run:
            self.assertEqual(pub.release("wanted")["tag_name"], "wanted")
            self.assertIn("--paginate", run.call_args.args)
            self.assertIn("--slurp", run.call_args.args)

    def test_fresh_alias_can_advance_for_current_main(self):
        with patch.object(pub, "release", return_value=None):
            self.assertTrue(pub.rolling_allowed(353, SHA, "refs/heads/main"))

    def test_postcreate_alias_inventory_mismatch_fails(self):
        with patch.object(pub, "rolling_allowed", return_value=True), patch.object(pub, "release", side_effect=[None, {"assets": []}]), patch.object(pub, "tag_sha", return_value=None), patch.object(pub, "run", side_effect=self.fake):
            with self.assertRaises(pub.PublicationError): pub.update_latest(self.args)
        self.assertFalse(any("delete" in x for x in self.calls))

    def test_rolling_download_mismatch_fails_without_immutable_deletion(self):
        def corrupt(*args):
            result = self.fake(*args)
            if args[:3] == ("gh", "release", "download"):
                (Path(args[args.index("--dir") + 1]) / self.ipa.name).write_bytes(b"wrong")
            return result
        Path(str(self.ipa) + ".sha256").write_text(pub.digest(self.ipa) + "  " + self.ipa.name + "\n")
        with patch.object(pub, "rolling_allowed", return_value=True), patch.object(pub, "release", return_value=self.existing()), patch.object(pub, "tag_sha", return_value=SHA), patch.object(pub, "run", side_effect=corrupt):
            with self.assertRaises(pub.PublicationError): pub.update_latest(self.args)
        self.assertFalse(any(self.args.tag in x and "delete" in x for x in self.calls))

    def test_invalid_tag_sha_version_build_rejected(self):
        for field, bad in (("tag", "build-3530"), ("sha", "short"), ("build", 0), ("version", "v1")):
            old = getattr(self.args, field); setattr(self.args, field, bad)
            with self.assertRaises(pub.PublicationError): pub.validate_args(self.args)
            setattr(self.args, field, old)


if __name__ == "__main__":
    unittest.main()
