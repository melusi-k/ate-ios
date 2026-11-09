import Foundation

/// Archive-side nested entry, implemented by slice A (ArchiveNestedGenerationBoundary).
/// Nested mode runs UNDER the caller's held account-gate effect: it must NOT open or
/// flock any lock file and holds no lifetime lease. It validates the durable generation
/// chain on entry and commits exactly one generation after a successful covered unit.
/// A throwing work commits nothing. Read-only capture never goes through this entry:
/// reads must not advance the generation (wrap them in the account-gate effect only).
/// Reentrant: an empty nested call inside an outer one re-validates and runs.
protocol ArchiveNestedLeaseBoundary {
    func withNestedLease<T>(_ work: () throws -> T) throws -> T
}

/// Production composition of the shared writer boundary for the unified Journal graph
/// (#245, slice B). Lock order (Shape A, agreed with central/A 2026-11-09): account
/// gate OUTER (shared flock writer-gate-v1.lock + UUID writer epoch + durable
/// reset-control check), archive generation boundary INNER (no flock; validation plus
/// one generation commit per committed unit). Exactly one lock file is flocked, so
/// ordinary effects, standalone archive import sessions and reset attempts are mutually
/// exclusive by the OS across the app and its extensions. TOCTOU-free: every epoch or
/// control mutation takes the same flock the effect is validated under.
///
/// The returned closure originates from MainActor composition, is synchronous, and must
/// not suspend or escape its effect. FoodJournalWriterBoundary wraps it for app use.
@MainActor
enum JournalWriterBoundaryComposition {
    static func makePerform(
        gate: AccountWriterGate,
        writerLease: UUID,
        archive: ArchiveNestedLeaseBoundary
    ) -> (() throws -> Void) throws -> Void {
        return { effect in
            try gate.withWriterEffect(writerLease) {
                try archive.withNestedLease { try effect() }
            }
        }
    }

    /// Validation-only form for call sites that re-prove the boundary without an effect
    /// (e.g. per-component validation inside one larger composed effect). Nesting is
    /// supported: the account gate reuses the held lock for the same lease.
    static func makeValidator(
        gate: AccountWriterGate,
        writerLease: UUID,
        archive: ArchiveNestedLeaseBoundary
    ) -> () throws -> Void {
        let perform = makePerform(gate: gate, writerLease: writerLease, archive: archive)
        return { try perform({}) }
    }
}
