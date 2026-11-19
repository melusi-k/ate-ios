#!/usr/bin/env python3
"""Bounded CI-host observations, not a timeout, performance gate or OCR retry.

No process arguments, source images, OCR text or environment values are collected.
CPU counters belong to OS processes, not individual Vision requests. Service start
means OS process start / first observed, never model initialization or request start.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import signal
import subprocess
import threading
import time

PS_COMMAND = ['/bin/ps', '-A', '-o', 'pid=,ppid=,time=,etime=,lstart=,comm=']
INTERVAL = 2.0
MAX_SECONDS = 45 * 60


def duration_seconds(value):
    """macOS ps TIME/ETIME: [[days-]hh:]mm:ss[.fraction]."""
    days, sep, clock = value.partition('-')
    if not sep:
        clock, days = days, '0'
    fields = clock.split(':')
    if len(fields) not in (2, 3):
        raise ValueError('unknown ps duration')
    values = [float(part) for part in fields]
    seconds = values[-1] + 60 * values[-2]
    if len(values) == 3:
        seconds += 3600 * values[0]
    return int(days) * 86400 + seconds


def category(name):
    lower = name.lower()
    if name in ('Ate', 'AteTests', 'AteTests-Runner'):
        return 'app'
    if any(word in lower for word in ('vision', 'textrecognition', 'imageanalysis')):
        return 'vision_related'
    return None


def parse_processes(text):
    result = []
    for line in text.splitlines():
        parts = line.split(None, 9)
        if len(parts) != 10:
            continue
        pid, ppid, cpu, elapsed = parts[:4]
        # Retain only executable basename, not full paths or command arguments.
        name = parts[9].rsplit('/', 1)[-1]
        kind = category(name)
        if kind is None:
            continue
        try:
            result.append({'pid': int(pid), 'ppid': int(ppid), 'name': name,
                           'category': kind, 'cpu_seconds': duration_seconds(cpu),
                           'elapsed_seconds': duration_seconds(elapsed),
                           'os_start_local': ' '.join(parts[4:9])})
        except ValueError:
            continue
    return result


def sample(previous, now, started, run=subprocess.run, load=os.getloadavg):
    row = {'kind': 'sample', 'utc': datetime.now(timezone.utc).isoformat(),
           'monotonic_seconds': now, 'collector_wall_seconds': now - started}
    try:
        row['load_average_1_5_15'] = list(load())
    except OSError:
        row['load_error'] = 'unavailable'
    try:
        proc = run(PS_COMMAND, capture_output=True, text=True, timeout=2, check=True,
                   env={'PATH': '/usr/bin:/bin', 'LC_ALL': 'C'})
        processes = parse_processes(proc.stdout)
        current = {}
        for item in processes:
            key = (item['pid'], item['os_start_local'])
            old = previous.get(key)
            item['first_observed'] = old is None
            if old is not None:
                wall = now - old['monotonic']
                cpu = item['cpu_seconds'] - old['cpu_seconds']
                item['sample_wall_seconds'] = wall
                if wall > 0 and cpu >= 0:
                    item['cpu_delta_seconds'] = cpu
                    item['cpu_percent_of_one_core'] = 100 * cpu / wall
            current[key] = {'monotonic': now, 'cpu_seconds': item['cpu_seconds']}
        row['processes'] = processes
        row['vision_related_visible'] = any(p['category'] == 'vision_related' for p in processes)
        return row, current
    except (OSError, subprocess.SubprocessError):
        # Never serialize stderr, commands or arbitrary exception text.
        row['process_error'] = 'ps unavailable, failed or exceeded 2 seconds'
        return row, previous


def collect(output, max_seconds=MAX_SECONDS, interval=INTERVAL):
    stop = threading.Event()
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    started = time.monotonic()
    previous = {}
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open('w', encoding='utf-8', buffering=1) as stream:
        def emit(value):
            stream.write(json.dumps(value, sort_keys=True) + '\n')
        emit({'kind': 'header', 'utc': datetime.now(timezone.utc).isoformat(),
              'cpu_count': os.cpu_count(), 'local_timezone': time.tzname,
              'local_utc_offset_seconds': -time.timezone,
              'interval_seconds': interval, 'max_seconds': max_seconds,
              'limits': 'Host load is not CPU utilization. Process CPU is not request CPU. '
                        'Service visibility/name matching is best effort. First observed is not startup. '
                        'OS start is not Vision model initialization. No OCR inputs or process arguments.'})
        while not stop.is_set() and time.monotonic() - started < max_seconds:
            now = time.monotonic()
            row, previous = sample(previous, now, started)
            emit(row)
            stop.wait(interval)
        emit({'kind': 'end', 'utc': datetime.now(timezone.utc).isoformat(),
              'collector_wall_seconds': time.monotonic() - started,
              'reason': 'signal' if stop.is_set() else 'bounded duration'})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    collect(args.output)


if __name__ == '__main__':
    main()
