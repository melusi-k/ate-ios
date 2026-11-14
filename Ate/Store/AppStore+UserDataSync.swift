import Foundation

/// Issue #34: sync all user data (Food Journal, insight states, nutrition goals) to
/// Supabase, in addition to the recipes/shopping sync `syncNow()` already runs.
/// Insight states are DORMANT in this slice (Reviewer, #34 split): journal + goals land
/// durable; insight sync waits on a crash-durable InsightLifecycleStore - see the doc.
///
/// Contract: docs/implementation/34_USER_DATA_SYNC.md.
///
/// Boundaries:
/// - Family sync runs only after the recipe/shopping round succeeded and reuses its
///   session. `syncNow` AWAITS the family round, so a slow family round extends that
///   call's completion after `syncState` is already `.synced`; family failures land on
///   `userDataSyncStatus` only - they never change `syncState`, and Library/Cook are never
///   blocked by them.
/// - Design constraint: families write ONLY through the fenced unified graph. When
///   `foodJournalRuntime` is nil (legacy graph), families stay local-only: the only write
///   route there would be an unfenced RPC writer beside the admitted one. The host binds
///   `userDataSyncTransport` (a `FencedUserDataSyncTransport`) when it builds the unified
///   graph, sharing ONE `SyncCycleGate` with the recipe/shopping transport so the two
///   cycles can never interleave; an unbound seam means the round is skipped, never
///   unfenced.
/// - Publication order inside a round (Reviewer): replay any interrupted earlier commit
///   (durable redo journal, fail-closed), validate the WHOLE snapshot strictly, stage
///   every family's proposal (plan + decode + expected-image, no local mutation), run the
///   authorized batch upload, revalidate the cycle (gate + session + generation), and only
///   then publish locally through `FamilySyncCommitJournal` - the #532 commit-journal
///   discipline: the commit's second local read runs inside the admitted boundary BEFORE
///   anything is recorded, then the complete target (store after-images + family metadata
///   after-image, bound to owner + generation receipt) is journaled durably (atomic,
///   fsync'd, checksummed) and every store is driven to it idempotently. An interrupted
///   commit is COMPLETED by replay at the next round, never rolled back; a corrupt,
///   foreign or stale-epoch intent blocks the round and preserves the evidence. A refused
///   or revoked writer leaves content AND stamps unchanged; a failed upload publishes
///   nothing locally.
/// - The backend may predate the new kinds; production migration stays file-only until
///   the owner explicitly applies it. 23514 / missing RPC contract => that round is
///   local-only; nothing is written, deleted or presented as synced.
/// - Account ownership follows `SyncMerge.isAccountSwitch`: family stamps/tombstones live in
///   `meta` and are reset on account switch together with the recipe/shopping ones, so one
///   account's rows never merge into another account.
extension AppStore {
    /// A generation change means the server epoch these stamps were merged against is
    /// gone (reset elsewhere). Old-epoch stamps/scope must not confirm or re-plan
    /// anything: the next round re-baselines from a fresh snapshot. The cleared metadata
    /// goes through the journal's authority when one is bound (UserDefaults stays a
    /// projection); a pending old-epoch intent is NOT touched - it keeps refusing replay
    /// until the reset composition erases the journal directory.
    private func clearFamilySyncStateForNewEpoch() {
        var cleared = meta.familySyncMetadata(ownerID: session?.userID
            ?? meta.journalScope?.ownerID ?? meta.insightScope?.ownerID
            ?? meta.goalsScope?.ownerID ?? "")
        cleared.journalStamps = nil; cleared.journalTombs = nil
        cleared.insightStamps = nil; cleared.insightTombs = nil
        cleared.goalsStamps = nil; cleared.goalsTombs = nil
        cleared.goalsSyncedPayload = nil
        cleared.journalScope = nil; cleared.insightScope = nil; cleared.goalsScope = nil
        if let journal = familySyncCommitJournal,
           let scope = userDataSyncTransport?.currentScope,
           scope.ownerID == cleared.ownerID {
            try? journal.resetMetadata(cleared, receipt: AccountGenerationPolicy.Receipt(
                ownerID: scope.ownerID, generation: scope.generation))
        } else if familySyncCommitJournal == nil {
            // No journal: no commit could have recorded authority; clear directly.
            try? performOrdinaryWriteThrowing {
                meta.applyFamilySyncMetadata(cleared)
                saveDefaults(meta, key: "ate.sync.v1")
            }
            return
        }
        meta.applyFamilySyncMetadata(cleared)
    }

