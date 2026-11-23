"""Reverse only the snapshot traversal delta before historical source pins."""
from pathlib import Path
import hashlib
import json
from canonical_goals_property_wait_delta import restore as restore_goals
FIXTURE_SHA = '1efaaa7f7530d24f3f7d82b3a1f875ed40cecf558db455ece8c087623a0f3e25'

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
