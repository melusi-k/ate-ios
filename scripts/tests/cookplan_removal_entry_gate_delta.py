"""Exact deterministic entry-gate inverse before unchanged historical guards."""
from pathlib import Path
import hashlib
import json
FIXTURE_SHA = '0835636e393f6c9282e24604424b68584c1bf27c694e981e34e521f8655a55fe'
def restore(key, raw):
    path = key.split(':', 1)[-1]
    payload = Path(__file__).with_name('cookplan_removal_entry_gate_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest() == FIXTURE_SHA
    c = json.loads(payload).get(path)
    if c is None:
        return raw
    binary = isinstance(raw, bytes)
    text = raw.decode() if binary else raw
    if hashlib.sha256(text.encode()).hexdigest() in [c['parent_sha256']] + c.get('ancestor_sha256', []):
        return raw
    assert hashlib.sha256(text.encode()).hexdigest() == c['current_sha256'], 'unrelated entry gate delta: ' + path
    for f in reversed(c['fragments']):
        assert text.count(f['new']) == 1
        text = text.replace(f['new'], f['old'], 1)
    assert hashlib.sha256(text.encode()).hexdigest() == c['parent_sha256']
    return text.encode() if binary else text
