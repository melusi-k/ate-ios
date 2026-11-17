import Foundation
import CryptoKit

/// Journal-local scope only. Settings/account routes call this inside their actual
/// writer effect. It does not clear a cloud account or activate the dormant graph.
@MainActor
extension AppStore {
    /// Minimal account-scope control survives expiry and app relaunch even if the
    /// account has never completed a recipe sync. Never store an email or raw ID.
    static func journalOwnerFingerprint(for owner: String) -> String {
        SHA256.hash(data: Data(owner.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    var journalOwnerFingerprint: String? {
        get { (foodJournalRuntime?.defaults ?? nutritionDiaryForReset.defaults).string(forKey: "ate.journal.owner.v1") }
        set {
            let defaults = foodJournalRuntime?.defaults ?? nutritionDiaryForReset.defaults
            if let newValue { defaults.set(newValue, forKey: "ate.journal.owner.v1") }
            else { defaults.removeObject(forKey: "ate.journal.owner.v1") }
        }
    }
    enum JournalPersonalResetError: Error { case wrongOwner, incomplete }

    /// Shared actual-owner erase for Clear all, explicit sign-out and account switch.
    /// Never called by token expiry or same-account token refresh.
    @discardableResult
    func eraseJournalPersonalData() throws -> ClearAllLocalData.Report {
        if foodJournalRuntime != nil && (journalWriterEffect == nil || journalWriterValidator == nil) {
            throw JournalPersonalResetError.wrongOwner
        }
        let validate: () throws -> Void = journalWriterValidator ?? {}
        try validate()
        let defaults = foodJournalRuntime?.defaults ?? nutritionDiaryForReset.defaults
        let journal = journalStore
        let inventory = journalPersonalResetInventory ?? JournalLocalReset(
            journal: journal, defaults: defaults, goalsStorage: journalGoalsRepository.storage,
            mediaDirectory: JournalStore.mediaDir,
            migrationBackupDirectory: JournalLocalReset.defaultMigrationBackupDirectory,
            repairBackupDirectory: nutritionDiaryForReset.backupDirectory,
            preservationDirectory: journalResetPreservationDirectory,
            storeFileURL: JournalLocalReset.defaultStoreFileURL)
        guard inventory.journal === journal, inventory.defaults === defaults else {
            throw JournalPersonalResetError.wrongOwner
        }
        // Revoke old asynchronous publication before the first potentially partial erase.
        journalPersonalResetEpoch += 1
        InsightsModel.shared.resetForJournalErase()
        let (journalComponents, _) = try inventory.components(validateWriterGate: validate)
        // Goals are preferences, not Journal entries. Keep them for sign-out-keep;
        // the existing remove-all route resets them separately.
        var components = journalComponents.filter {
            $0.name != "nutrition-goals-file" && $0.name != "journal-diary-cook-defaults"
        }
        components.insert(ClearAllLocalData.Component(name: "journal-cooking-history-cache", erase: {
            try validate(); self.journalCookingHistory.clear()
        }, verifyEmpty: {
            guard self.journalCookingHistory.events.isEmpty else { throw ClearAllLocalData.Error.notEmpty }
        }), at: 0)
        components.append(ClearAllLocalData.defaults(name: "journal-diary-cook-defaults", store: defaults,
            keys: JournalLocalReset.journalDefaultsKeys.subtracting([DailyNutritionGoals.defaultsKey]),
            prefixes: JournalLocalReset.journalDefaultsPrefixes, validateWriterGate: validate))
        components.append(ClearAllLocalData.defaults(name: "journal-insight-lifecycle", store: defaults,
            keys: ["insights.lifecycle.v1"], prefixes: ["insights.lifecycle.v1.account."], validateWriterGate: validate))
        if let commits = familySyncCommitJournal {
            components.append(commits.clearAllComponent(validateResetGate: validate))
        }
        let report = try ClearAllLocalData.execute(components, requiredNames: Set(components.map(\.name)),
            validateWriterGate: validate)
        lastJournalPersonalResetReport = report
        // Even partial erasure must invalidate stale presented rows and editors.
        manualJournalHost = nil; manualJournalDraft = ""
        journalReflection = JournalReflectionDraft()
        cookJournalViewVisible = false; cookJournalModalDismissing = false
        cookedReflectionSessions.removeAll(); cookedReflectionPendingID = nil; cookedReflectionPresentedID = nil
        showNutritionDiary = false; showNutritionDiaryEntry = false
        trackerPath = []
        journalRevision += 1
        guard report.complete else { throw JournalPersonalResetError.incomplete }
        return report
    }
}
