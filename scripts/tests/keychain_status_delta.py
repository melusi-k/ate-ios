"""Exact status-only wrapper inverse; original security branches remain audited."""
import hashlib,json
from pathlib import Path
FIXTURE=Path(__file__).with_suffix('.json')
DIGEST='219bb769e2da73e17fde6cc9600d0546cda4f5cdd1222877cdec43aaf695481a'

def restore(key,raw):
    from cleanup_phase_delta import restore as restore_cleanup
    raw=restore_cleanup(key,raw)
    payload=FIXTURE.read_bytes()
    assert hashlib.sha256(payload).hexdigest()==DIGEST
    spec=json.loads(payload).get('source:'+key.split(':',1)[-1])
    if not spec:return raw
    binary=isinstance(raw,bytes)
    text=raw.decode() if binary else raw
    if hashlib.sha256(text.encode()).hexdigest()==spec['base']:return raw
    assert text==spec['new'], 'Unreviewed status diagnostic edit: '+key
    return spec['old'].encode() if binary else spec['old']

ADDITIONS=Path(__file__).with_name('keychain_status_additions.json')
ADDITIONS_DIGEST='1de1d9f82b8749697e03eaeb20fef9fb639564b40b1e5d47a6a54baa547238f6'

def is_added(path,raw):
    payload=ADDITIONS.read_bytes()
    assert hashlib.sha256(payload).hexdigest()==ADDITIONS_DIGEST
    expected=json.loads(payload).get(path)
    if expected is None:return False
    assert hashlib.sha256(raw).hexdigest()==expected, 'Unreviewed diagnostic addition: '+path
    return True
