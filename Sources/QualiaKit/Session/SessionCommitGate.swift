import Foundation

struct SessionCommit: Sendable {
    let response: QualiaResponse
    let context: SessionContext?
    let acceptedID: QualiaInputID
}

/// Immutable storage makes retained-context lifetime testable without exposing
/// sensitive text through a public snapshot or diagnostics.
final class SessionContext: Sendable {
    let fragments: [QualiaContextFragment]
    init(_ fragments: [QualiaContextFragment]) { self.fragments = fragments }
}

/// The sole cross-actor synchronization point. The session owns semantic state;
/// MainActor leaves one committed receipt for the actor to absorb before its
/// next operation. begin() atomically drains that receipt AND invalidates older
/// work, so a dispatch cannot slip between draining state and starting a request.
/// No lock is held across await. Only synchronous pure reduction/policy and one
/// renderer command batch run inside commit(); diagnostic callbacks run outside.
final class SessionCommitGate: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var cancelled = false
    private var committedGeneration: UInt64?
    private var receipt: SessionCommit?

    func begin() -> (generation: UInt64, receipt: SessionCommit?) {
        lock.lock()
        defer { lock.unlock() }
        precondition(generation < .max, "Session generation overflow")
        generation += 1
        cancelled = false
        defer { receipt = nil }
        return (generation, receipt)
    }

    func takeReceipt() -> SessionCommit? {
        lock.lock()
        defer { lock.unlock() }
        defer { receipt = nil }
        return receipt
    }

    func isCurrent(_ expected: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return generation == expected && !cancelled
    }

    func cancel(_ expected: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        if generation == expected, committedGeneration != expected { cancelled = true }
    }

    func commit(_ expected: UInt64, _ body: () throws -> SessionCommit) throws -> QualiaResponse {
        lock.lock()
        defer { lock.unlock() }
        guard generation == expected, !cancelled, committedGeneration != expected else {
            throw CancellationError()
        }
        let result = try body()
        receipt = result
        committedGeneration = expected
        return result.response
    }

    func lifecycle(_ expected: UInt64, _ body: () throws -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        guard generation == expected else { throw CancellationError() }
        try body()
    }
}