    /// One sync round for every new family. Called at the end of a successful `syncNow()`.
    func syncUserDataFamilies() async {
        let enabled = userDataSyncEnabledOverride ?? AppConfig.userDataSyncEnabled
        guard enabled, !AppConfig.isUITesting else { return }
        guard let s = session else { return }
        // Legacy graph: local-only by design (see header).
        guard foodJournalRuntime != nil else { return }
        guard let transport = userDataSyncTransport else {
            userDataSyncStatus = .unavailable("family sync host seam is not bound")
            return
        }
        guard let journal = familySyncCommitJournal else {
            userDataSyncStatus = .unavailable("family sync commit journal is not bound")
            return
        }
        do {
            let failures = try await transport.cycle(session: s) { snapshot, pushBatch, revalidate -> [String] in
                // The session captured by syncNow may have moved on before the cycle opened.
                guard session?.userID == s.userID else { return ["session changed during sync"] }

                // Strict replay of an interrupted earlier commit BEFORE staging, so this
                // round plans from a consistent local base. A replay refusal (corrupt,
                // foreign-owner or stale-epoch intent) fails the round BEFORE anything new
                // is planned over it.
                if let projected = try journal.recoverAndProject() {
                    meta.applyFamilySyncMetadata(projected)
                }

                // Strict whole-snapshot validation BEFORE any local write or upload: a
                // malformed or inconsistent remote row rejects the round outright.
                try RemoteSnapshotValidator.validate(rows: snapshot.rows)

                // Stage every family: plan + decode + expected-image, no local mutation yet.
                // A family that stages successfully confirms under THIS round's scope; a
                // failed family keeps its carried-over (older) scope and stamps, so the
                // commit never promotes stale confirmations into the new owner/epoch.
                let roundScope = AccountDataScope(ownerID: s.userID, generation: snapshot.generation)
                var verifies: [() throws -> Void] = []
                var afterImages = FamilySyncCommitJournal.Images()
                var beforeImages = FamilySyncCommitJournal.Images()
                var familyMeta = meta.familySyncMetadata(ownerID: s.userID)
                var push: [SyncRecord] = []
                var failures: [String] = []
                for family in UserDataFamily.allCases {
                    // Insight states are DORMANT (Reviewer, #34 split): InsightLifecycleStore
                    // is UserDefaults-volatile, and neither a post-commit repair image nor
                    // LWW projection can make its confirmed states crash-durable without a
                    // durable store or local tombstones (see the #34 doc follow-ups). The
                    // family keeps its wire/migration surface but no round stages it.
                    if family == .insight { continue }
                    do {
                        switch family {
                        case .journal:
                            let staging = try stageJournalFamily(snapshot: snapshot, session: s, push: &push)
                            verifies.append(staging.verify)
                            afterImages.journal = staging.image
                            if staging.image != nil { beforeImages.journal = staging.before }
                            familyMeta.journalStamps = staging.stamps
                            familyMeta.journalTombs = staging.tombstones
                            familyMeta.journalScope = roundScope
                        case .goals:
                            let staging = try stageGoalsFamily(snapshot: snapshot, session: s, push: &push)
                            verifies.append(staging.verify)
                            afterImages.goals = staging.image
                            if staging.image != nil { beforeImages.goals = staging.before }
                            familyMeta.goalsStamps = staging.stamps
                            familyMeta.goalsTombs = staging.tombstones
                            familyMeta.goalsSyncedPayload = staging.syncedPayload
                            familyMeta.goalsScope = roundScope
                        case .insight:
                            break // unreachable: skipped above (dormant)
                        }
                    } catch let e as UserDataSyncError {
                        if e == .generationChanged {
                            // The account was cleared elsewhere mid-round: discard the staged
                            // proposals; the next sync re-snapshots fresh.
                            throw e
                        }
                        failures.append("\(family.kind): \(e.errorDescription ?? "")")
                    } catch {
                        failures.append("\(family.kind): \(error.localizedDescription)")
                    }
                }

                // Authorized upload FIRST. Local publication happens only after it succeeds.
                if !push.isEmpty {
                    do {
                        try await pushBatch(push)
                    } catch {
                        let e = UserDataSyncError.classify(error)
                        if e == .generationChanged { throw e }
                        if case .familyUnavailable = e { userDataSyncBackendUnavailable = true }
                        // Staged proposals are discarded: nothing is published locally from a
                        // round whose upload did not complete.
                        failures.append("push: \(e.errorDescription ?? "")")
                        return failures
                    }
                }
                userDataSyncBackendUnavailable = false

                // Re-prove gate + session + generation before ANY local write: a reset or
                // account change mid-cycle must leave local content untouched.
                try revalidate()

                // ONE journaled commit for every local apply plus the metadata write. The
                // second local read runs inside the admitted boundary before the intent is
                // recorded; after that the recorded target is driven to completion now or
                // by replay - never rolled back.
                do {
                    let projected = try journal.commit(FamilySyncCommitJournal.Commit(
                        receipt: AccountGenerationPolicy.Receipt(ownerID: s.userID,
                                                                 generation: snapshot.generation),
                        metadata: familyMeta,
                        before: beforeImages,
                        after: afterImages,
                        verify: { for verify in verifies { try verify() } }))
                    meta.applyFamilySyncMetadata(projected)
                } catch {
                    let e = UserDataSyncError.classify(error)
                    failures.append("commit: \(e.errorDescription ?? "")")
                }
                return failures
            }
            userDataSyncStatus = failures.isEmpty ? .synced : .unavailable(failures.joined(separator: " | "))
        } catch {
            let e = UserDataSyncError.classify(error)
            if case .familyUnavailable = e { userDataSyncBackendUnavailable = true }
            if e == .generationChanged { clearFamilySyncStateForNewEpoch() }
            userDataSyncStatus = .unavailable(e.errorDescription ?? "")
        }
    }

