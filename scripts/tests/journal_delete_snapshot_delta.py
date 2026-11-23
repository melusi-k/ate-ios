"""Reverse only the snapshot traversal delta before historical source pins."""
from pathlib import Path
import hashlib
import json
from canonical_goals_property_wait_delta import restore as restore_goals
FIXTURE_SHA = 'ec5d2a9b48cacfbdc27348462aa3d7f73e15f9e92b21db7c45eab227355d4c24'

def contract():
    payload = Path(__file__).with_name('journal_delete_snapshot_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest() == FIXTURE_SHA
    return json.loads(payload)

def restore(key, raw):
    raw = restore_goals(key, raw)
    path = key.split(':', 1)[-1]
    c = contract()
    if path not in c['files']:
        return raw
    binary = isinstance(raw, bytes)
    text = raw.decode() if binary else raw
    digest = hashlib.sha256(text.encode()).hexdigest()
    entry = c['files'][path]
    if digest == entry['parent_sha256'] or (path == 'AteUITests/JournalOpenStateUITests.swift' and digest in c['legacy_journal_sha256']):
        return raw
    assert digest == entry['current_sha256'], 'unrelated snapshot delta: ' + path
    for fragment in reversed(entry['fragments']):
        assert text.count(fragment['new']) == 1
        text = text.replace(fragment['new'], fragment['old'], 1)
    assert hashlib.sha256(text.encode()).hexdigest() == entry['parent_sha256']
    return text.encode() if binary else text
