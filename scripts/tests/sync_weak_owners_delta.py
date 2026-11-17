"""Exact weak-owner diagnostic inverse; all historical contracts stay pinned."""
from pathlib import Path
import hashlib,json
FIXTURE=Path(__file__).with_suffix('.json')
DIGEST='d9b2c429e1f4a93a2215423d8dc58f46bd79dc0e541199f53d502e562e84d225'

def restore(key,raw):
    path=key.split(':',1)[-1]
    if path not in ('Ate/Store/JournalSyncBridge.swift','AteTests/UserDataSyncTests.swift'): return raw
    payload=FIXTURE.read_bytes()
    assert hashlib.sha256(payload).hexdigest()==DIGEST, 'Weak-owner fixture changed'
    item=json.loads(payload)[path]
    binary=isinstance(raw,bytes)
    text=raw.decode() if binary else raw
    digest=hashlib.sha256(text.encode()).hexdigest()
    if digest==item['base_sha256']: return raw
    assert digest==item['patched_sha256'], 'Unreviewed weak-owner delta: '+key
    for fragment in reversed(item['fragments']):
        assert text.count(fragment['new'])==1, 'Weak-owner fragment absent/changed/duplicated'
        text=text.replace(fragment['new'],fragment['old'],1)
    assert hashlib.sha256(text.encode()).hexdigest()==item['base_sha256']
    return text.encode() if binary else text
