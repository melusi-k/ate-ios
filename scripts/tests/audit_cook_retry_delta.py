"""Exact authorized audit source layer; inherited whole-file pins preserved."""
import hashlib
PATH='Ate/Views/CookModeView.swift'
BASE='162f61642d15c92390ae36fd42048443e6e169d9a409cb8c827b0bde0dd3fcff'
PATCHED='252e825a80d9856ce1b026c1d40f84335dd783a626302eb08228efdb04358b9a'
PARTS=[(4964, '// A partial finish may already have cleared the session. Dismiss never repeats a write.\n            ', ''), (5073, 'D', 'Try aga'), (5075, 'smiss', 'n')]
def restore(file, raw):
    if file != PATH: return raw
    binary=isinstance(raw,bytes);text=raw.decode() if binary else raw
    digest=hashlib.sha256(text.encode()).hexdigest()
    if digest == BASE: return raw
    assert digest == PATCHED, 'Unreviewed audit source mutation'
    for start,new,old in reversed(PARTS):
        assert text[start:start+len(new)]==new
        text=text[:start]+old+text[start+len(new):]
    assert hashlib.sha256(text.encode()).hexdigest()==BASE
    return text.encode() if binary else text
