"""Exact native accessibility repair inverse, before the unchanged #612 inverse."""
import hashlib
import json
from pathlib import Path

FIXTURE_SHA = '7b61df3ed904988b8423c4291acda849f89d2af34f9bbcea8b9ec774215d61aa'

def restore(key, raw):
    if key.split(':', 1)[-1] != 'Ate/Views/LibraryView.swift':
        return raw
    payload = Path(__file__).with_name('library_selection_accessibility_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest() == FIXTURE_SHA, 'accessibility inverse changed'
    contract = json.loads(payload)
    binary = isinstance(raw, bytes)
    text = raw.decode() if binary else raw
    assert text.count(contract['new']) == 1, 'accessibility repair absent, changed or duplicated'
    text = text.replace(contract['new'], contract['old'], 1)
    assert hashlib.sha256(text.encode()).hexdigest() == contract['parent_sha'], 'Library source outside repair changed'
    return text.encode() if binary else text
