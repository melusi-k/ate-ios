"""Reverse only the snapshot traversal delta before historical source pins."""
from pathlib import Path
import hashlib
import json
FIXTURE_SHA = '60f57c499893d4ab60048aae61e64f60187c5d679c6e523ae269d2deeab4dd4e'

def contract():
    payload = Path(__file__).with_name('journal_delete_snapshot_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest() == FIXTURE_SHA
    return json.loads(payload)

def restore(key, raw):
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
