"""Exact diagnostic inverse before existing source/workflow pins."""
from pathlib import Path
import hashlib
import json
FIXTURE_SHA = '01131abe077872592d415aefb9917d7159f252b0c9a8d03df5417f8befd32908'
def restore(key, raw):
    from cookplan_cancel_phase_delta import restore as restore_cancel_phases
    raw = restore_cancel_phases(key, raw)
    path = key.split(':', 1)[-1]
    payload = Path(__file__).with_name('live_query_capture_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest() == FIXTURE_SHA
    c = json.loads(payload).get(path)
    if c is None:
        return raw
    binary = isinstance(raw, bytes)
    text = raw.decode() if binary else raw
    if hashlib.sha256(text.encode()).hexdigest() == c['parent_sha256']:
        return raw
    assert hashlib.sha256(text.encode()).hexdigest() == c['current_sha256'], 'unrelated live query delta: ' + path
    for f in reversed(c['fragments']):
        assert text.count(f['new']) == 1
        text = text.replace(f['new'], f['old'], 1)
    assert hashlib.sha256(text.encode()).hexdigest() == c['parent_sha256']
    return text.encode() if binary else text
