"""Reverse only the reviewed same-cap property-wait observation delta."""
from pathlib import Path
import hashlib
import json
FIXTURE_SHA = '9dd75982752cad94f271ca696b3d9eed67f95deebc3f45905a5116ef63315080'

def contract():
    payload = Path(__file__).with_name('canonical_goals_property_wait_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest() == FIXTURE_SHA
    return json.loads(payload)

def restore(key, raw):
    path = key.split(':', 1)[-1]
    c = contract()
    if path not in c['files']:
        return raw
    binary = isinstance(raw, bytes)
    text = raw.decode() if binary else raw
    entry = c['files'][path]
    digest = hashlib.sha256(text.encode()).hexdigest()
    if digest == entry['parent_sha256']:
        return raw
    assert digest == entry['current_sha256'], 'unrelated property-wait delta: ' + path
    for fragment in reversed(entry['fragments']):
        assert text.count(fragment['new']) == 1
        text = text.replace(fragment['new'], fragment['old'], 1)
    assert hashlib.sha256(text.encode()).hexdigest() == entry['parent_sha256']
    return text.encode() if binary else text
