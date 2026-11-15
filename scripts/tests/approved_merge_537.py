"""Exact reviewed opposite-parent inverse deltas; no git or network at runtime."""
import hashlib,json
from pathlib import Path
_FIXTURE=Path(__file__).with_name('approved_merge_537_inverses.json')
_FIXTURE_SHA256='033c0722bd0afa84aa9870da65f35ccf95814d132fc3faa0587857dab60dab58'
def normalize(key, raw):
    payload=_FIXTURE.read_bytes()
    assert hashlib.sha256(payload).hexdigest()==_FIXTURE_SHA256, 'approved inverse fixture changed'
    contract=json.loads(payload)['contracts'][key]
    binary=isinstance(raw,bytes)
    text=raw.decode() if binary else raw
    cursor=0
    for item in contract['inverse_fragments']:
        old,new=item['merged_fragment'],item['parent_fragment']
        assert text.count(old)==1, 'approved inverse fragment absent, changed or duplicated: '+key
        start=text.index(old)
        assert start>=cursor, 'approved inverse placement/order changed: '+key
        text=text[:start]+new+text[start+len(old):]
        cursor=start+len(new)
    return text.encode() if binary else text
