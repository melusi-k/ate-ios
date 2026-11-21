"""Restore only four transparent event-origin checkout refs before frozen guards."""
from pathlib import Path
import hashlib,json
FIXTURE_SHA='211e9acff8ef9ce573f38f2bda7330c0e8be3d4561d070042aefdb8e05c760a7'
def restore(path,raw):
    if path.split(':',1)[-1]!='.github/workflows/dogfood-qualification.yml':return raw
    payload=Path(__file__).with_name('dogfood_checkout_provenance_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest()==FIXTURE_SHA
    c=json.loads(payload);binary=isinstance(raw,bytes);text=raw.decode() if binary else raw
    if hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']:return raw
    assert hashlib.sha256(text.encode()).hexdigest()==c['current_sha'],'unrelated checkout provenance delta'
    assert text.count(c['new'])==c['count']
    text=text.replace(c['new'],c['old'])
    assert hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']
    return text.encode() if binary else text
