"""Reverse only the zero-node absence query before existing historical pins."""
from pathlib import Path
import hashlib
import json
FIXTURE_SHA = '9edbfd45cce5748e6e70ff1be684a4485237555cf8c5efc8cccc30e76ea86b45'
def restore(key, raw):
    if key.split(':', 1)[-1] != 'AteUITests/JournalOpenStateUITests.swift':
        return raw
    payload = Path(__file__).with_name('journal_delete_zero_nodes_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest() == FIXTURE_SHA
    c = json.loads(payload)
    binary = isinstance(raw, bytes)
    text = raw.decode() if binary else raw
    digest = hashlib.sha256(text.encode()).hexdigest()
    if digest == c['parent_sha256']:
        return raw
    assert digest == c['current_sha256'], 'unrelated zero-node query delta'
    assert text.count(c['new']) == 1
    text = text.replace(c['new'], c['old'], 1)
    assert hashlib.sha256(text.encode()).hexdigest() == c['parent_sha256']
    return text.encode() if binary else text
