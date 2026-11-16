"""Exact additive Tools reveal inverse. Original assertion/budget guards remain."""
from pathlib import Path
import hashlib,json
FIXTURE=Path(__file__).with_suffix('.json')
FIXTURE_SHA='af9e5985a3cc5377de13da91e7120a3e11822abd197816aa406ca29384526e64'
def restore(key,raw):
    if key.split(':',1)[-1]!='AteUITests/CoverageUITests.swift':return raw
    payload=FIXTURE.read_bytes()
    assert hashlib.sha256(payload).hexdigest()==FIXTURE_SHA
    spec=json.loads(payload)
    binary=isinstance(raw,bytes)
    text=raw.decode() if binary else raw
    assert hashlib.sha256(text.encode()).hexdigest()==spec['after_sha256']
    assert text.count(spec['new'])==1
    text=text.replace(spec['new'],spec['old'],1)
    assert hashlib.sha256(text.encode()).hexdigest()==spec['before_sha256']
    return text.encode() if binary else text
