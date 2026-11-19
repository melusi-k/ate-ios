"""Exact #612 inverse before historic Library pins; no changed assertion hashes."""
import hashlib
import json
from pathlib import Path

FIXTURE_SHA = 'd186b9b94f568edcee6d83436a236ebd35490e286915a78e90777cb5379eba91'
PARENT_SHA = '14948188f9859bad9b02c5537ca5fb2faa9d61d29ffe3127c2437071551082ff'

def restore(key, raw):
    path = key.split(':', 1)[-1]
    if path not in ['Ate/Views/LibraryView.swift', '.github/workflows/compile-check.yml']:
        return raw
    payload = Path(__file__).with_name('library_selection_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest() == FIXTURE_SHA, 'selection inverse fixture changed'
    contract = json.loads(payload)[path]
    binary = isinstance(raw, bytes)
    text = raw.decode() if binary else raw
    for fragment in contract['fragments']:
        new, old = fragment['selected_fragment'], fragment['parent_fragment']
        assert text.count(new) == 1, 'selection fragment absent, changed or duplicated'
        text = text.replace(new, old, 1)
    assert hashlib.sha256(text.encode()).hexdigest() == contract['parent_sha'], 'selection parent bytes changed'
    return text.encode() if binary else text