    // MARK: - Food Journal

    /// Stages the journal family; appends the rows the batch push must send to `push` and
    /// returns the second-local-read check, the pre-commit image the journal admits replay
    /// from, and the COMPLETE post-merge image it drives the store to (nil when the round
    /// changes nothing locally).
    private func stageJournalFamily(snapshot: AccountSnapshot, session s: AuthSession,
                                    push: inout [SyncRecord])
        throws -> (verify: () throws -> Void, before: [JournalEntrySyncPayload],
                   image: [JournalEntrySyncPayload]?,
                   stamps: [String: Double], tombstones: [String: Double]) {
        let payloads: [JournalEntrySyncPayload]
        do {
            payloads = try JournalSyncBridge.export(container: journalStore.container)
        } catch {
            throw UserDataSyncError.transport("journal export failed")
        }
        let beforeByID = Dictionary(payloads.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let enc = JSONEncoder()
        var data: [String: Data] = [:]
        var stamps: [String: Double] = [:]
        for p in payloads {
            // An encoding failure fails the whole family rather than looking like a deletion.
            data[p.id] = try enc.encode(p)
            stamps[p.id] = Double(p.stampMs)
        }
        let local = UserDataSyncPlanner.localWithDeletes(
            data: data, stamps: stamps, tombstones: meta.journalTombs ?? [:],
            previouslySynced: meta.journalStamps ?? [:], now: nowMs())
        let plan = UserDataSyncPlanner.plan(kind: UserDataFamily.journal.kind, userID: s.userID,
                                            local: local,
                                            remote: snapshot.rows.filter { $0.kind == UserDataFamily.journal.kind })
        push += plan.push
        // Decode the remote winners now, while staging: a decode failure here means the
        // snapshot slipped past validation and fails the family before anything is written.
        let dec = JSONDecoder()
        var imageByID = beforeByID
        for id in plan.applyDeletes { imageByID.removeValue(forKey: id) }
        for (id, bytes) in plan.applyUpserts {
            imageByID[id] = try dec.decode(JournalEntrySyncPayload.self, from: bytes)
        }
        let image: [JournalEntrySyncPayload]? =
            (plan.applyUpserts.isEmpty && plan.applyDeletes.isEmpty) ? nil : Array(imageByID.values)
        let container = journalStore.container
        return (
            verify: {
                // Second local read (mirrors the #532 staged cycle): refuse the commit when
                // the family's local input changed during the upload, so a mid-upload edit
                // is never overwritten by a staged remote winner.
                let nowByID = try Dictionary(
                    JournalSyncBridge.export(container: container).map { ($0.id, $0) },
                    uniquingKeysWith: { a, _ in a })
                guard nowByID == beforeByID else {
                    throw UserDataSyncError.transport("journal changed during the upload")
                }
            },
            before: payloads,
            image: image,
            stamps: plan.stamps,
            tombstones: plan.tombstones
        )
    }

    // MARK: - Nutrition goals

    private func stageGoalsFamily(snapshot: AccountSnapshot, session s: AuthSession,
                                  push: inout [SyncRecord])
        throws -> (verify: () throws -> Void, before: DailyNutritionGoals, image: DailyNutritionGoals?,
                   stamps: [String: Double], tombstones: [String: Double], syncedPayload: Data?) {
        let goals: DailyNutritionGoals
        do {
            goals = try journalGoalsRepository.load()
        } catch {
            // A corrupt/in-flight goals store must never sync as empty; try again next round.
            throw UserDataSyncError.transport("goals unreadable")
        }
        let enc = JSONEncoder()
        var data: [String: Data] = [:]
        var stamps = meta.goalsStamps ?? [:]
        if !goals.isEmpty {
            let bytes = try enc.encode(goals)
            data[UserDataSyncID.goals] = bytes
            // Goals carry no updatedAt of their own; a byte change against the last synced
            // payload is the local edit signal and moves the LWW stamp.
            if meta.goalsSyncedPayload != bytes || stamps[UserDataSyncID.goals] == nil {
                stamps[UserDataSyncID.goals] = nowMs()
            }
        }
        let local = UserDataSyncPlanner.localWithDeletes(
            data: data, stamps: stamps, tombstones: meta.goalsTombs ?? [:],
            previouslySynced: meta.goalsStamps ?? [:], now: nowMs())
        let plan = UserDataSyncPlanner.plan(kind: UserDataFamily.goals.kind, userID: s.userID,
                                            local: local,
                                            remote: snapshot.rows.filter { $0.kind == UserDataFamily.goals.kind })
        push += plan.push
        let dec = JSONDecoder()
        // Include the complete target even on push-only/no-delta rounds: confirmation
        // may retire only after the existing file (or empty-target deletion) is sealed.
        var image: DailyNutritionGoals? = goals
        if let bytes = plan.applyUpserts[UserDataSyncID.goals] {
            image = try dec.decode(DailyNutritionGoals.self, from: bytes)
        } else if plan.applyDeletes.contains(UserDataSyncID.goals) {
            image = DailyNutritionGoals(energyKcal: nil, proteinGrams: nil, carbohydratesGrams: nil,
                                        fatGrams: nil, fibreGrams: nil)
        }
        let repository = journalGoalsRepository
        return (
            verify: {
                let current: DailyNutritionGoals
                do {
                    current = try repository.load()
                } catch {
                    throw UserDataSyncError.transport("goals changed during the upload")
                }
                guard current == goals else {
                    throw UserDataSyncError.transport("goals changed during the upload")
                }
            },
            before: goals,
            image: image,
            stamps: plan.stamps,
            tombstones: plan.tombstones,
            syncedPayload: plan.data[UserDataSyncID.goals]
        )
    }
}
