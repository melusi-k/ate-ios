"""Exact inverse for scoped test seams; rejects any unreviewed edits."""
import hashlib,json
from pathlib import Path
FIXTURE = Path(__file__).with_name('journal_reset_test_seams_delta.json')
DIGEST = 'd947e4f83340192dacfe69cdb461b7601e089c6543cdb733ae27a447c18ff1cd'
def restore(key, raw):
    payload = FIXTURE.read_bytes()
    assert hashlib.sha256(payload).hexdigest() == DIGEST
    item = json.loads(payload).get(key)
    if not item: return raw
    binary = isinstance(raw, bytes)
    text = raw.decode() if binary else raw
    actual = hashlib.sha256(text.encode()).hexdigest()
    if actual == item['base']: return raw
    assert actual == item['patched'], 'Unreviewed test seam change: ' + key
    for fragment in item['fragments']:
        assert text.count(fragment['new']) == 1
        text = text.replace(fragment['new'], fragment['old'], 1)
    assert hashlib.sha256(text.encode()).hexdigest() == item['base']
    return text.encode() if binary else text
