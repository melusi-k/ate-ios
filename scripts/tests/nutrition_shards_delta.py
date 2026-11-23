"""Exact inverse for historical workflow guards, not native acceptance."""
from pathlib import Path
import hashlib,json
FIXTURE_SHA = '9ff5e66fadfb60489e409e0228e4678adbbceb6d64aaee15f7c7517503917dd0'
def restore(key, raw, strict=True):
    if key.split(':',1)[-1] != '.github/workflows/compile-check.yml': return raw
    payload=Path(__file__).with_name('nutrition_shards_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest()==FIXTURE_SHA
    c=json.loads(payload); binary=isinstance(raw,bytes)
    text=raw.decode() if binary else raw
    digest=hashlib.sha256(text.encode()).hexdigest()
    if digest==c['parent_sha256']: return raw
    if digest!=c['current_sha256'] and not strict: return raw
    assert digest==c['current_sha256'], 'unrelated nutrition shard delta'
    text=c['parent']
    assert hashlib.sha256(text.encode()).hexdigest()==c['parent_sha256']
    return text.encode() if binary else text
