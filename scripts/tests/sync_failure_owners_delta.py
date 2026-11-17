"""Exact failure-time owner diagnostic inverse; all historical contracts stay pinned."""
from pathlib import Path
import hashlib,json
FIXTURE=Path(__file__).with_suffix('.json')
DIGEST='e8f2ee1c83d814ccfbbba5ae26e9adda30755fa9f86fc647d948229473edafd1'

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
