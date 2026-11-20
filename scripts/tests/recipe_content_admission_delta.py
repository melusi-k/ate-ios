"""Exact content-admission descendant inverse to 8a11cfbc."""
from pathlib import Path
import json,hashlib
FIXTURE_SHA='99c49484ed044cb70d939bb24ec892762e0d9a26fd2842a379002d793c19d7f2'
def restore(path,raw):
    payload=Path(__file__).with_name('recipe_content_admission_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest()==FIXTURE_SHA
    c=json.loads(payload).get(path)
    if c is None:return raw
    binary=isinstance(raw,bytes);text=raw.decode() if binary else raw
    if hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']:return raw
    for f in c['fragments']:
        assert text.count(f['new'])==1,'changed content-admission fragment: '+path
        text=text.replace(f['new'],f['old'],1)
    assert hashlib.sha256(text.encode()).hexdigest()==c['parent_sha'],'unrelated content-admission delta: '+path
    return text.encode() if binary else text
