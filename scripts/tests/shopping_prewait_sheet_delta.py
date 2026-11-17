"""Exact Shopping pre-wait sheet dismissal inverse; no runtime effect."""
from pathlib import Path
import hashlib,json
FIXTURE=Path(__file__).with_suffix('.json')
DIGEST='bf7b2ea4784f8cdfbb8afe6aa096bcc18f7c3789506e0c41844e7c560fc24ac3'
def restore(key,raw):
    payload=FIXTURE.read_bytes()
    assert hashlib.sha256(payload).hexdigest()==DIGEST, 'Shopping prewait sheet fixture changed'
    item=json.loads(payload).get(key.split(':',1)[-1])
    if not item:return raw
    binary=isinstance(raw,bytes)
    text=raw.decode() if binary else raw
    digest=hashlib.sha256(text.encode()).hexdigest()
    if digest in item['historical_bases']:return raw
    assert digest==item['patched'], 'Unreviewed Shopping prewait sheet change: '+key
    assert text==item['new']
    return item['old'].encode() if binary else item['old']
