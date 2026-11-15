from approved_merge_539 import normalize
from pathlib import Path
import unittest,hashlib
ROOT=Path(__file__).resolve().parents[2]
def restore_sync_crash_capture(s):
    from test_user_data_sync_model_qualification import restore_sync_model_qualification
    s=restore_sync_model_qualification(s)
    s=s.replace('            print("SYNC-MATRIX boundary=\\(boundary.rawValue) phase=recovery-assertions-return")\n','',1)
    s=s.replace('            print("SYNC-MATRIX boundary=\\(boundary.rawValue) phase=reopened-before-recovery")\n','',1)
    s=s.replace('            print("SYNC-MATRIX boundary=\\(boundary.rawValue) phase=release-return")\n','',1)
    s=s.replace('            print("SYNC-MATRIX boundary=\\(boundary.rawValue) phase=release-enter")\n','',1)
    s=s.replace('            print("SYNC-MATRIX boundary=\\(boundary.rawValue) phase=commit2-return")\n','',1)
    s=s.replace('            print("SYNC-MATRIX boundary=\\(boundary.rawValue) phase=commit2-enter")\n','',1)
    s=s.replace('                print("SYNC-MATRIX boundary=\\(boundary.rawValue) checkpoint=\\(b.rawValue)")\n','',1)
    s=s.replace('            print("SYNC-MATRIX boundary=\\(boundary.rawValue) phase=commit1-return")\n','',1)
    s=s.replace('            print("SYNC-MATRIX boundary=\\(boundary.rawValue) phase=commit1-enter")\n','',1)
    s=s.replace('            print("SYNC-MATRIX boundary=\\(boundary.rawValue) phase=seed-return")\n','',1)
    s=s.replace('            captureSyncSchema(container, phase: "matrix-opened-before-seed")\n','',1)
    s=s.replace('            print("SYNC-MATRIX boundary=\\(boundary.rawValue) phase=iteration-enter")\n','',1)
    s=s.replace('        print("SYNC-MODEL-CAPTURE phase=testEditAfterCrashMakesReplayRefuseAndPreserve-save-return")\n','',1)
    s=s.replace('        print("SYNC-MODEL-CAPTURE phase=testEditAfterCrashMakesReplayRefuseAndPreserve-save-enter")\n','',1)
    s=s.replace('        print("SYNC-MODEL-CAPTURE phase=testEditAfterCrashMakesReplayRefuseAndPreserve-text-set-enter")\n','',1)
    s=s.replace('        captureSyncSchema(store.journalStore.container, phase: "testEditAfterCrashMakesReplayRefuseAndPreserve-fetch-enter")\n','',1)
    s=s.replace('        captureSyncSchema(store.journalStore.container, phase: "testEditAfterCrashMakesReplayRefuseAndPreserve-seed-enter")\n','',1)
    s=s.replace('            print("SYNC-MODEL-CAPTURE phase=testEditDuringUploadRefusesCommit-save-return")\n','',1)
    s=s.replace('            print("SYNC-MODEL-CAPTURE phase=testEditDuringUploadRefusesCommit-save-enter")\n','',1)
    s=s.replace('            captureSyncSchema(store.journalStore.container, phase: "testEditDuringUploadRefusesCommit-fetch-enter")\n        let entry = try! context.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.id == "j-local" })).first!\n            print("SYNC-MODEL-CAPTURE phase=testEditDuringUploadRefusesCommit-text-set-enter")\n','            let entry = try! context.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.id == "j-local" })).first!\n',1)
    s=s.replace('        captureSyncSchema(store.journalStore.container, phase: "testEditDuringUploadRefusesCommit-seed-enter")\n','',1)
    s=s.replace('private func captureSyncSchema(_ container: ModelContainer?, phase: String) {\n    print("SYNC-MODEL-CAPTURE phase=\\(phase) uptime=\\(ProcessInfo.processInfo.systemUptime)")\n    guard let container else { return }\n    for entity in container.schema.entities.prefix(8) {\n        print("SYNC-MODEL-SCHEMA entity=\\(entity.name) properties=\\(entity.properties.prefix(32).map(\\.name).joined(separator: ","))")\n    }\n}\n\n@MainActor\n','',1)
    return s
class SyncCrashCaptureContracts(unittest.TestCase):
    def test_original_operations_and_assertions_unchanged(self):
        s=restore_sync_crash_capture(normalize('source:AteTests/UserDataSyncTests.swift', (ROOT/"AteTests/UserDataSyncTests.swift").read_text()))
        self.assertEqual(hashlib.sha256(s.encode()).hexdigest(),'12b5852b8bdde8541b9d37a83c93c95b0735fafe77aac41bbc725d6a2d666d79')
