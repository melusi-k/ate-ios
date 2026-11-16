"""Invert only the reviewed #539 screenshot-transport delta, never assertions."""
OLD = '    /// Attaches a named screenshot and mirrors it into the log as chunked base64\n    /// so the exact rendered pixels can be recovered from CI logs alone.\n    private func shot(_ name: String) {\n        let screenshot = XCUIScreen.main.screenshot()\n        let attachment = XCTAttachment(screenshot: screenshot)\n        attachment.name = name\n        attachment.lifetime = .keepAlways\n        add(attachment)\n        let b64 = screenshot.pngRepresentation.base64EncodedString()\n        print("SNAPSHOT-BEGIN \\(name) \\(b64.count)")\n        var i = b64.startIndex\n        while i < b64.endIndex {\n            let j = b64.index(i, offsetBy: 4000, limitedBy: b64.endIndex) ?? b64.endIndex\n            print("SNAPSHOT-CHUNK \\(name) \\(b64[i..<j])")\n            i = j\n        }\n        print("SNAPSHOT-END \\(name)")\n    }\n\n'
NEW = "    /// Retain the full-resolution screenshot at this exact journey point.\n    /// CI mirrors these bytes only after XCTest finishes, so terminal writes\n    /// cannot block the runner inside a test's execution budget (#539).\n    private func shot(_ name: String) {\n        let screenshot = XCUIScreen.main.screenshot()\n        let attachment = XCTAttachment(screenshot: screenshot)\n        attachment.name = name\n        attachment.lifetime = .keepAlways\n        add(attachment)\n    }\n\n"
OLD_COMMENT = '/// (SNAPSHOT-CHUNK base64) so review sees exactly what shipped, not just assertions.'
NEW_COMMENT = '/// after XCTest (SNAPSHOT-CHUNK base64) so runner stdout cannot consume test budgets.'

def restore(key, raw):
    if key != 'source:AteUITests/JournalOpenStateUITests.swift':
        return raw
    binary = isinstance(raw, bytes)
    text = raw.decode() if binary else raw
    assert text.count(NEW) == 1, 'post-run shot helper absent, modified or duplicated'
    assert text.count(NEW_COMMENT) == 1, 'post-run shot comment absent, modified or duplicated'
    text = text.replace(NEW, OLD, 1).replace(NEW_COMMENT, OLD_COMMENT, 1)
    return text.encode() if binary else text
