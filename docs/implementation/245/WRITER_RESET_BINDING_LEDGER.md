# Activation writer/reset binding ledger

Source review at347e7cf8, graph route still OFF. This is a list of work and evidence
requirements, not confirmation that activation is safe. No production operation was
performed. Source comments that call a design approved are not execution authority.

## Retained graph and auth

| Surface | Actual source | Required before activation |
| --- | --- | --- |
| Startup resources | FoodJournalProductionAdmission, FoodJournalDiskResources, FoodJournalAppGraph | Same strict snapshot/owner/receipt proof and original lease; no ordinary constructor before admission. Retained ModelContainers disable autosave. Existing AteApp still constructs legacy AppStore before any of these. |
| Session change | AppStore.setSession in AppStore.swift | Sign-in, same-owner sign-out/relogin, callback, expiry and refresh need explicit epoch semantics. Current setSession writes session/Keychain/watch but does not invalidate writer epoch or retire/remount graph. A refresh may not silently authorize pending work. |
| Late startup completion | ResetAwareStartup |1d2b7e83 adds terminal retire and run identity; full host must call it after fencing, clear all graph references and separately reconcile a replacement. No implicit retry. |
| Global current store | AppStore.current | Weak but must clear/rebind on retirement; no old consumer may use a replacement graph through this global to finish old work. |
| Shared app boundary | SharedWriterBoundary.install/current in SharedWriterGate.swift | One-way install currently prevents production replacement. Need retained per-graph adapters or a qualified replacement protocol, never a fresh current lookup after an await. |
| Account conflict | GenerationFencedSyncService, AccountWriterGate, SharedFileWriterGate |c4a3c051 plus20fb287b persist/block on common marker. Host still needs actual quiescence/unmount and observable conflict state. IO failure cannot promise durable cross-process fencing. No unblock API. |

## Producers and writers

| Producer | Actual source / bound state | Remaining qualification |
| --- | --- | --- |
| Sync debounce and explicit sync | AppStore.scheduleSync/syncNow, GenerationFencedSyncService | Original capture retained, no direct fallback, concurrent guard, PT409 invalidates/block. Need cancel/join debounce and all sync calls at retirement; old requests may finish on server but must not publish locally. |
| Delayed shopping undo, callbacks, deep-link fetch | AppStore.swift Tasks | Track/join or prove original lease/session after every await; no reroute through new graph. Timer-based UI messages are not proof all personal producers stopped. |
| Cover download/generation | CoverStore.swift | shared singleton has mutable boundary/validator and Task in ensure. Post-await reading its *current* binding can bless old output after remount. Retain original binding through resolve/generate/save and publishing; stop/join pending work. Cache/loading/attempted are personal derivative state to clear. |
| Watch mirror | PhoneWatchBridge.swift | update(session/timers) gated, but activationDidComplete calls push outside boundary and can resend cached session. Must gate republish and clear cached state. Phone cannot verify watch-device cleanup. |
| Widget debounce / Spotlight | WidgetBridge.swift | publishTask/indexTask are static. Cancel/join; capture original boundary before debounce; clear publisher cache/lastIndexed; retire IntentRelay closures. Spotlight OS calls need completion verification after any in-flight add. |
| Shared widget queues/timers | SharedWidgets/WidgetShared.swift, TimerIntents.swift, SharedContainer.swift | Install SharedFileWriterGate before ANY extension access. Current defaults are legacy until installed. Same immutable control directory/reset reader/archive chain. Publish/queue claims must reflect refused effects. |
| Share image + queue | AteShare/ShareViewController.swift, SharedInbox.swift |57d376e0 retains boundary before provider await and gates bytes+queue/consume deletion. Still needs extension gate install and quiescence; orphan images must be erased, not only referenced queue files. |
| Draft recovery | DraftStore.swift | begin/end/saveDraft/clear write UserDefaults directly, no boundary. Add a retained graph writer binding and original-operation capture; AddRecipeSheet generation completion must not save a draft after reset. |
| Manual Journal/media + food meals/goals | JournalSuggestionService.swift, FoodJournalRuntime/Coordinator, NutritionGoalsRepository | Runtime boundary covers canonical writes. Journal media writer uses static JournalStore.mediaDir. Archive's mediaDirectory injection must equal actual writer path or refuse activation; no silently different export/reset location. |
| Timer / Live Activity | TimerCenter.swift | Timer effects have boundary seam, but async ActivityKit requests/updates and permission tasks need retirement checks and join/verified end. Stopping arrays alone is insufficient. |
| Cook plan notifications | CookPlanNotifications.swift | Ordered tail/generation prevents late adds when cancelAll is queued. Actual reset must await queue drain and verification, not merely remove pending notifications once. |
| Diagnostic / Health / QA / insights | DiagnosticHistory, HealthKitService, BetaQA, InsightLifecycleStore | Global/defaults writers and async reads must be stopped or fenced; no post-erase recreation. OS Health permissions are not app data and cannot be reset by deleting a key. No claim to erase HealthKit records outside app ownership. |

