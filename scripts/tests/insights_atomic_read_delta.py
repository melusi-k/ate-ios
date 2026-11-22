"""Reverse the atomic test-fixture correction before historical diagnostic pins."""
from pathlib import Path
import hashlib
import json
FIXTURE_SHA = 'f01a6058bbfd01c46fb271f1c098070e42ed32d4142bb084a05c09cfb1c5fdbe'

def restore(source):
    payload = Path(__file__).with_name('insights_atomic_read_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest() == FIXTURE_SHA
    c = json.loads(payload)
    digest = hashlib.sha256(source.encode()).hexdigest()
    if digest == c['parent_sha256']:
        return source
    assert digest == c['current_sha256']
    for fragment in reversed(c['fragments']):
        assert source.count(fragment['new']) == 1
        source = source.replace(fragment['new'], fragment['old'], 1)
    assert hashlib.sha256(source.encode()).hexdigest() == c['parent_sha256']
    return source
