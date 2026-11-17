"""Exact test-only native prompt inverse. Historical contracts remain unchanged."""
from pathlib import Path
import hashlib,json
FIXTURE=Path(__file__).with_suffix('.json')
DIGEST='67602fdd72db9872907980d886ab8e0d085b959f0b548310bad8441efa3081f0'
def restore(key,raw):
    from shopping_prewait_sheet_delta import restore as restore_shopping_prewait
    raw=restore_shopping_prewait(key,raw)
    from late_native_sheet_delta import restore as restore_late_sheet
    raw=restore_late_sheet(key,raw)
    payload=FIXTURE.read_bytes()
    assert hashlib.sha256(payload).hexdigest()==DIGEST, 'Password prompt fixture changed'
    item=json.loads(payload).get(key.split(':',1)[-1])
    if not item:return raw
    binary=isinstance(raw,bytes)
    text=raw.decode() if binary else raw
    if hashlib.sha256(text.encode()).hexdigest()==item['base']:return raw
    assert hashlib.sha256(text.encode()).hexdigest()==item['patched'], 'Unreviewed password prompt change: '+key
    assert text==item['new']
    return item['old'].encode() if binary else item['old']
