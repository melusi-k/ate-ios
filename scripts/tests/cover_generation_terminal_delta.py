"""Exact terminal-deadline and settled-fixture inverse before unchanged historical guards."""
from pathlib import Path
import hashlib
import json
FIXTURE_SHA = 'a6d03fd23626f216329d50446405142229572e2a585540cc82f19a7cc7decff6'
def restore(key, raw):
    path = key.split(':', 1)[-1]
    payload = Path(__file__).with_name('cover_generation_terminal_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest() == FIXTURE_SHA
    c = json.loads(payload).get(path)
    if c is None:
        return raw
    binary = isinstance(raw, bytes)
    text = raw.decode() if binary else raw
    if hashlib.sha256(text.encode()).hexdigest() in [c['parent_sha256']] + c.get('ancestor_sha256', []):
        return raw
    assert hashlib.sha256(text.encode()).hexdigest() == c['current_sha256'], 'unrelated terminal deadline delta: ' + path
    for f in reversed(c['fragments']):
        assert text.count(f['new']) == 1
        text = text.replace(f['new'], f['old'], 1)
    assert hashlib.sha256(text.encode()).hexdigest() == c['parent_sha256']
    return text.encode() if binary else text
