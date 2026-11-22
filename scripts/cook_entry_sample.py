#!/usr/bin/env python3
"""Single diagnostic sample during the strict Cook removal-entry wait."""
import json
from pathlib import Path
import re
import subprocess
import time
from group28_idle_samples import main, targets

MARK = re.compile(r'^COOK-REMOVAL-PHASE phase=([a-z-]+) monotonic_ns=([0-9]+) main_thread=(true|false)$')

class EntryWatch:
    def __init__(self):
        self.active = False
        self.started = None
        self.sampled = False
        self.returned = False

    def line(self, line):
        if "Test Case '-[AteTests.CookPlanNotificationTests testBlockedSystemRemovalLeavesMainResponsiveAndDoesNotReturnEarly]' started." in line:
            self.active = True
        if not self.active:
            return
        mark = MARK.match(line.strip())
        if mark:
            phase, nanos, _ = mark.groups()
            if phase == 'before-entry-wait' and self.started is None:
                self.started = int(nanos) / 1e9
            if phase in ('entry-wait-return', 'test-completion'):
                self.returned = True
        if "Test Case '-[AteTests.CookPlanNotificationTests testBlockedSystemRemovalLeavesMainResponsiveAndDoesNotReturnEarly]'" in line and any(x in line for x in (' passed ', ' failed ', 'exceeded execution')):
            self.returned = True

    def due(self, now):
        if self.active and not self.returned and not self.sampled and self.started is not None and 0.25 <= now - self.started <= 1.25:
            self.sampled = True
            return True
        return False


def capture(simulator, output):
    event = {'uptime': time.monotonic()}
    try:
        ps = subprocess.run(['/bin/ps', '-axo', 'pid=,command='], capture_output=True, text=True, timeout=1, check=True)
        pids = targets(ps.stdout, simulator).get('app', [])
        if len(pids) != 1:
            return dict(event, status='missing-or-ambiguous-pid', pids=pids)
        event['pid'] = pids[0]
        with (output / 'entry.stderr.txt').open('w') as err:
            result = subprocess.run(['/usr/bin/sample', str(pids[0]), '1', '-file', str(output / 'entry.sample.txt')], stdout=err, stderr=subprocess.STDOUT, timeout=3)
        return dict(event, status='sample-returned', returncode=result.returncode)
    except Exception as error:
        return dict(event, status='capture-error', error=str(error))


def observe(log, simulator, output, stop):
    output.mkdir(parents=True, exist_ok=True)
    watch = EntryWatch()
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
                if watch.due(time.monotonic()):
                    events.append(capture(simulator, output))
            stop.wait(0.05)
    except Exception as error:
        events.append({'status': 'watch-error', 'error': str(error)})
    finally:
        (output / 'receipt.json').write_text(json.dumps({'diagnostic_only': True, 'sample_requested': watch.sampled, 'wait_return_seen': watch.returned, 'events': events, 'finished_uptime': time.monotonic()}, indent=2) + '\n')

if __name__ == '__main__':
    raise SystemExit(main(observer=observe))
