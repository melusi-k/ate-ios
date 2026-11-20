#!/usr/bin/env python3
"""Mirror native output losslessly to disk; stream named lifecycle evidence to Actions.

A heartbeat is an observation of elapsed wait, never a pass or a test timeout.
No process launch, test retry, filtering of the saved log, or qualification decision.
"""
import argparse
import os
import re
import select
import signal
import sys
import time


class Progress:
    pattern = re.compile(r"Test Case '(.*?)' (started|passed|failed)(?: \(([0-9.]+) seconds\))?")

    def __init__(self, selection, clock=time.monotonic, emit=print):
        self.selection = selection
        self.clock = clock
        self.emit = emit
        self.began = clock()
        self.active = None
        self.started = None
        self.last = 'none'

    def receipt(self, event):
        now = self.clock()
        elapsed = 'unobserved' if self.started is None else f'{now - self.started:.1f}'
        self.emit(f'UI-PROGRESS selection={self.selection} event={event} selection_elapsed_s={now - self.began:.1f} active={self.active or "none"} active_elapsed_s={elapsed} last={self.last}', flush=True)

    def line(self, text):
        match = self.pattern.search(text)
        if match:
            name, state, duration = match.groups()
            if state == 'started':
                self.active, self.started = name, self.clock()
            self.last = f'{name}:{state}'
            self.emit(text.rstrip('\r\n'), flush=True)
            self.receipt(state + (f' native_duration_s={duration}' if duration else ''))
            if state in ('passed', 'failed') and self.active == name:
                self.active, self.started = None, None
        elif 'UI-RED journey=' in text:
            self.emit(text.rstrip('\r\n'), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--selection', required=True)
    parser.add_argument('--log', required=True)
    args = parser.parse_args()
    progress = Progress(args.selection)
    # A cancellation signal may be delivered before stdin closes. Do not hide it.
    def interrupted(signum, _frame):
        progress.receipt(f'interrupted-signal-{signum}')
        raise SystemExit(128 + signum)
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    progress.receipt('stream-open-no-native-test-observed-yet')
    pending = b''
    last_heartbeat = time.monotonic()
    with open(args.log, 'wb', buffering=0) as output:
        while True:
            ready, _, _ = select.select([sys.stdin.fileno()], [], [], 1)
            if ready:
                chunk = os.read(sys.stdin.fileno(), 65536)
                if not chunk:
                    break
                output.write(chunk)
                pending += chunk
                while b'\n' in pending:
                    line, pending = pending.split(b'\n', 1)
                    progress.line(line.decode('utf-8', errors='replace'))
            if time.monotonic() - last_heartbeat >= 30:
                progress.receipt('heartbeat')
                last_heartbeat = time.monotonic()
        if pending:
            progress.line(pending.decode('utf-8', errors='replace'))
    progress.receipt('stream-closed-not-a-pass')


if __name__ == '__main__':
    main()
