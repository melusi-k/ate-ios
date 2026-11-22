"""Reverse the exact Cook entry workflow wrapper before historical guards."""
from pathlib import Path
import hashlib
import json
FIXTURE_SHA = '9012e77dcf40c51fd362d968023b9a0073b571a7625bbf67b5e3ecfebd621ab5'
def restore(key, raw):
    from live_query_capture_delta import restore as restore_live_query
    raw = restore_live_query(key, raw)
    if key.split(':', 1)[-1] != '.github/workflows/compile-check.yml':
        return raw
    payload = Path(__file__).with_name('cook_entry_sample_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest() == FIXTURE_SHA
    c = json.loads(payload)['workflow']
    binary = isinstance(raw, bytes)
    text = raw.decode() if binary else raw
    if text == c['old']:
        return raw
    assert text == c['new'], 'unrelated Cook entry workflow delta'
    return c['old'].encode() if binary else c['old']
