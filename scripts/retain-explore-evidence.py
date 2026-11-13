#!/usr/bin/env python3
"""Local-only evidence extraction and console fallback, never changes test outcome."""
from pathlib import Path
import argparse
import base64
import hashlib
import json
import subprocess


def emit(path, label):
    data = path.read_bytes()
    encoded = base64.b64encode(data).decode('ascii')
    print(f'EXPLORE-EVIDENCE-BEGIN {label} bytes={len(data)} sha256={hashlib.sha256(data).hexdigest()}', flush=True)
    for start in range(0, len(encoded), 4000):
        print(f'EXPLORE-EVIDENCE-CHUNK {label} {encoded[start:start + 4000]}', flush=True)
    print(f'EXPLORE-EVIDENCE-END {label}', flush=True)


def retain(log, result, output):
    output.mkdir(parents=True, exist_ok=True)
    if log.exists():
        # Complete text goes to the independent artifact AND console, not tail120.
        target = output / 'explore-discovery.log'
        target.write_bytes(log.read_bytes())
        print('EXPLORE-FULL-LOG-BEGIN', flush=True)
        print(log.read_text(errors='replace'), flush=True)
        print('EXPLORE-FULL-LOG-END', flush=True)
        # Lossless fallback also survives control sequences in native log lines.
        emit(target, 'explore-discovery.log')
    else:
        print('EXPLORE-LOG-MISSING: test may not have started', flush=True)
    if not result.is_dir():
        print('EXPLORE-XCRESULT-MISSING: cannot classify failure from missing result', flush=True)
        return
    for kind in ['summary', 'tests']:
        p = output / f'test-{kind}.json'
        run = subprocess.run(['xcrun', 'xcresulttool', 'get', 'test-results', kind, '--path', str(result)], capture_output=True)
        p.write_bytes(run.stdout)
        (output / f'test-{kind}.stderr.txt').write_bytes(run.stderr)
        print(f'EXPLORE-EXTRACT {kind} exit={run.returncode}', flush=True)
        emit(p, p.name)
        if run.stderr:
            print(run.stderr.decode(errors='replace'), flush=True)
    attachments = output / 'attachments'
    run = subprocess.run(['xcrun', 'xcresulttool', 'export', 'attachments', '--path', str(result), '--output-path', str(attachments)], capture_output=True)
    (output / 'attachment-export.txt').write_bytes(run.stdout + run.stderr)
    print(f'EXPLORE-EXTRACT attachments exit={run.returncode}', flush=True)
    print((run.stdout + run.stderr).decode(errors='replace'), flush=True)
    if attachments.exists():
        # Full exported screenshots/AX/manifest stay in the independent artifact.
        # Console mirrors screenshots and metadata too, independent of artifact DNS.
        for p in sorted(attachments.rglob('*')):
            if p.is_file() and p.suffix.lower() in ['.png', '.jpg', '.jpeg', '.json', '.txt']:
                emit(p, str(p.relative_to(output)).replace(' ', '_'))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--log', type=Path, required=True)
    parser.add_argument('--result', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    retain(args.log, args.result, args.output)
