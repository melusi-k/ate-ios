"""Reverse only the timer-alerts relay non-blocking delta before historical source pins."""
from pathlib import Path
import hashlib
import json
FIXTURE_SHA = 'fe1b4b60977fd98f102e6941b9a58af1d08e0d75bc5bf50e1baa5f2fed13bc0e'

def contract():
    payload = Path(__file__).with_name('timer_alerts_relay_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest() == FIXTURE_SHA
    return json.loads(payload)

def restore(path, source):
    c = contract()['files']
    if path not in c:
        return source
    entry = c[path]
    binary = isinstance(source, bytes)
    text = source.decode() if binary else source
    digest = hashlib.sha256(text.encode()).hexdigest()
    if digest == entry['parent_sha256']:
        return source
    assert digest == entry['current_sha256'], 'unrelated timer-alerts relay delta: ' + path
    for fragment in reversed(entry['fragments']):
        assert text.count(fragment['new']) == 1
        text = text.replace(fragment['new'], fragment['old'], 1)
    assert hashlib.sha256(text.encode()).hexdigest() == entry['parent_sha256']
    return text.encode() if binary else text
