# Food Journal activation, stage 3: concrete archive consumers

Incremental base 1a948a7818745597b04e8af78882a7b698055abd. Part of #245.

FoodJournalArchiveConsumers supplies the required stage-1 callback pair using the
actual runtime, recipe container, media and control directories. This is not a
second archive format or replay implementation: capture/import/recovery use the
existing UnifiedArchive services. Production factory/root wiring remains pending.

Export runs real migration/goals preparation as covered writes, then captures an
immutable snapshot under the account gate without advancing the archive generation.
Media loads outside the gate. Reacquired original epoch, owner and exact archive
generation must still match before returning bytes; unresolved recovery refuses.

Import validates the whole file before migration, then runs one journaled import
inside the already-held account gate with a no-flock nested archive lease. It must
not reacquire the same lock through the standalone session or enter the ordinary
boundary for an extra generation. It advances once after commit and retires only
after that advance, preserving the existing crash-recovery protocol. Failed import
retains recovery evidence. Added counts include Journal entries rather than claiming
that a successful reflection-only import was "Data up to date".

Two native tests exercise actual stores/export/additive retry and invalid-file/stale
lease refusal. They are written but UNRUN. No old tests or timeout changes. Diff
check PASS. Native build, Darwin locks, process-death/reopen and device proof remain
required. Stage 1 infrastructure Python checks are not native archive proof.

Remaining integration requirements: reload the live AppStore view state after a
successful import, bind owner validation to production admission/auth lifecycle,
run archive startup recovery before ordinary constructors, bind full reset surfaces,
and mount only a complete production graph. No route switch is included here.

Rollback: revert this stage before routing changes. Once used, preserve imported
canonical bytes and recovery journal; never retire failed/unverified transactions
or restore legacy data as rollback. Stage 1/2 rollback notes still apply.
