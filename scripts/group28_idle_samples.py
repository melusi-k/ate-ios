#!/usr/bin/env python3
"""Bounded Group28 idle evidence. Child status, selection and output stay native."""
import argparse
import json
from pathlib import Path
import re
import signal
import subprocess
import threading
import time

PHASES = ('browse', 'submenu')
MARK = re.compile(r'^STARTUP-TEST phase=(browse|submenu)-tap-(start|end) uptime=([0-9.]+)$')

class PhaseWatch:
    def __init__(self):
        self.active = False
        self.seen = set()
        self.open = {}
        self.sampled = set()

    def line(self, line):
        if "Test Case '-[AteUITests.AteUITests test28_GroupSortAndMenus]' started." in line:
            self.active = True
        if not self.active:
            return
        m = MARK.match(line.strip())
        if m:
            phase, edge, uptime = m.groups()
            if edge == 'start' and phase not in self.seen:
                self.seen.add(phase)
                self.open[phase] = float(uptime)
            elif edge == 'end':
                self.open.pop(phase, None)
        if "Test Case '-[AteUITests.AteUITests test28_GroupSortAndMenus]'" in line and any(x in line for x in (' passed ', ' failed ', 'exceeded execution')):
            self.active = False
            self.open.clear()

    def due(self, now):
        # A stale buffered phase never causes a later process to be sampled.
        for phase, started in list(self.open.items()):
            if phase not in self.sampled and 10 <= now - started <= 30:
                self.sampled.add(phase)
                yield phase


def targets(ps, simulator):
    found = {}
    for line in ps.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) != 2 or not parts[0].isdigit():
            continue
        pid, command = parts
        if f'/Devices/{simulator}/' not in command:
            continue
        for name, suffix in [('app', '/Ate.app/Ate'), ('runner', '/AteUITests-Runner.app/AteUITests-Runner')]:
            if command.endswith(suffix):
                found.setdefault(name, []).append(int(pid))
    return found


def capture(phase, simulator, output, stop):
    events = []
    try:
        ps = subprocess.run(['/bin/ps', '-axo', 'pid=,command='], capture_output=True, text=True, timeout=3, check=True)
        found = targets(ps.stdout, simulator)
        for name in ('app', 'runner'):
            pids = found.get(name, [])
            if len(pids) != 1:
                events.append({'phase': phase, 'target': name, 'status': 'missing-or-ambiguous-pid', 'pids': pids})
                continue
            if stop.is_set():
                events.append({'phase': phase, 'target': name, 'status': 'child-ended-before-sample'})
                continue
            path = output / f'{phase}-{name}.sample.txt'
            with (output / f'{phase}-{name}.stderr.txt').open('w') as err:
                result = subprocess.run(['/usr/bin/sample', str(pids[0]), '3', '-file', str(path)], stdout=err, stderr=subprocess.STDOUT, timeout=6)
            events.append({'phase': phase, 'target': name, 'pid': pids[0], 'status': 'sample-returned', 'returncode': result.returncode, 'uptime': time.monotonic()})
    except Exception as error:
        events.append({'phase': phase, 'status': 'capture-error', 'error': str(error)})
    return events


def observe(log, simulator, output, stop):
    output.mkdir(parents=True, exist_ok=True)
    watch = PhaseWatch()
    offset = 0
    pending = ''
    events = []
    try:
        while not stop.is_set():
            if log.exists():
                with log.open(errors='replace') as stream:
                    stream.seek(offset)
                    pending += stream.read()
                    offset = stream.tell()
                lines = pending.split('\n')
                pending = lines.pop()
                for line in lines:
                    watch.line(line)
                for phase in watch.due(time.monotonic()):
                    events.extend(capture(phase, simulator, output, stop))
            stop.wait(0.25)
    except Exception as error:
        events.append({'status': 'watch-error', 'error': str(error)})
    finally:
        (output / 'receipt.json').write_text(json.dumps({'diagnostic_only': True, 'sampled_phases': sorted(watch.sampled), 'events': events, 'finished_uptime': time.monotonic()}, indent=2) + '\n')


def main(observer=observe):
    parser = argparse.ArgumentParser()
    parser.add_argument('--log', required=True, type=Path)
    parser.add_argument('--simulator', required=True)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command:
        parser.error('native command required')
    stop = threading.Event()
    watcher = threading.Thread(target=observer, args=(args.log, args.simulator, args.output, stop))
    watcher.start()
    child = None
    def interrupted(signum, _frame):
        stop.set()
        if child is not None and child.poll() is None:
            child.send_signal(signum)
    previous = {sig: signal.signal(sig, interrupted) for sig in (signal.SIGTERM, signal.SIGINT)}
    try:
        child = subprocess.Popen(command)
        result = child.wait()
    finally:
        stop.set()
        watcher.join()  # No detached watcher or sampler survives normal child completion.
    for sig, handler in previous.items():
        signal.signal(sig, handler)
    return result if result >= 0 else 128 - result

if __name__ == '__main__':
    raise SystemExit(main())
