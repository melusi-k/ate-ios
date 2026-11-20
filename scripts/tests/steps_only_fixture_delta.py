"""Product-contract native fixture correction, exact inverse to 764bd89a."""
from pathlib import Path
import json,hashlib
FIXTURE_SHA='ddde18a03047f4604153e0ecd2929e3b57de3f373e342a5f4aad7e26f256c968'
def restore(path,raw):
    payload=Path(__file__).with_name('steps_only_fixture_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest()==FIXTURE_SHA
    c=json.loads(payload).get(path)
    if c is None:return raw
    binary=isinstance(raw,bytes);text=raw.decode() if binary else raw
    if hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']:return raw
    for f in c['fragments']:
        assert text.count(f['new'])==1
        text=text.replace(f['new'],f['old'],1)
    assert hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']
    return text.encode() if binary else text
