"""Exact branch-local inverse for inherited immutable-source assertions.

The fixture and its base digests are pinned by test_journal_personal_reset.py.
No Git checkout or network access is required by these contracts.
"""
import hashlib, json
from pathlib import Path
FIXTURE = Path(__file__).with_name('journal_personal_reset_delta.json')
FIXTURE_SHA256 = '33c75e0caa26e72777793323f419e2cc5afa3508378b0d1d51e0738454f8ce7d'
def restore(key, raw):
    from cleanup_phase_delta import restore as restore_cleanup
    raw=restore_cleanup(key,raw)
    binary = isinstance(raw, bytes)
    text = raw.decode() if binary else raw
    payload = FIXTURE.read_bytes()
    assert hashlib.sha256(payload).hexdigest() == FIXTURE_SHA256, 'Journal inverse fixture changed'
    item = json.loads(payload).get(key)
    if item:
        for fragment in item['inverse']:
            merged, base = fragment['new'], fragment['old']
            assert text.count(merged) == 1, 'Journal delta absent/changed/duplicated: ' + key
            text = text.replace(merged, base, 1)
        assert hashlib.sha256(text.encode()).hexdigest() == item['base_sha256'], 'Unreviewed Journal delta: ' + key
    return text.encode() if binary else text

def is_added(path, raw):
    from journal_reset_test_seams_delta import restore as restore_seams
    raw = restore_seams("source:" + path, raw)
    payload = FIXTURE.read_bytes()
    assert hashlib.sha256(payload).hexdigest() == FIXTURE_SHA256
    added = json.loads(payload).get('_added_files', {})
    if path not in added: return False
    assert hashlib.sha256(raw).hexdigest() == added[path], 'Journal added file changed: ' + path
    return True
