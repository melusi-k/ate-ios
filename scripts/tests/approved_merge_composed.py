"""Composed #535+#536 opposite-parent inverse deltas; no git or network at runtime.

Covers BOTH delta families on the composed head: #535's and #536's fragments for the
shared pinned files (compile-check.yml, CoverageUITests.swift) plus each side's
unshared keys. Original bytes are restored only after all fragments of both families
are reversed; guards hash after full reversal (no hash replacement, no weakened pins).
The 'approved' naming is retained from the branch-carried modules for drop-in
compatibility; it records no external review by itself."""
import hashlib,json
from pathlib import Path
_FIXTURE=Path(__file__).with_name('approved_merge_composed_inverses.json')
_FIXTURE_SHA256='ef5c07c1bf823f61f6688f27cc0356581b74fee14c75b1b7c6c0ebf070991b28'
def normalize(key, raw):
    from ocr_host_timing_inverse import restore as restore_ocr_host_timing
    raw = restore_ocr_host_timing(key, raw)
    from export_target_readiness_delta import restore
    raw = restore(key, raw)
    payload=_FIXTURE.read_bytes()
    assert hashlib.sha256(payload).hexdigest()==_FIXTURE_SHA256, 'composed inverse fixture changed'
    contract=json.loads(payload)['contracts'][key]
    binary=isinstance(raw,bytes)
    text=raw.decode() if binary else raw
    cursor=0
    for item in contract['inverse_fragments']:
        old,new=item['merged_fragment'],item['parent_fragment']
        assert text.count(old)==1, 'composed inverse fragment absent, changed or duplicated: '+key
        start=text.index(old)
        assert start>=cursor, 'composed inverse placement/order changed: '+key
        text=text[:start]+new+text[start+len(old):]
        cursor=start+len(new)
    return text.encode() if binary else text
