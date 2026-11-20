"""Exact fixture-only inverse before historical whole-file checks. No hash replaced."""
from pathlib import Path
import hashlib,json
FIXTURE_SHA='9f350cea201f5e659fa39aed4c27d70043cfbf9e202e16251c81fe87cbd85660'
def restore(key,raw):
    from group28_swipe_target_delta import restore as restore_swipe
    raw = restore_swipe(key,raw)
    path=key.split(':',1)[-1]
    payload=Path(__file__).with_name('all_ui_prompt_source_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest()==FIXTURE_SHA
    contract=json.loads(payload)['contracts'].get(path)
    if contract is None:return raw
    binary=isinstance(raw,bytes)
    text=raw.decode() if binary else raw
    if hashlib.sha256(text.encode()).hexdigest()==contract['parent_sha']:return raw
    for fragment in contract['fragments']:
        assert text.count(fragment['new'])==1,'missing/changed/duplicated fixture fragment: '+path
        text=text.replace(fragment['new'],fragment['old'],1)
    assert hashlib.sha256(text.encode()).hexdigest()==contract['parent_sha'],'unrelated source changed: '+path
    return text.encode() if binary else text
