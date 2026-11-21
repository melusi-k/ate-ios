"""Exact suggested-review button-styling inverse (#646) before older discovery pins."""
from pathlib import Path
import hashlib,json
FIXTURE_SHA='d06e156ccb03dfbb9304cebbee542e7bd0ca4360d4373de6d9471fc439638186'
MARKER='HStack(spacing: 8) {\n                            Button(session.savedIDs.contains(card.id)'
def restore(path,raw):
    if path!='Ate/Views/SuggestedNewRecipesView.swift':return raw
    payload=Path(__file__).with_name('suggest_review_buttons_inverse.json').read_bytes()
    assert hashlib.sha256(payload).hexdigest()==FIXTURE_SHA
    c=json.loads(payload).get(path)
    if c is None:return raw
    binary=isinstance(raw,bytes);text=raw.decode() if binary else raw
    # Older or unrelated historical states pass through; only the exact #646 head
    # content is inverted, and anything claiming the marker but differing fails.
    if MARKER not in text:return raw
    assert hashlib.sha256(text.encode()).hexdigest()==c['current_sha'],'unrelated current buttons delta: '+path
    for f in c['fragments']:
        assert text.count(f['new'])==1,'missing/changed/duplicate buttons fragment: '+path
        text=text.replace(f['new'],f['old'],1)
    assert hashlib.sha256(text.encode()).hexdigest()==c['parent_sha'],'unrelated buttons parent delta: '+path
    return text.encode() if binary else text
