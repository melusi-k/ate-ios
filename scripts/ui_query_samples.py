#!/usr/bin/env python3
"""At most one live app sample per explicitly marked UI query boundary."""
import json
from pathlib import Path
import re
import subprocess
import time
from group28_idle_samples import main

MARK = re.compile(r'^UI-QUERY-DIAGNOSTIC boundary=(tracker-returned-month|cook-add-title|cook-plan-cancel) edge=(begin|end) monotonic_ns=([0-9]+)$')

class QueryWatch:
    def __init__(self):
        self.open = {}
        self.sampled = set()

    def line(self, line):
        if "Test Case '-[AteUITests.CookPlanUITests testSavedRecipePlanWithoutReminderCanBeReopenedAndCancelled]'" in line and any(x in line for x in (' passed ', ' failed ', 'exceeded execution')):
            self.open.pop('cook-plan-cancel', None)
        match = MARK.fullmatch(line.strip())
        if match:
            name, edge, nanos = match.groups()
            if edge == 'begin':
                self.open[name] = int(nanos) / 1e9
            else:
                self.open.pop(name, None)

    def due(self, now):
        for name, started in list(self.open.items()):
            if name not in self.sampled and 10 <= now - started <= 30:
                self.sampled.add(name)
                yield name


def app_pid(ps, services):
    # launchctl is scoped to the requested simulator, not the host or another sim.
    bound = []
    for line in services.splitlines():
        parts = line.split()
        if len(parts) == 3 and parts[0].isdigit() and parts[2].startswith('UIKitApplication:com.melusik.ate['):
            bound.append(int(parts[0]))
    commands = {}
    for line in ps.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) == 2 and parts[0].isdigit():
            commands[int(parts[0])] = parts[1]
    if len(bound) != 1 or not commands.get(bound[0], '').endswith('/Ate.app/Ate'):
        return None
    return bound[0]


def capture(name, simulator, output, stop, is_open=lambda: True):
    output.mkdir(parents=True, exist_ok=True)
    event = {'boundary': name, 'started_uptime': time.monotonic()}
    def run(label, command, timeout):
        with (output / f'{name}-{label}.stdout.txt').open('w') as out, (output / f'{name}-{label}.stderr.txt').open('w') as err:
            return subprocess.run(command, stdout=out, stderr=err, timeout=timeout).returncode
    try:
        event['ps_returncode'] = run('processes', ['/bin/ps', '-axo', 'pid=,comm='], 3)
        event['launchctl_returncode'] = run('services', ['xcrun', 'simctl', 'spawn', simulator, 'launchctl', 'list'], 3)
        if event['ps_returncode'] or event['launchctl_returncode']:
            return dict(event, status='process-metadata-failed')
        pid = app_pid((output / f'{name}-processes.stdout.txt').read_text(), (output / f'{name}-services.stdout.txt').read_text())
        if pid is None:
            return dict(event, status='missing-ambiguous-or-unverified-app-pid')
        event['pid'] = pid
        if stop.is_set():
            return dict(event, status='child-ended-before-sample')
        if not is_open():
            return dict(event, status='boundary-closed-or-stale-before-sample')
        event['sample_returncode'] = run('sample', ['/usr/bin/sample', str(pid), '1', '-file', str(output / f'{name}.sample.txt')], 3)
        return dict(event, status='sample-returned', boundary_open_after_sample=is_open(), finished_uptime=time.monotonic())
    except Exception as error:
        return dict(event, status='capture-error', error=str(error), finished_uptime=time.monotonic())


def observe(log, simulator, output, stop):
    output.mkdir(parents=True, exist_ok=True)
    watch = QueryWatch()
    offset, pending = 0, ''
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
                for name in watch.due(time.monotonic()):
                    started = watch.open[name]
                    def is_open():
                        current = QueryWatch()
                        for line in log.read_text(errors='replace').splitlines():
                            current.line(line)
                        return current.open.get(name) == started and 10 <= time.monotonic() - started <= 30
                    events.append(capture(name, simulator, output, stop, is_open))
            stop.wait(0.1)
    except Exception as error:
        events.append({'status': 'watch-error', 'error': str(error)})
    finally:
        (output / 'receipt.json').write_text(json.dumps({'diagnostic_only': True, 'sampled_boundaries': sorted(watch.sampled), 'open_boundaries_at_end': watch.open, 'events': events, 'finished_uptime': time.monotonic()}, indent=2) + '\n')

if __name__ == '__main__':
    raise SystemExit(main(observer=observe))
