"""Reverse only the current-query boundary before unchanged historical pins."""
from pathlib import Path
import hashlib
import json
FIXTURE_SHA = 'f2a9acb2749da280fb7e1fe67f578734566a2bc764997239cff4a09e37200d73'
def restore(key, raw):
    if key.split(':', 1)[-1] != 'AteUITests/JournalOpenStateUITests.swift':
        return raw
    payload = Path(__file__).with_name('journal_delete_current_query_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest() == FIXTURE_SHA
    c = json.loads(payload)
    binary = isinstance(raw, bytes)
    text = raw.decode() if binary else raw
    digest = hashlib.sha256(text.encode()).hexdigest()
    if digest == c['parent_sha256']:
        return raw
    assert digest == c['current_sha256'], 'unrelated current-query delta'
    assert text.count(c['new']) == 1
    text = text.replace(c['new'], c['old'], 1)
    assert hashlib.sha256(text.encode()).hexdigest() == c['parent_sha256']
    return text.encode() if binary else text
