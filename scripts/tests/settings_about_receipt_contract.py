import hashlib
START='        #if DEBUG\n        var settingsAboutGeometryReceipt = SettingsAboutGeometryReceipt()\n        #endif\n'
WRAP='            func fullyVisible() -> Bool {\n                let visible = evaluatedFullyVisible()\n                #if DEBUG\n                settingsAboutGeometryReceipt.observe(visible: visible, heading: heading, app: app)\n                #endif\n                return visible\n            }\n'
BASE_SHA256='f2865352acbfcb1df5b57cc6a7764083112b4ac279e715f40e901463c10dbd9e'
def original_coverage_bytes(raw):
    text=raw.decode()
    assert text.count(START)==1
    assert text.count(WRAP)==1
    text=text.replace(START,'').replace(WRAP,'')
    assert text.count('func evaluatedFullyVisible() -> Bool {')==1
    text=text.replace('func evaluatedFullyVisible() -> Bool {','func fullyVisible() -> Bool {')
    assert hashlib.sha256(text.encode()).hexdigest()==BASE_SHA256
    return text.encode()
