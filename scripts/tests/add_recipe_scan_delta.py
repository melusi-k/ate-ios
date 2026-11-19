"""Exact #613 inverse; preserves historical guard hashes and base bytes."""
import hashlib
import json
from pathlib import Path
FIXTURE_SHA = '33f8c536d32f2f8c7a73ee898b1cb5cd8c0c0f7e2713256db22ee89f57065810'

def restore(key, raw):
    path = key.split(':', 1)[-1]
    if path not in ['Ate/Views/AddRecipeSheet.swift', '.github/workflows/compile-check.yml']:
        return raw
    payload = Path(__file__).with_name('add_recipe_scan_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest() == FIXTURE_SHA, 'Add review inverse fixture changed'
    contract = json.loads(payload)[path]
    binary = isinstance(raw, bytes)
    text = raw.decode() if binary else raw
    for fragment in contract['fragments']:
        new, old = fragment['slice'], fragment['parent']
        assert text.count(new) == 1, 'Add review fragment absent, changed or duplicated'
        text = text.replace(new, old, 1)
    assert hashlib.sha256(text.encode()).hexdigest() == contract['parent_sha'], 'Add review parent bytes changed'
    return text.encode() if binary else text
