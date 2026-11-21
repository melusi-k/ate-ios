"""Exact inverse for the native-reproduced sync overflow correction only."""
from pathlib import Path
import hashlib,json
FIXTURE_SHA='87e3d7f273ddc7097194150a36ca8b63d17159d854c6916fb5236b58b91cc654'
def restore(path,raw):
    if path=='Ate/Models/Models.swift' and 'The full saved-recipe collection pushed inside the Today stack (#642).' in (raw.decode() if isinstance(raw,bytes) else raw):
        from today_tab_route_delta import restore as restore_today_tab_route
        raw = restore_today_tab_route(path,raw)
    payload=Path(__file__).with_name('sync_payload_overflow_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest()==FIXTURE_SHA
    c=json.loads(payload).get(path)
    if c is None:return raw
    binary=isinstance(raw,bytes);text=raw.decode() if binary else raw
    if hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']:return raw
    assert hashlib.sha256(text.encode()).hexdigest()==c['current_sha'],'unrelated sync overflow delta: '+path
    for f in c['fragments']:
        assert text.count(f['new'])==1
        text=text.replace(f['new'],f['old'],1)
    assert hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']
    return text.encode() if binary else text
