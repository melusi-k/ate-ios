from pathlib import Path
import hashlib,unittest
ROOT=Path(__file__).resolve().parents[2]
REPLACEMENTS=[('    private let syncCoordinator = SyncCoordinator()\n    var syncState: SyncState {\n        get { syncCoordinator.state }\n        set { syncCoordinator.state = newValue }\n    }\n', '    var syncState: SyncState = .signedOut\n'), ('    private var syncTask: Task<Void, Never>? {\n        get { syncCoordinator.scheduledTask }\n        set { syncCoordinator.scheduledTask = newValue }\n    }\n    private var syncInFlight: Bool {\n        get { syncCoordinator.inFlight }\n        set { syncCoordinator.inFlight = newValue }\n    }\n    private var syncRequestedWhileBusy: Bool {\n        get { syncCoordinator.requestedWhileBusy }\n        set { syncCoordinator.requestedWhileBusy = newValue }\n    }\n', '    private var syncTask: Task<Void, Never>?\n    private var syncInFlight = false\n    private var syncRequestedWhileBusy = false\n'), ('            let remote = try await syncCoordinator.pull(using: sync, session: s)\n', '            let remote = try await sync.pull(session: s)\n'), ('            try await syncCoordinator.push(out, using: sync, session: s)\n', '            try await sync.push(out, session: s)\n')]

class SyncCoordinatorBoundaryContracts(unittest.TestCase):
    def test_entire_appstore_reconstructs_original_after_only_reviewed_facade_delta(self):
        source=(ROOT/"Ate/Store/AppStore.swift").read_text()
        for new,old in REPLACEMENTS:
            self.assertEqual(source.count(new),1)
            source=source.replace(new,old,1)
        self.assertEqual(hashlib.sha256(source.encode()).hexdigest(), '09bf254a50d65f3f13c97e7f79a5444375bca885ce32f65f878a41fb573489c6')
    def test_versions_fail_closed_and_coordinator_does_not_own_domain_writes(self):
        adapter=(ROOT/'Ate/Logic/SyncPayloadVersion.swift').read_text()
        for token in ['current = 1', 'CFBooleanGetTypeID()', 'fields["schema_version"] == nil', 'number.doubleValue == Double(current)']:
            self.assertIn(token,adapter)
        safety=(ROOT/'Ate/Logic/SyncPayloadSafety.swift').read_text()
        self.assertIn('SyncPayloadVersion.compatibleFields(raw)',safety)
        coordinator=(ROOT/'Ate/Services/SyncCoordinator.swift').read_text()
        for forbidden in ['UserDefaults','Keychain','persistRecipes','performOrdinaryWrite','Task.detached']:
            self.assertNotIn(forbidden,coordinator)
        for token in ['@MainActor @Observable','try await service.pull(session: session)','try await service.push(records, session: session)']:
            self.assertIn(token,coordinator)
