from pathlib import Path
import hashlib
import unittest
ROOT = Path(__file__).resolve().parents[2]
INVERSES = {'Ate/Views/SettingsView.swift': ('// Keep the visible heading independently exposed, as with build notes.\n                            // Selectable combined content may be an AX Other rather than StaticText.\n                            Text("AI diagnostics").font(AteFont.body(12, .semibold))\n                                .accessibilityIdentifier("aiDiagnosticsHeading")\n                            VStack(alignment: .leading, spacing: 2) {\n                                Text("Model: " + OnDeviceBackend.availabilityDescription)\n                                Text("Last generation: " + (GenerationLog.last?.summary ?? "none yet"))\n                                    .accessibilityIdentifier("lastGeneration")\n                            }\n                            .textSelection(.enabled)\n                            .accessibilityElement(children: .combine)\n                            .accessibilityIdentifier("aiDiagnostics")\n                        }\n                        .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)\n                        .accessibilityElement(children: .contain', 'Text("AI diagnostics").font(AteFont.body(12, .semibold))\n                            Text("Model: " + OnDeviceBackend.availabilityDescription)\n                            Text("Last generation: " + (GenerationLog.last?.summary ?? "none yet"))\n                                .accessibilityIdentifier("lastGeneration")\n                        }\n                        .font(AteFont.body(12)).foregroundStyle(Theme.mutedForeground)\n                        .textSelection(.enabled)\n                        .accessibilityElement(children: .combine).accessibilityIdentifier("aiDiagnostics"', '2043a1d656662f88fe36bffc7b0d6510975b0e5bbb0d7d3f2df9f2cf1e725953'), 'AteUITests/SettingsAboutGeometryReceipt.swift': ('        print("SETTINGS-ABOUT-GEOMETRY \\(checkpoint) visible=\\(visible) row=\\(geometry(heading)) window=\\(geometry(window)) nav=\\(geometry(navigation)) tab=\\(geometry(tabs)) accessory=\\(geometry(accessory))")\n', '        print("SETTINGS-ABOUT-GEOMETRY \\(checkpoint) visible=\\(visible) heading=\\(heading.identifier) row=\\(geometry(heading)) window=\\(geometry(window)) nav=\\(geometry(navigation)) tab=\\(geometry(tabs)) accessory=\\(geometry(accessory))")\n', '8b5dce77613a0675d0b9374a8738c8d1eda4bd689e665fe92ff643750c3fc3e2')}
class SettingsDiagnosticsHeadingTests(unittest.TestCase):
    def test_exact_inverse_preserves_all_original_settings_and_receipt_bytes(self):
        for file, (new, old, expected) in INVERSES.items():
            source = (ROOT / file).read_text()
            self.assertEqual(source.count(new), 1, file)
            restored = source.replace(new, old, 1)
            self.assertEqual(hashlib.sha256(restored.encode()).hexdigest(), expected, file)

    def test_existing_journey_assertions_selectors_and_budgets_are_byte_identical(self):
        self.assertEqual(hashlib.sha256((ROOT / "AteUITests/CoverageUITests.swift").read_bytes()).hexdigest(), 'e3dab947e3c11ecde4080fe0e81bc73108788c52f4b6c7a8060c54d5c55c0b35')

    def test_diagnostic_log_does_not_resolve_a_missing_heading_identifier(self):
        source = (ROOT / "AteUITests/SettingsAboutGeometryReceipt.swift").read_text()
        self.assertNotIn("heading.identifier", source)
        self.assertIn('guard element.exists else { return "missing" }', source)
        self.assertIn("row=\(geometry(heading))", source)
