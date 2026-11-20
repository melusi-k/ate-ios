"""Exact native-found parser and obsolete-intent fixture correction inverse."""
from pathlib import Path
import json,hashlib
FIXTURE_SHA='980180e25895f96e561cac6707f3176b86ad71f96c8772b32082da18b99c3eaa'
def restore(path,raw):
    from generation_native_reds_delta import restore_for_history as restore_generation
    raw = restore_generation(path,raw)
    payload=Path(__file__).with_name('verified_heading_fix_inverse.json').read_bytes()
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
