#!/usr/bin/env python3
"""Fingerprint checked-in simulator inputs, never run-stamped generated files."""
import hashlib
import subprocess

SOURCE_ROOTS = ('Ate/', 'AteWidgets/', 'AteShare/', 'AteWatch/', 'AteWatchWidgets/',
                'AteClip/', 'Shared/', 'SharedWidgets/')
GENERATOR_INPUTS = {'project.yml', 'scripts/gen-beta-checklist.py',
                    'scripts/gen-build-notes.py', 'docs/MVP_CHECKLIST.md'}


def source_fingerprint(repo='.'):
    entries = subprocess.check_output(['git', '-C', str(repo), 'ls-tree', '-r', '-z', 'HEAD'])
    selected = []
    for entry in entries.split(b'\0'):
        if not entry:
            continue
        path = entry.split(b'\t', 1)[1].decode()
        if path in GENERATOR_INPUTS or path.endswith('Package.resolved') or path.startswith(SOURCE_ROOTS):
            selected.append(entry)
    if not any(entry.endswith(b'\tproject.yml') for entry in selected):
        raise ValueError('checked-in project.yml is required for simulator cache provenance')
    return hashlib.sha256(b'\0'.join(selected)).hexdigest()


def cache_identity(source, xcode, scheme, fatal_mode, os_name, arch):
    # Xcode contains its version AND build. Excludes build number, run ID and
    # generated pbxproj: every cache restore still runs xcodebuild and verifies plist.
    xcode_hash = hashlib.sha256(xcode.encode()).hexdigest()
    return f'sim-release-v2-{os_name}-{arch}-{xcode_hash}-{source}-{scheme}-{fatal_mode}'


if __name__ == '__main__':
    import os
    xcode = subprocess.check_output(['xcodebuild', '-version'], text=True)
    print(cache_identity(source_fingerprint(), xcode, os.environ['SCHEME'],
                         os.environ['SENTRY_FATAL_PROOF'], os.environ['RUNNER_OS'], os.environ['RUNNER_ARCH']))
