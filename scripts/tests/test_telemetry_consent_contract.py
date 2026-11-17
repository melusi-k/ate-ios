from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]

class TelemetryConsentContracts(unittest.TestCase):
    def test_shipping_gate_and_explicit_consent_precede_task_start(self):
        text = (ROOT/'Ate/Services/TelemetryClient.swift').read_text()
        self.assertIn('static let remoteReleaseReady = false', text)
        record = text.split('func record(', 1)[1]
        self.assertLess(record.index('guard canEnable,'), record.index('session.dataTask('))
        self.assertIn('as? Bool == true', record)
        self.assertNotIn('Task.detached', text)
        self.assertNotIn('Net.data(for:', text)
        self.assertNotIn('try await', record)
        self.assertLess(record.index('lock.lock()'), record.index('task.resume()'))
        self.assertIn('tasks.values.forEach { $0.cancel() }', text)
    def test_local_history_contract_and_product_hooks_are_not_removed(self):
        text = (ROOT/'Ate/Services/DiagnosticHistory.swift').read_text()
        for token in ['maximumEntries = 200', 'func clear()', 'func exportReport(', 'TelemetryClient.shared.record(kind, at: date)']:
            self.assertIn(token, text)
        tests = (ROOT/'AteTests/TelemetryConsentTests.swift').read_text()
        for token in ['testBetaChannelIsNotConsentAndDefaultDoesNotUpload',
                      'testShippingReadinessGateOverridesEvenStoredConsent',
                      'testExplicitConsentPersistsAndRevocationStopsNewRequests',
                      'testOnlyAllowlistedCategoryEnvelopeIsSentWithoutIdentifiers',
                      'testOldLocalHistoryIsNotReplayedOnConsent']:
            self.assertIn(token, tests)
        self.assertIn('settings.protocolClasses = [TelemetryIntercept.self]', tests)
    def test_visible_unavailable_and_revoke_controls(self):
        text = (ROOT/'Ate/Views/DiagnosticHistoryView.swift').read_text()
        for token in ['diagnostics.remoteConsent', 'diagnostics.remoteStatus', 'diagnostics.remoteRevoke',
                      '.disabled(!TelemetryClient.shared.canEnable)', 'diagnostics.clear', 'diagnostics.export']:
            self.assertIn(token, text)
    def test_policy_is_default_off_not_beta_implied_consent(self):
        for path in ['docs/TELEMETRY.md','docs/legal/privacy.md','docs/legal/subprocessors.md','docs/legal/cookies.md']:
            text = (ROOT/path).read_text().lower()
            self.assertIn('off by default', text, path)
            self.assertNotIn('send privacy-safe remote telemetry by default', text)
            self.assertNotIn('✓ by default on recognized', text)
        self.assertIn('No offline upload queue', (ROOT/'docs/TELEMETRY.md').read_text())
