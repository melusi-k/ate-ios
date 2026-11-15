"""Exact inverse of this diagnostic packet only. Original hash guards still run."""
from pathlib import Path
import hashlib
import unittest
ROOT = Path(__file__).resolve().parents[2]
INSERTIONS = {'Ate/Views/LibraryView.swift': ['                #if DEBUG\n                .modifier(SearchReceiptAccessibilityDiagnostic(receipt: SearchReceiptDiagnostic.enabled ? SearchReceiptDiagnostic.accessibilityReceipt(stored: query.count) : nil))\n                #endif\n', '    static func accessibilityReceipt(stored: Int) -> String {\n        "pid=\\(ProcessInfo.processInfo.processIdentifier) stored=\\(stored) events=\\(events) rows=\\(rows.count)|" + rows.joined(separator: "|")\n    }\n', '\n#if DEBUG\n/// Explicit diagnostic flag only. Reuses the existing count label, with no new\n/// controls, query text, storage writes or focus/keyboard reads.\nprivate struct SearchReceiptAccessibilityDiagnostic: ViewModifier {\n    let receipt: String?\n    func body(content: Content) -> some View {\n        if let receipt {\n            content.accessibilityValue(receipt)\n        } else {\n            content\n        }\n    }\n}\n#endif\n'], 'AteUITests/ExploreUITests.swift': ['            captureSearchWriteReceipt("before-teardown")\n', '        captureSearchWriteReceipt("after-single-input")\n', '\nextension ExploreUITests {\n    /// Read the app-owned numeric ring while this exact process is still alive.\n    /// No simctl cache lookup after the test class, extra wait, input or retry.\n    private func captureSearchWriteReceipt(_ phase: String) {\n        let value = app.staticTexts["libraryCount"].value as? String ?? "receipt-value-unavailable"\n        let body = "SEARCH-WRITE-RECEIPT phase=\\(phase) \\(value)"\n        print(body)\n        let attachment = XCTAttachment(string: body)\n        attachment.name = "search-write-receipt-" + phase\n        attachment.lifetime = .keepAlways\n        add(attachment)\n    }\n}\n']}
HASHES = {'Ate/Views/LibraryView.swift': '14948188f9859bad9b02c5537ca5fb2faa9d61d29ffe3127c2437071551082ff', 'AteUITests/ExploreUITests.swift': '5e300bda3a3f8ab02caae977a6d3906f0d1df4700b11d29cbbb443af6fcf1b25'}
def original_source(path, source):
    for block in INSERTIONS[path]:
        if source.count(block) != 1:
            raise AssertionError("Exact live-receipt insertion missing or duplicated: " + path)
        source = source.replace(block, "", 1)
    return source

class LiveSearchReceiptTests(unittest.TestCase):
    def test_exact_main_files_reconstructed(self):
        for path, expected in HASHES.items():
            self.assertEqual(hashlib.sha256(original_source(path, (ROOT/path).read_text()).encode()).hexdigest(), expected)

    def test_insertion_deletion_and_mutation_rejected(self):
        for path, blocks in INSERTIONS.items():
            source = (ROOT/path).read_text()
            for block in blocks:
                for mutant in (source.replace(block, "", 1), source.replace(block, block + block, 1), source.replace(block, block.replace(next(c for c in block if c.isalpha()), "Z", 1), 1)):
                    with self.assertRaises(AssertionError):
                        original_source(path, mutant)

    def test_original_input_mutation_still_fails_frozen_hash(self):
        path = "AteUITests/ExploreUITests.swift"
        source = (ROOT/path).read_text()
        for old,new in [('search.typeText("miso")','search.typeText("mi")'), ('[fullQuery], timeout: 5','[fullQuery], timeout: 50'), ('XCTAssertEqual(search.value as? String, "miso"','XCTAssertEqual(search.value as? String, "mi"')]:
            self.assertIn(old, source)
            mutant = original_source(path, source.replace(old,new,1))
            self.assertNotEqual(hashlib.sha256(mutant.encode()).hexdigest(), HASHES[path])

    def test_transport_precedes_existing_failure_and_termination(self):
        ui=(ROOT/"AteUITests/ExploreUITests.swift").read_text()
        self.assertLess(ui.index('search.typeText("miso")'),ui.index('captureSearchWriteReceipt("after-single-input")'))
        self.assertLess(ui.index('captureSearchWriteReceipt("after-single-input")'),ui.index('XCTWaiter.wait(for: [fullQuery]'))
        self.assertLess(ui.index('captureSearchWriteReceipt("before-teardown")'),ui.index('app.terminate()'))
        for token in ['XCTAttachment(string: body)', 'print(body)', '.keepAlways', 'app.staticTexts["libraryCount"].value']:
            self.assertIn(token,ui)

    def test_gate_numeric_only_no_new_state_or_input(self):
        app=''.join(INSERTIONS["Ate/Views/LibraryView.swift"])
        self.assertIn('SearchReceiptDiagnostic.enabled ?',app)
        self.assertIn('stored: query.count',app)
        self.assertIn('#if DEBUG',app)
        self.assertIn('rows.joined(separator: "|")',app)
        for forbidden in ['@State','@Observable','Timer(','.async','query =','hasKeyboardFocus','firstResponder','wrappedValue =']:
            self.assertNotIn(forbidden,app)
        ui=''.join(INSERTIONS["AteUITests/ExploreUITests.swift"])
        for forbidden in ['waitForExistence','XCTWaiter','typeText(','.tap()', 'sleep(', 'XCTAssert']:
            self.assertNotIn(forbidden,ui)
