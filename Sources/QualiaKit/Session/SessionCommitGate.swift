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

/// A request's cancellation/commit boundary. This lock only protects the signal:
/// it is never held while invoking renderer code or cancelling another task.
/// Once commit is claimed, synchronous cancellation from a renderer callback
/// cannot roll it back or wait for the gate that is executing that callback.
final class SessionCancellation: @unchecked Sendable {
    private enum State { case pending, cancelled, committing }
    private let lock = NSLock()
    private var state = State.pending

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return state == .cancelled
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        if state == .pending { state = .cancelled }
    }

    func beginCommit() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard state == .pending else { return false }
        state = .committing
        return true
    }
}

/// Cross-actor admission and state synchronization. The session owns semantic state;
/// MainActor leaves one committed receipt for the actor to absorb before its
/// next operation. Admission checks that receipt before invalidating older work,
/// so a rejected duplicate cannot supersede an unrelated request in flight.
/// No lock is held across await. Only synchronous pure reduction/policy and one
/// renderer command batch run inside commit(); diagnostic callbacks run outside.
final class SessionCommitGate: @unchecked Sendable {
    struct Request: Sendable {
        let generation: UInt64
        let cancellation: SessionCancellation
        let receipt: SessionCommit?
    }

    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var cancellation = SessionCancellation()
    private var receipt: SessionCommit?

    func begin() -> Request {
        lock.lock()
        defer { lock.unlock() }
        return advance()
    }

    func begin(accepting id: QualiaInputID, lastAcceptedID: QualiaInputID?, context: SessionContext?) throws -> Request {
        lock.lock()
        defer { lock.unlock() }
        // An unabsorbed receipt replaces the actor's entire accepted state,
        // including nil context when the retained window has become empty.
        let acceptedID: QualiaInputID?
        let acceptedContext: SessionContext?
        if let receipt {
            acceptedID = receipt.acceptedID
            acceptedContext = receipt.context
        } else {
            acceptedID = lastAcceptedID
            acceptedContext = context
        }
        guard acceptedID != id,
              !(acceptedContext?.fragments.contains(where: { $0.id == id }) ?? false) else {
            throw QualiaSessionError.duplicateInput
        }
        return advance()
    }

    /// Called only while holding the gate lock, after successful admission.
    private func advance() -> Request {
        precondition(generation < .max, "Session generation overflow")
        generation += 1
        cancellation = SessionCancellation()
        defer { receipt = nil }
        return Request(generation: generation, cancellation: cancellation, receipt: receipt)
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
        return generation == expected && !cancellation.isCancelled
    }

    func commit(_ expected: UInt64, _ body: () throws -> SessionCommit) throws -> QualiaResponse {
        lock.lock()
        defer { lock.unlock() }
        guard generation == expected, cancellation.beginCommit() else {
            throw CancellationError()
        }
        let result = try body()
        receipt = result
        return result.response
    }

    func lifecycle(_ expected: UInt64, _ body: () throws -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        guard generation == expected else { throw CancellationError() }
        try body()
    }
}
