"""Exact fixed-stage diagnostic inverse; no alternate execution paths accepted."""
from pathlib import Path
import hashlib,json
FIXTURE=Path(__file__).with_suffix('.json')
DIGEST='6a5d7ea1795ae82a3634a4abd2355b475a212911968d8c901a32116ffe4d7e0d'

def restore(key,raw):
    from account_simulator_signing_delta import restore as restore_signing
    raw=restore_signing(key,raw)
    payload=FIXTURE.read_bytes()
    assert hashlib.sha256(payload).hexdigest()==DIGEST
    item=json.loads(payload).get('source:'+key.split(':',1)[-1])
    if not item:return raw
    binary=isinstance(raw,bytes)
    text=raw.decode() if binary else raw
    digest=hashlib.sha256(text.encode()).hexdigest()
    if digest==item['base']:return raw
    assert digest==item['patched'], 'Unreviewed cleanup phase change: '+key
    for fragment in reversed(item['fragments']):
        assert text.count(fragment['new'])==1
        text=text.replace(fragment['new'],fragment['old'],1)
    assert hashlib.sha256(text.encode()).hexdigest()==item['base']
    return text.encode() if binary else text
