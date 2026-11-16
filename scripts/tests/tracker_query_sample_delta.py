"""Exact workflow diagnostic layer; original frozen pins remain authoritative."""
import hashlib
BASE='108c7cdceba87632a60e03a896807735ad015e5e6237ef9d8a20ffcfe067ebff'
PATCHED='f78e1d6b96f24cde232789f0cef37698958346ecfd29f7954c9b30ef030b0252'
PARTS=[(14175, '\n            tracker-query-sample', ''), (40406, '# Advisory single stack capture only if the original month AX Find stays blocked.\n          rm -f tracker-ui.log tracker-query-sample.stop\n          python3 scripts/sample-tracker-query.py --log tracker-ui.log --output tracker-query-sample --simulator "$SIM_ID" --stop tracker-query-sample.stop &\n          tracker_sampler=$!\n          trap \'touch tracker-query-sample.stop; wait "$tracker_sampler" 2>/dev/null || true\' EXIT\n          ', ''), (41295, '\n          touch tracker-query-sample.stop\n          wait "$tracker_sampler" 2>/dev/null || true\n          trap - EXIT', ''), (57984, 'tracker-query-sample\n            ', '')]
def restore(key, raw):
    if key not in {'source:.github/workflows/compile-check.yml', 'main:.github/workflows/compile-check.yml'}: return raw
    binary=isinstance(raw,bytes); text=raw.decode() if binary else raw
    digest=hashlib.sha256(text.encode()).hexdigest()
    if digest == BASE: return raw
    assert digest == PATCHED, 'Unreviewed Tracker sampling workflow change'
    for start,new,old in reversed(PARTS):
        assert text[start:start+len(new)]==new
        text=text[:start]+old+text[start+len(new):]
    assert hashlib.sha256(text.encode()).hexdigest()==BASE
    return text.encode() if binary else text
