"""Exact additive diagnostic inverse. Original contract pins stay unchanged."""
from pathlib import Path
import hashlib,json
FIXTURE=Path(__file__).with_suffix('.json')
FIXTURE_SHA='2b541d769f3840b8b3de1ba8fc3354dede613111cbc6ed22d06dd41a52bb699e'
def restore(file,raw):
    payload=FIXTURE.read_bytes()
    assert hashlib.sha256(payload).hexdigest()==FIXTURE_SHA
    spec=json.loads(payload)[file]
    assert hashlib.sha256(raw.encode()).hexdigest()==spec['head_sha256']
    for new,old in spec['inverse']:
        assert raw.count(new)==1
        raw=raw.replace(new,old,1)
    assert hashlib.sha256(raw.encode()).hexdigest()==spec['base_sha256']
    return raw
