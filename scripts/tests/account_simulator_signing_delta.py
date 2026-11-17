"""Exact account-only simulator signing inverse, not an alternate workflow."""
from pathlib import Path
import hashlib,json
FIXTURE=Path(__file__).with_suffix('.json')
DIGEST='32fe09862350f10e37576ce4fa3ec870bd7c9ac11aa8b0f970453d36afb2a6e5'

def restore(key,raw):
    from window_hit_failure_delta import restore as restore_window_hit
    raw=restore_window_hit(key,raw)
    if key.split(':',1)[-1] != '.github/workflows/compile-check.yml': return raw
    payload=FIXTURE.read_bytes()
    assert hashlib.sha256(payload).hexdigest()==DIGEST, 'Signing inverse fixture changed'
    item=json.loads(payload)
    binary=isinstance(raw,bytes)
    text=raw.decode() if binary else raw
    digest=hashlib.sha256(text.encode()).hexdigest()
    if digest==item['base_sha256']: return raw
    assert digest==item['patched_sha256'], 'Unreviewed simulator signing delta: '+key
    for fragment in reversed(item['fragments']):
        assert text.count(fragment['new'])==1, 'Signing fragment absent/changed/duplicated'
        text=text.replace(fragment['new'],fragment['old'],1)
    assert hashlib.sha256(text.encode()).hexdigest()==item['base_sha256']
    return text.encode() if binary else text
