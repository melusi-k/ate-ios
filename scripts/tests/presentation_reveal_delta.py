"""Exact bounded-reveal efficiency inverse; historical source contracts unchanged."""
from pathlib import Path
import hashlib,json
FIXTURE=Path(__file__).with_suffix('.json')
DIGEST='0e58515da8256882e786db8f047d10017c3ec8f1b78abe1b9d1c800517c59736'
def restore(key,raw):
    payload=FIXTURE.read_bytes()
    assert hashlib.sha256(payload).hexdigest()==DIGEST, 'Presentation reveal fixture changed'
    item=json.loads(payload).get(key.split(':',1)[-1])
    if not item:return raw
    binary=isinstance(raw,bytes)
    text=raw.decode() if binary else raw
    digest=hashlib.sha256(text.encode()).hexdigest()
    if digest in (item['base'],item.get('prior_inverse_base')):return raw
    assert digest==item['patched'], 'Unreviewed presentation reveal change: '+key
    assert text==item['new']
    return item['old'].encode() if binary else item['old']
