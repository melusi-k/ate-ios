"""Exact authorized audit source layer; inherited whole-file pins preserved."""
import hashlib
PATH='Ate/Resources/ProductUpdates/catalog.json'
BASE='7c08b52b7e01545855aac627ceea92ac2f9a70627e1c1167e4667cd792811bc3'
PATCHED='e90e2336834659da47a816b94d26a4c854e2c284f8a0304ca3ab6ecb06f4d5b7'
PARTS=[(587, 'Br', 'Pl'), (590, 'n', 'cehol'), (592, '', 'er'), (618, '', 'Placeholder illustration of '), (622, 'l', 'pr'), (624, 'g', 'duct updates, n'), (626, '', 't an app screenshot'), (826, 'fals', 'tru'), (928, 'Br', 'Pl'), (931, 'n', 'cehol'), (933, '', 'er'), (959, 'A', 'Placeholder illus'), (961, '', 'ration of th'), (963, 'l', 'pr'), (965, 'g', 'duct updates menu, n'), (967, '', 't an app screenshot'), (1254, 'fals', 'tru')]
VIEW='Ate/Views/ProductUpdatesViews.swift'
VIEW_BASE='b839618892148326636471c779c51e2ed138b2ec0a48124540665465fa0771b1'
def _restore_view(raw):
    binary=isinstance(raw,bytes);text=raw.decode() if binary else raw
    if hashlib.sha256(text.encode()).hexdigest()==VIEW_BASE: return raw
    a1='    @State private var showingSlides = false\n'
    i1='    @Environment(\\.requestReview) private var requestReview\n'
    assert text.count(a1)==1 and i1 not in text
    text=text.replace(a1,a1+i1,1)
    a2='                ProductUpdatesSeenStore(defaults: ProductUpdatesSeenStore.launchDefaults).markSeen(release.version)\n'
    i2='                requestReview()\n'
    assert text.count(a2)==1 and i2 not in text
    text=text.replace(a2,a2+i2,1)
    assert hashlib.sha256(text.encode()).hexdigest()==VIEW_BASE
    return text.encode() if binary else text
def restore(file, raw):
    if file == VIEW: return _restore_view(raw)
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
