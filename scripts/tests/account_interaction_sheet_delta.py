"""Exact account interaction sheet candidate inverse; historical contracts retained."""
from pathlib import Path
import hashlib,json
FIXTURE=Path(__file__).with_suffix('.json')
DIGEST='f8f84a03cf495081b209da8e803bec69def4b01bec773cd43f80f9d353268e4c'
def restore(key,raw):
    payload=FIXTURE.read_bytes()
    assert hashlib.sha256(payload).hexdigest()==DIGEST, 'Account interaction sheet fixture changed'
    item=json.loads(payload).get(key.split(':',1)[-1])
    if not item:return raw
    binary=isinstance(raw,bytes)
    text=raw.decode() if binary else raw
    if hashlib.sha256(text.encode()).hexdigest() in item['historical_bases']:return raw
    assert hashlib.sha256(text.encode()).hexdigest()==item['patched'], 'Unreviewed account interaction sheet change: '+key
    assert text==item['new']
    return item['old'].encode() if binary else item['old']
