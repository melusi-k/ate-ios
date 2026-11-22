"""Exact cancel journey inverse before historical Today-tab pins."""
from pathlib import Path
import hashlib
import json
FIXTURE_SHA = '393cd0c3d17ab1579603f6c4c21b011d1a850a439e9246ad8fa00579710d7fba'
def restore(key, raw):
    if key.split(':', 1)[-1] != 'AteUITests/CookPlanUITests.swift':
        return raw
    payload = Path(__file__).with_name('cookplan_cancel_journey_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest() == FIXTURE_SHA
    c = json.loads(payload)
    binary = isinstance(raw, bytes)
    text = raw.decode() if binary else raw
    if hashlib.sha256(text.encode()).hexdigest() == c['parent_sha256']:
        return raw
    assert hashlib.sha256(text.encode()).hexdigest() == c['current_sha256']
    assert text.count(c['new']) == 1
    text = text.replace(c['new'], c['old'], 1)
    assert hashlib.sha256(text.encode()).hexdigest() == c['parent_sha256']
    return text.encode() if binary else text
