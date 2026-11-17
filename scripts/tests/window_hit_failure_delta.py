"""Exact diagnostic-only inverse. Unknown historical bytes are passed to older strict guards."""
from pathlib import Path
import hashlib,json
FIXTURE=Path(__file__).with_suffix('.json')
DIGEST='05dbcf4e66fe8a827963a0da380d8f419e0a83b9e52158ec156423543751beee'
def restore(key,raw):
    payload=FIXTURE.read_bytes()
    assert hashlib.sha256(payload).hexdigest()==DIGEST, 'Window probe fixture changed'
    item=json.loads(payload).get(key.split(':',1)[-1])
    if not item:return raw
    binary=isinstance(raw,bytes)
    text=raw.decode() if binary else raw
    if hashlib.sha256(text.encode()).hexdigest()==item['new_sha']:
        assert text==item['new']
        return item['old'].encode() if binary else item['old']
    # Reject partial/tampered diagnostics, preserve all earlier strict inverses.
    assert 'WindowHitFailure' not in text and 'window-hit-failures' not in text, 'Unreviewed window probe change: '+key
    return raw
