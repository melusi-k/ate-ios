#!/usr/bin/env python3
"""Publish an immutable engineering artifact, verify download, then allow alias update.

No validation/promotion authority: this checks artifact identity only. Existing tags,
immutable releases and assets are never overwritten or deleted. Only latest-build
is mutable. A conflict fails closed.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


class PublicationError(RuntimeError):
    pass


def run(*args):
    result = subprocess.run(args, text=True, capture_output=True)
    if result.returncode:
        # Preserve verifier/API diagnostics instead of hiding the failing command.
        raise PublicationError("Command failed: " + " ".join(args) + "\n" + result.stdout + result.stderr)
    return result.stdout.strip()


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def tag_sha(tag):
    # Failure talking to origin is an error, not evidence that the tag is absent.
    text = run("git", "ls-remote", "--tags", "origin", "refs/tags/" + tag,
               "refs/tags/" + tag + "^{}")
    refs = dict(line.split()[::-1] for line in text.splitlines() if line)
    return refs.get("refs/tags/" + tag + "^{}", refs.get("refs/tags/" + tag))


def release(tag):
    # Enumerate via the supported CLI with pagination. A nonzero response fails closed.
    text = run("gh", "api", "--paginate", "--slurp", "repos/{owner}/{repo}/releases?per_page=100")
    rows = [item for page in json.loads(text) for item in page]
    return next((item for item in rows if item["tag_name"] == tag), None)


def publish(args):
    ipa = Path(args.ipa).resolve()
    checksum = Path(str(ipa) + ".sha256")
    expected = digest(ipa)
    expected_line = expected + "  " + ipa.name + "\n"
    checksum.write_text(expected_line)
    target = tag_sha(args.tag)
    if target is not None and target != args.sha:
        raise PublicationError("Immutable tag points at another source commit")
    existing = release(args.tag)
    if existing is not None:
        if target is None or existing.get("draft") or not existing.get("prerelease"):
            raise PublicationError("Existing release has incompatible tag or publication state")
        if sorted(a["name"] for a in existing.get("assets", [])) != sorted([ipa.name, checksum.name]):
            raise PublicationError("Existing immutable release has a different asset inventory")
    else:
        if target is None:
            run("git", "tag", args.tag, args.sha)
            run("git", "push", "origin", "refs/tags/" + args.tag)
        run("gh", "release", "create", args.tag, str(ipa), str(checksum), "--prerelease",
            "--verify-tag", "--title", args.title, "--notes-file", args.notes)
    # Even a successful create or an existing matching asset list is not byte verification.
    with tempfile.TemporaryDirectory(prefix="ate-published-") as temp:
        run("gh", "release", "download", args.tag, "--dir", temp,
            "--pattern", ipa.name, "--pattern", checksum.name)
        downloaded = Path(temp) / ipa.name
        if digest(downloaded) != expected or (Path(temp) / checksum.name).read_text() != expected_line:
            raise PublicationError("Published artifact differs from this build; history left untouched")
        report = run("bash", "scripts/verify-ipa.sh", str(downloaded), str(Path(temp) / checksum.name),
                     args.version, str(args.build))
        print(report, flush=True)
    return expected


def rolling_allowed(build, sha, ref):
    if ref != "refs/heads/main":
        return False
    # A newer run number can still be a rerun/dispatch of old main source.
    # Such builds keep their immutable artifact without moving the main alias.
    main_ref = run("git", "ls-remote", "origin", "refs/heads/main")
    current_main = main_ref.split()[0] if main_ref else None
    if current_main is None:
        raise PublicationError("Cannot resolve current main before updating rolling alias")
    if current_main != sha:
        return False
    current = release("latest-build")
    if current is None:
        return True
    # Existing releases have versioned IPA names. Unknown/ambiguous history must be reviewed,
    # never treated as an empty pointer. Same-number updates require the same source tag.
    names = [a["name"] for a in current.get("assets", []) if a["name"].endswith(".ipa")]
    if len(names) != 1:
        raise PublicationError("Cannot identify current latest-build number safely")
    match = re.fullmatch(r"Ate-[0-9.]+-build([0-9]+)(?:-[^/]+)?\.ipa", names[0])
    if not match:
        raise PublicationError("Unrecognized latest-build asset name")
    previous = int(match[1])
    if previous > build:
        return False
    if previous == build:
        if tag_sha("latest-build") != sha:
            raise PublicationError("Same build number conflicts with current rolling source")
        return False  # Idempotent replay leaves rolling release untouched.
    return True


def update_latest(args):
    # Publication-job repository concurrency serializes this writer with other
    # publication jobs. Re-read state immediately before replacing the mutable convenience alias.
    if not rolling_allowed(args.build, args.sha, args.ref):
        return False
    current = release("latest-build")
    remote = tag_sha("latest-build")
    if current is not None:
        run("gh", "release", "delete", "latest-build", "--yes")
    if remote is not None:
        run("git", "push", "origin", ":refs/tags/latest-build")
    run("git", "tag", "-f", "latest-build", args.sha)
    run("git", "push", "origin", "refs/tags/latest-build")
    ipa = Path(args.ipa).resolve()
    run("gh", "release", "create", "latest-build", str(ipa), str(ipa) + ".sha256",
        "--prerelease", "--verify-tag", "--title",
        "Latest engineering build " + args.version + " (" + str(args.build) + ") @ " + args.sha[:7],
        "--notes-file", args.notes)
    actual = release("latest-build")
    if actual is None or sorted(a["name"] for a in actual.get("assets", [])) != sorted([ipa.name, ipa.name + ".sha256"]):
        raise PublicationError("Rolling asset inventory mismatch; immutable build remains available")
    with tempfile.TemporaryDirectory(prefix="ate-rolling-") as temp:
        run("gh", "release", "download", "latest-build", "--dir", temp)
        if {f.name for f in Path(temp).iterdir()} != {ipa.name, ipa.name + ".sha256"}:
            raise PublicationError("Rolling download inventory mismatch")
        for file in (ipa, Path(str(ipa) + ".sha256")):
            if digest(Path(temp) / file.name) != digest(file):
                raise PublicationError("Rolling downloaded bytes mismatch; immutable build remains available")
    return True


def prepare_handoff(args):
    ipa = Path(args.ipa).resolve()
    checksum = Path(str(ipa) + ".sha256")
    checksum.write_text(digest(ipa) + "  " + ipa.name + "\n")
    notes = ipa.parent / "notes.md"
    notes.write_bytes(Path(args.notes).read_bytes())
    record = {key: getattr(args, key) for key in
              ("tag", "sha", "version", "build", "title", "ref", "run_id", "run_attempt")}
    record["ipa"] = ipa.name
    record["files"] = {f.name: digest(f) for f in (ipa, checksum, notes)}
    manifest = ipa.parent / "manifest.json"
    manifest.write_text(json.dumps(record, sort_keys=True) + "\n")
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write("manifest_sha256=" + digest(manifest) + "\n")


def load_handoff(args):
    root = Path(args.handoff).resolve()
    manifest = root / "manifest.json"
    if digest(manifest) != args.manifest_sha256:
        raise PublicationError("Handoff manifest differs from source-job output")
    record = json.loads(manifest.read_text())
    for field in ("sha", "ref", "run_id", "run_attempt"):
        if record[field] != getattr(args, field):
            raise PublicationError("Handoff identity mismatch: " + field)
    ipa = record["ipa"]
    if Path(ipa).name != ipa or not ipa.endswith(".ipa"):
        raise PublicationError("Invalid handoff IPA filename")
    wanted = {ipa, ipa + ".sha256", "notes.md"}
    if set(record["files"]) != wanted or {f.name for f in root.iterdir()} != wanted | {"manifest.json"}:
        raise PublicationError("Unexpected handoff file inventory")
    for name, expected in record["files"].items():
        if digest(root / name) != expected:
            raise PublicationError("Handoff file checksum mismatch: " + name)
    record.pop("files")
    record["ipa"] = str(root / ipa)
    record["notes"] = str(root / "notes.md")
    return argparse.Namespace(**record)


def validate_args(args):
    if not re.fullmatch(r"[0-9a-f]{40}", args.sha or "") or not isinstance(args.build, int) or args.build < 1:
        raise PublicationError("Expected full source SHA and positive build number")
    if not re.fullmatch(r"build-" + str(args.build) + r"(?:-[^/]+)?", args.tag or ""):
        raise PublicationError("Tag must identify this build number exactly")
    # workflow_dispatch channel is free text, not an alphanumeric enum. Retain
    # literal filename-safe suffixes that Git already accepts, without renaming.
    run("git", "check-ref-format", "refs/tags/" + args.tag)
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", args.version or ""):
        raise PublicationError("Expected numeric app version")


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ("tag", "sha", "ipa", "version", "title", "notes", "ref", "run-id", "run-attempt"):
        p.add_argument("--" + name)
    p.add_argument("--build", type=int)
    p.add_argument("--prepare-handoff", action="store_true")
    p.add_argument("--handoff")
    p.add_argument("--manifest-sha256")
    args = p.parse_args()
    if args.handoff:
        if args.prepare_handoff:
            p.error("Cannot prepare and load a handoff together")
        args = load_handoff(args)
    validate_args(args)
    if getattr(args, "prepare_handoff", False):
        prepare_handoff(args)
        return
    value = publish(args)
    print("Verified immutable engineering artifact " + args.tag + " SHA-256 " + value, flush=True)
    changed = update_latest(args)
    print("latest-build updated" if changed else "latest-build left untouched")


if __name__ == "__main__":
    main()
