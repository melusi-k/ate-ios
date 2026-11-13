#!/usr/bin/env python3
"""macOS native fixture: two REAL processes use the actual app/shared gate.
Run manually on Reviewer macOS; no backend, account, network or installed app.
Not executed/qualified by adding this script. iOS simulator journeys remain needed.
"""
import pathlib
import subprocess
import tempfile
ROOT = pathlib.Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='ate-native-process-gate-') as temp:
    temp = pathlib.Path(temp).resolve()
    binary = temp / 'gate-fixture'
    sources = ['Shared/SharedWriterGate.swift', 'Shared/SharedArchiveWriterLease.swift',
               'Shared/SharedResetControl.swift', 'Shared/AppGroupResolver.swift',
               'Shared/SharedNotificationSubmission.swift',
               'Ate/Store/AccountWriterGate.swift', 'scripts/native/food-journal-process-gate.swift']
    subprocess.run(['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
                    *[str(ROOT / s) for s in sources], '-o', str(binary)], check=True)
    writer = subprocess.Popen([str(binary), 'writer', str(temp)], stdin=subprocess.PIPE,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
    reset = None
    try:
        assert writer.stdout.readline().strip() == 'captured'
        reset = subprocess.Popen([str(binary), 'reset', str(temp)], stdin=subprocess.PIPE,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, bufsize=1)
        assert reset.stdout.readline().strip() == 'reset-held'
        writer.stdin.write('write\n'); writer.stdin.flush()
        assert writer.stdout.readline().strip() == 'refused', 'writer escaped active reset flock'
        assert not (temp / 'late-image.jpg').exists()
        reset.stdin.write('release\n'); reset.stdin.flush()
        assert reset.stdout.readline().strip() == 'reset-released'
        assert reset.wait(timeout=10) == 0, reset.stderr.read()
        writer.stdin.write('write\n'); writer.stdin.flush()
        assert writer.stdout.readline().strip() == 'refused', 'old captured epoch escaped after reset'
        assert not (temp / 'late-image.jpg').exists()
        writer.stdin.close()
        assert writer.wait(timeout=10) == 0, writer.stderr.read()
        print('PASS: distinct writer/reset processes refuse during reset and after epoch rotation; no late image')
    finally:
        for child in [writer, reset]:
            if child is not None and child.poll() is None:
                child.kill(); child.wait()
