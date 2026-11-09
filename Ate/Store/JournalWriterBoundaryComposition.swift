import Foundation

// ArchiveNestedLeaseBoundary is declared ONCE in A's ArchiveLeaseBoundary.swift
// (authoritative). Contract recap: nested mode runs UNDER the caller's held
// account-gate effect - no lock file, no lifetime lease; it validates the durable
// generation chain on entry and commits exactly one generation after a successful
// covered unit; a throwing work commits nothing; read-only capture never goes
// through it; reentrant.

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
    /// (e.g. per-component validation inside one larger composed effect). This NEVER
    /// enters the archive boundary: an empty covered unit would still commit one
    /// archive generation, and a nested validation inside an active outer lease could
    /// stamp a second generation and go stale. The account gate's validateWriter is
    /// itself non-mutating (a flock cycle + durable epoch/control check) and reuses
    /// the held lock for the same lease.
    static func makeValidator(
        gate: AccountWriterGate,
        writerLease: UUID,
        archive: ArchiveNestedLeaseBoundary
    ) -> () throws -> Void {
        _ = archive   // archive chain re-validation happens inside real effects only
        return { try gate.validateWriter(writerLease) }
    }
}
