"""Exact #614 inverse; preserves historical guard hashes and base bytes."""
import hashlib
import json
from pathlib import Path
FIXTURE_SHA = 'd8055621e214323bf15b7cd015cad57823204b1603ac27e4249c4d99a6517f92'

def restore(key, raw):
    path = key.split(':', 1)[-1]
    if path not in ['Ate/Views/RecipeDetailView.swift', 'Ate/Views/Components.swift', '.github/workflows/compile-check.yml']:
        return raw
    payload = Path(__file__).with_name('stitch_detail_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest() == FIXTURE_SHA, 'Detail inverse fixture changed'
    contract = json.loads(payload)[path]
    binary = isinstance(raw, bytes)
    text = raw.decode() if binary else raw
    for fragment in contract['fragments']:
        new, old = fragment['slice'], fragment['parent']
        assert text.count(new) == 1, 'Detail fragment absent, changed or duplicated'
        text = text.replace(new, old, 1)
    assert hashlib.sha256(text.encode()).hexdigest() == contract['parent_sha'], 'Detail parent bytes changed'
    return text.encode() if binary else text
