"""Exact #615 inverse; preserves historical guard hashes and base bytes."""
import hashlib
import json
from pathlib import Path
FIXTURE_SHA = '110e8fdc7fff4fc885ae86387ea6e8a675a045283bcdd917ca3c0d83248363c7'

def restore(key, raw):
    path = key.split(':', 1)[-1]
    if path not in ['Ate/Views/CookModeView.swift', '.github/workflows/compile-check.yml']:
        return raw
    payload = Path(__file__).with_name('stitch_cook_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest() == FIXTURE_SHA, 'Cook inverse fixture changed'
    contract = json.loads(payload)[path]
    binary = isinstance(raw, bytes)
    text = raw.decode() if binary else raw
    for fragment in contract['fragments']:
        new, old = fragment['slice'], fragment['parent']
        assert text.count(new) == 1, 'Cook fragment absent, changed or duplicated'
        text = text.replace(new, old, 1)
    assert hashlib.sha256(text.encode()).hexdigest() == contract['parent_sha'], 'Cook parent bytes changed'
    return text.encode() if binary else text
