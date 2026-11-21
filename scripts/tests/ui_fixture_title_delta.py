from pathlib import Path
import json,hashlib
FIXTURE_SHA='471c1fd77148443feab4d32914dcb4f0093c04fdf0232a52ca90c6128fe26ed2'
def restore(path,raw):
    payload=Path(__file__).with_name('ui_fixture_title_inverse.json').read_bytes()
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