## Erase inventory: personal bytes vs minimal controls

| Location | Owner/source | Erase / preserve policy needed |
| --- | --- | --- |
| Recipe/shopping rows | Actual retained recipe ModelContainer | Raw rows, not filtered arrays. Verify fresh context empty; nil/unavailable is failure. Store files require explicit path/recovery state, no global fallback. |
| Journal rows and raw payloads | JournalLocalReset retained in graph347e7cf8 | Raw orphan/future/corrupt payload rows, exact named-store path, durable state checks. Refuse missing retained inventory before any local wipe. |
| Journal media, legacy/corrupt diary backups, adoption preservation, goals file | Injected retained paths / actual Journal media writer | Erase complete owned directories including orphans, verify empty; exact roots, not inferred defaults. Preservation is personal, not control. |
| Recipe recovery Backups folder | StoreRecovery.moveAside | Sibling Backups/ate-TIMESTAMP.store plus wal/shm carry personal data. Exact owned directory scope required; cannot erase unrelated stores. |
| Recovery JSON exports | StoreRecovery.exportRecovered | Documents/Ate-recovered-TIMESTAMP.json; enumerate exact app-owned matching regular files, verify removal. Never delete all Documents. |
| Temporary export and imported media | SettingsView.writeTemp / archive import | ate-data.json, share/recovery temp paths and .ate-restore-* staging carry personal data. User-saved external export copies are outside app sandbox erase and must not be claimed erased. |
| Covers + Inbox | CoverStore.folder; SharedInbox.folder | Entire exact roots including orphan files; no App Group→standard fallback in activated shared mode. |
| Standard and shared defaults | ClearAllDataKeys, runtime defaults and actual shared suite | Explicit keys/prefixes, strict absence checks. Current list intentionally omits ate.sync.v1; account-wide reset must explicitly erase old stamps/tombstones/owner metadata only after fencing and verified new generation receipt. No blanket removePersistentDomain/ate.* wildcard. |
| Archive txn-* and .resolved-* | DiskArchiveRecoveryJournal in SAME control directory | BOTH hold personal before/after images. retire() only renames to .resolved-UUID, it does not erase bytes. Resolve/verify unresolved transactions before normal reset, then erase personal recovery records under qualified reset protocol. Blanket preserve or blanket delete of control directory is wrong. |
| Lock/epoch/generation chain/reset-control/owner-generation receipt/conflict marker | AccountWriterGate, SharedArchiveWriterLease, FileResetControlPersistence | Minimal nonpersonal coordination records. Preserve lock inode and generation continuity. Never erase pending reset UUID or conflict fence to make startup succeed. Archive record payloads above are NOT minimal controls. |
| Keychain session/PKCE | Auth.swift Keychain / SupabaseAuth | Separate identity policy: clearing account data is not account deletion/sign-out. Keep only needed credentials; current Keychain.save ignores Security status, so no verified credential erasure claim without status/readback binding. |
| Widgets/notifications/Live Activities/Spotlight/watch | SystemSurfaceCleanup | Actual timer/bridge/defaults instances plus reset-gate validator. Current normal timer writer boundary will refuse after reset-gate epoch change, so injecting it blindly cannot clean in-memory producers. Need reset-authorized cleanup adapter, all awaited calls verified. Watch delivery not verifiable from phone; report scope truthfully. |

## Settings and recovery stop gates

Current Settings Clear all calls clearLibrary() and reports Library cleared. Unified
clearLibraryUnified intentionally does NOT clear meals/Journal. Do not relabel this
as account-wide success. Full binding needs: original owner/session capture; producer
quiescence; strict full inventory before effects; durable UUID+generation control;
server receipt verification; local erase and independent verification; minimal receipt
handoff; control retirement; qualified replacement graph. Partial/unknown outcomes
stay closed with retained control. No new reset UUID or legacy sync action can stand
in for recovery. User confirmation/UI tests need normal iPhone18 Pro acceptance.

Native/device validation is still required for exact-head lifecycle races, reset
resume/partial IO, cross-process extension writes, auth remount, visible conflict and
Settings copy. Python/static tests are not evidence those behaviors work.
