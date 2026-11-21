"""Exact sibling-head composition inverse; preserves each parent fixture unchanged."""
from pathlib import Path
import json,hashlib
FIXTURE_SHA = '10f73527b1a692cbef4fdd73dc669fe3e8406a5a8af9dae3ee5f99e81b7aec46'
def parent_source(label,path,text):
    if path != 'Ate/Services/OnDeviceBackend.swift': return text
    payload=Path(__file__).with_name('add_stack_composition_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest()==FIXTURE_SHA
    c=json.loads(payload)[label]
    for f in c['fragments']:
        assert text.count(f['new'])==1
        text=text.replace(f['new'],f['old'],1)
    assert hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']
    return text
