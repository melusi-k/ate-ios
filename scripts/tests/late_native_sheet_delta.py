"""Exact late native sheet monitor inverse. Historical contracts remain unchanged."""
from pathlib import Path
import hashlib,json
FIXTURE=Path(__file__).with_suffix('.json')
DIGEST='ba5aa4eba217b537f9c45dff6e1a64cca65b954a9794e958b9eb674335126664'
def restore(key,raw):
    payload=FIXTURE.read_bytes()
    assert hashlib.sha256(payload).hexdigest()==DIGEST, 'Password prompt fixture changed'
    item=json.loads(payload).get(key.split(':',1)[-1])
    if not item:return raw
    binary=isinstance(raw,bytes)
    text=raw.decode() if binary else raw
    if hashlib.sha256(text.encode()).hexdigest()in (item['base'],item['prior_inverse_base']):return raw
    assert hashlib.sha256(text.encode()).hexdigest()==item['patched'], 'Unreviewed password prompt change: '+key
    assert text==item['new']
    return item['old'].encode() if binary else item['old']
