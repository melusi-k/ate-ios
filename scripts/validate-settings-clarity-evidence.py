#!/usr/bin/env python3
"""Fail closed on missing/skipped named tests or unscoped/undecodable captures."""
import json
import pathlib
import re
import subprocess
import tempfile

log = pathlib.Path('settings-ui-qualification.log').read_text()
required = {
    'SettingsAIStatusTests': [
        'testPrivateModeTakesPrecedenceOverEveryModelState',
        'testEveryUnavailableStateExplainsDemoFallbackWithoutRawSDKReason',
        'testHardwareAndOSRequirementsAreNotConflated',
        'testExportExplicitlyDisclosesJournalExclusionAndNoSync',
        'testReadyStateDoesNotSuggestDemoOrTurningOnAI',
    ],
    'SettingsClarificationUITests': ['testPrivateModeExplanationTracksToggleAndRetainsScreenshot'],
    'SettingsOrganizationUITests': ['testSyncSummaryNormalText', 'testAppearanceChoicesPersistAcrossRelaunchAtNormalText'],
    'SettingsAuditUITests': ['testAuditSettingsRoot'],
}
for suite, methods in required.items():
    for method in methods:
        # XCTest native log format, full exact class/method and PASSED terminal state.
        expression = r"Test Case '-\[(?:[A-Za-z0-9_]+\.)?" + re.escape(suite) + r' ' + re.escape(method) + r"\]' passed \([0-9.]+ seconds\)\."
        assert re.search(expression, log), f'Missing named PASS: {suite}/{method}'

raw = pathlib.Path('ui-screenshots/raw').resolve()
manifest = json.loads((raw / 'manifest.json').read_text())
scoped = [
    ('SettingsClarificationUITests/testPrivateModeExplanationTracksToggleAndRetainsScreenshot', 'settings-private-mode-guidance'),
    ('SettingsOrganizationUITests/testSyncSummaryNormalText', 'settings-sync-summary-normal'),
]
for mode in ['light', 'dark', 'system']:
    for suffix in ['', '-diary-navigation', '-log-food-sheet']:
        scoped.append(('SettingsOrganizationUITests/testAppearanceChoicesPersistAcrossRelaunchAtNormalText',
                       f'appearance-normal-{mode}{suffix}'))
scoped.append(('SettingsOrganizationUITests/testAppearanceChoicesPersistAcrossRelaunchAtNormalText',
               'appearance-normal-dark-after-relaunch'))
for test, capture in scoped:
    matches = []
    for record in manifest:
        identifier = record.get('testIdentifier', '').replace('()', '')
        if identifier != test:
            continue
        for attachment in record.get('attachments', []):
            name = attachment.get('suggestedHumanReadableName', '')
            if name == capture or name.startswith(capture + '_') or name.startswith(capture + '.'):
                file = (raw / attachment['exportedFileName']).resolve()
                assert file.parent == raw, 'Attachment path escapes export directory'
                matches.append(file)
    assert matches, f'Missing scoped capture: {test} / {capture}'
    for file in matches:
        assert file.read_bytes()[:8] == b'\x89PNG\r\n\x1a\n', f'Not PNG: {file}'
        with tempfile.TemporaryDirectory() as temp:
            # sips forces actual image decoding, unlike header/file-exists checks.
            decoded = pathlib.Path(temp) / 'decoded.png'
            result = subprocess.run(['sips', '-s', 'format', 'png', str(file), '--out', str(decoded)],
                                    capture_output=True, text=True)
            assert result.returncode == 0 and decoded.is_file(), f'PNG decode failed: {file}: {result.stderr}'
            dimensions = subprocess.check_output(['sips', '-g', 'pixelWidth', '-g', 'pixelHeight', str(decoded)], text=True)
            width = re.search(r'pixelWidth:\s*(\d+)', dimensions)
            height = re.search(r'pixelHeight:\s*(\d+)', dimensions)
            assert width and height and int(width[1]) >= 300 and int(height[1]) >= 500, f'Invalid screenshot dimensions: {file}'
            print(f'Decoded scoped capture: {test} / {capture}: {width[1]} x {height[1]}')
print('All exact named tests passed; required scoped screenshots decoded. Human pixel review still required.')
