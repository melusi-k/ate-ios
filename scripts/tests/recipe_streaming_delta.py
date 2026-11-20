"""Exact per-request streaming inverse to ec792a35 before frozen checks."""
from pathlib import Path
import hashlib,json
FIXTURE_SHA='5a87c0e149ec571324e7c08620a12732e44542ecf6915be56c482a3a64af9b17'
def restore(path,raw):
    from generation_native_reds_delta import restore_for_history as restore_generation
    raw = restore_generation(path,raw)
    payload=Path(__file__).with_name('recipe_streaming_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest()==FIXTURE_SHA
    c=json.loads(payload).get(path)
    if c is None:return raw
    binary=isinstance(raw,bytes);text=raw.decode() if binary else raw
    if hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']:return raw
    from recipe_content_admission_delta import restore as restore_content
    text = restore_content(path,text)
    assert hashlib.sha256(text.encode()).hexdigest()==c['current_sha'],'unrelated current streaming delta: '+path
    for f in c['fragments']:
        assert text.count(f['new'])==1,'missing/changed/duplicate stream fragment: '+path
        text=text.replace(f['new'],f['old'],1)
    assert hashlib.sha256(text.encode()).hexdigest()==c['parent_sha'],'unrelated streaming parent delta: '+path
    return text.encode() if binary else text
