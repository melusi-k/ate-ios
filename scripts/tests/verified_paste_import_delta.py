"""Exact direct-import inverse before existing frozen-source partitions."""
from pathlib import Path
import hashlib,json
FIXTURE_SHA='c9c47f10d433eebb512382c9a32b30164ea27c9c3b810ec2918be74bbdd25794'
def restore(path,raw):
    from verified_heading_fix_delta import restore as restore_heading
    raw = restore_heading(path,raw)
    payload=Path(__file__).with_name('verified_paste_import_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest()==FIXTURE_SHA
    c=json.loads(payload).get(path)
    if c is None:return raw
    binary=isinstance(raw,bytes)
    text=raw.decode() if binary else raw
    if hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']:return raw
    from recipe_streaming_delta import restore as restore_stream
    text = restore_stream(path,text)
    from steps_only_fixture_delta import restore as restore_fixture
    text = restore_fixture(path,text)
    # Native compiler correction: the successful import now propagates throws.
    # Remove only this exact declaration delta before the original pinned inverse.
    if path == 'AteTests/AddPromptSourceImportTests.swift':
        old = '    func testRecognizableUnverifiableRecipeKeepsExistingFailClosedBackendBoundary() async {'
        new = '    func testRecognizableUnverifiableRecipeKeepsExistingFailClosedBackendBoundary() async throws {'
        if new in text:
            assert text.count(new) == 1
            text = text.replace(new, old, 1)
    for f in c['fragments']:
        assert text.count(f['new'])==1,'missing/changed/duplicate import fragment: '+path
        text=text.replace(f['new'],f['old'],1)
    assert hashlib.sha256(text.encode()).hexdigest()==c['parent_sha'],'unrelated parent delta: '+path
    return text.encode() if binary else text
