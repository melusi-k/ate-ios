"""Exact inverse for the independently bounded Dogfood groups only."""
from pathlib import Path
import hashlib,json
FIXTURE_SHA='6adae6a6280759640f03ef074e19cac2c4ef1bbe6c238b7fc95ea4936d0e1ceb'
def restore(path,raw):
    payload=Path(__file__).with_name('dogfood_independent_lane_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest()==FIXTURE_SHA
    path=path.split(':',1)[-1]
    c=json.loads(payload).get(path)
    if c is None:return raw
    binary=isinstance(raw,bytes);text=raw.decode() if binary else raw
    if hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']:return raw
    assert hashlib.sha256(text.encode()).hexdigest()==c['current_sha'],'unrelated Dogfood group split delta: '+path
    for f in c['fragments']:
        assert text.count(f['new'])==1
        text=text.replace(f['new'],f['old'],1)
    assert hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']
    return text.encode() if binary else text
