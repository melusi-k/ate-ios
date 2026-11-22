"""Reverse only access-lost phase stamps before the earlier await diagnostic pin."""
from pathlib import Path
import hashlib
import json
FIXTURE_SHA = '3b70df014f197b15f6e0ca517b195b8992e6e5bd33eaf37077d18019e5fe97dd'
def restore(source):
    payload = Path(__file__).with_name('insights_accesslost_phase_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest() == FIXTURE_SHA
    c = json.loads(payload)
    assert hashlib.sha256(source.encode()).hexdigest() == c['current_sha256']
    assert source.count(c['new']) == 1
    restored = source.replace(c['new'], c['old'], 1)
    assert hashlib.sha256(restored.encode()).hexdigest() == c['parent_sha256']
    return restored
