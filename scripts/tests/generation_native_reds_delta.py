"""Exact inverse for the native-found generation corrections only."""
from pathlib import Path
import hashlib,json
FIXTURE_SHA='eb5e05b021928f94e7e9081bd726956406abe454b0cb8494462352cd1d876dce'
def restore(path,raw):
    payload=Path(__file__).with_name('generation_native_reds_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest()==FIXTURE_SHA
    c=json.loads(payload).get(path)
    if c is None:return raw
    binary=isinstance(raw,bytes);text=raw.decode() if binary else raw
    if hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']:return raw
    assert hashlib.sha256(text.encode()).hexdigest()==c['current_sha'],'unrelated generation native delta: '+path
    for f in c['fragments']:
        assert text.count(f['new'])==1
        text=text.replace(f['new'],f['old'],1)
    assert hashlib.sha256(text.encode()).hexdigest()==c['parent_sha']
    return text.encode() if binary else text

def restore_for_history(path,raw):
    text=raw.decode() if isinstance(raw,bytes) else raw
    markers={
        'Ate/Logic/SourceDraftImport.swift':'static func inlineCaptionCard(',
        'Ate/Services/OnDeviceBackend.swift':'SourceDraftImport.inlineCaptionCard(text)',
        'AteTests/RecipeStreamingTests.swift':'Initial preview must publish synchronously:',
        'AteTests/SourceRecipeFidelityTests.swift':'func testVerifiedInlineCaptionKeepsExactKnownFactsWithoutCallingFailingClassifier('
    }
    marker=markers.get(path)
    return restore(path,raw) if marker and marker in text else raw
