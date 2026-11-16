#!/usr/bin/env python3
"""One bounded stack capture after the original Tracker month AX query is slow.

Never calls UI automation, retries an action, or affects test exit status.
Private CI diagnostic: stacks/process names only, no app files or environment.
"""
import argparse
from pathlib import Path
import subprocess
import time

TEST = 'testMonthNavigationAndFutureMonthRestriction'
QUERY = 'Checking `Expect predicate `label != '

def capture(output, simulator):
    output.mkdir(parents=True, exist_ok=True)
    try:
        result = subprocess.run(['xcrun', 'simctl', 'spawn', simulator, 'launchctl', 'list'], capture_output=True, text=True, timeout=5)
        candidates = []
        for line in result.stdout.splitlines():
            parts = line.split()
            if len(parts) < 3 or not parts[0].isdigit(): continue
            pid, label = parts[0], parts[-1]
            if 'com.melusik.ate' in label and 'xctrunner' not in label.lower():
                candidates.insert(0, (pid, 'Ate'))
            elif label in {'com.apple.accessibilityd', 'com.apple.AccessibilityUIServer', 'com.apple.AXUIService'}:
                candidates.append((pid, label.rsplit('.', 1)[-1]))
        (output/'capture.txt').write_text('One capture; 3s per process; at most 3 processes.\n' + '\n'.join(f'{p} {n}' for p,n in candidates[:3]))
        for pid, name in candidates[:3]:
            try:
                r = subprocess.run(['sample', pid, '3', '-file', str(output/f'{name}-{pid}.sample.txt')], capture_output=True, text=True, timeout=8)
                (output/f'{name}-{pid}.status.txt').write_text(f'exit={r.returncode}\n{r.stderr}')
            except (OSError, subprocess.TimeoutExpired) as error:
                (output/f'{name}-{pid}.status.txt').write_text(type(error).__name__)
    except (OSError, subprocess.TimeoutExpired) as error:
        (output/'capture.txt').write_text(type(error).__name__)

def monitor(log, output, simulator, stop, slow_seconds=5, watch_seconds=900):
    start=time.monotonic(); query_at=None
    while time.monotonic()-start < watch_seconds and not stop.exists():
        if log.exists():
            text=log.read_text(errors='replace')
            index=text.find(TEST+']\' started.')
            if index >= 0:
                tail=text[index:]
                if QUERY in tail:
                    after=tail.split(QUERY,1)[1]
                    # Stop without sampling once another XCTest statement follows this Find.
                    lines=[line for line in after.splitlines()[1:] if 't =' in line]
                    if any('Find the "tracker.displayedMonth"' not in line for line in lines): return
                    if query_at is None: query_at=time.monotonic()
                    if time.monotonic()-query_at >= slow_seconds:
                        capture(output, simulator); return
                if "' passed (" in tail or "' failed (" in tail: return
        time.sleep(1)

if __name__ == '__main__':
    p=argparse.ArgumentParser();p.add_argument('--log',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--simulator',required=True);p.add_argument('--stop',type=Path,required=True)
    a=p.parse_args();monitor(a.log,a.output,a.simulator,a.stop)
