import Foundation
import QualiaKit

/// Manually advanced monotonic clock. Sleeping suspends until its deadline;
/// cancellation and advancement are serialized and resume each sleeper once.
public final class TestQualiaClock: QualiaClock, @unchecked Sendable {
    // All mutable state, including Ticket fields, is protected by `lock`.
    private final class Ticket: @unchecked Sendable {
        enum Condition { case deadline(Duration), sleepCount(Int) }
        let condition: Condition
        var cancelled = false
        var continuation: CheckedContinuation<Void, Error>?
        init(_ condition: Condition) { self.condition = condition }
    }

    private let lock = NSLock()
    private var instant: Duration
    private var tickets: [ObjectIdentifier: Ticket] = [:]

    public init(now: Duration = .zero) { instant = now }
    public var now: Duration { lock.lock(); defer { lock.unlock() }; return instant }
    public var pendingSleepCount: Int { lock.lock(); defer { lock.unlock() }; return sleeperCount }

    public func advance(by duration: Duration) throws {
        lock.lock()
        guard duration >= .zero else { lock.unlock(); throw QualiaTestingError.nonMonotonicTime }
        instant += duration
        let ready = takeReady()
        lock.unlock()
        ready.forEach { $0.resume() }
    }

    public func advance(to value: Duration) throws {
        lock.lock()
        guard value >= instant else { lock.unlock(); throw QualiaTestingError.nonMonotonicTime }
        instant = value
        let ready = takeReady()
        lock.unlock()
        ready.forEach { $0.resume() }
    }

    public func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        guard duration > .zero else { return }
        try await wait(Ticket(.deadline(now + duration)))
    }

    /// Scheduling barrier for tests: advance time only after the requested
    /// number of sleeps is registered. This wait itself is cancellable.
    public func waitUntilSleeping(count: Int = 1) async throws {
        guard count > 0 else { throw QualiaTestingError.invalidWaitCount }
        try await wait(Ticket(.sleepCount(count)))
    }

    public func cancelAll() {
        lock.lock()
        let pending = Array(tickets.values)
        tickets.removeAll()
        let continuations = pending.compactMap { ticket -> CheckedContinuation<Void, Error>? in
            ticket.cancelled = true
            defer { ticket.continuation = nil }
            return ticket.continuation
        }
        lock.unlock()
        continuations.forEach { $0.resume(throwing: CancellationError()) }
    }

    private func wait(_ ticket: Ticket) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { install(ticket, continuation: $0) }
            try Task.checkCancellation()
        } onCancel: { self.cancel(ticket) }
    }

    private func install(_ ticket: Ticket, continuation: CheckedContinuation<Void, Error>) {
        lock.lock()
        guard !ticket.cancelled, !Task.isCancelled else {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        ticket.continuation = continuation
        tickets[ObjectIdentifier(ticket)] = ticket
        let ready = takeReady()
        lock.unlock()
        ready.forEach { $0.resume() }
    }

    private func cancel(_ ticket: Ticket) {
        lock.lock()
        ticket.cancelled = true
        tickets.removeValue(forKey: ObjectIdentifier(ticket))
        let continuation = ticket.continuation
        ticket.continuation = nil
        lock.unlock()
        continuation?.resume(throwing: CancellationError())
    }

    private var sleeperCount: Int {
        tickets.values.filter { if case .deadline = $0.condition { return true }; return false }.count
    }

    private func takeReady() -> [CheckedContinuation<Void, Error>] {
        let count = sleeperCount
        let ready = tickets.filter { _, ticket in
            switch ticket.condition {
            case .deadline(let deadline): return deadline <= instant
            case .sleepCount(let target): return count >= target
            }
        }
        return ready.compactMap { id, ticket in
            tickets.removeValue(forKey: id)
            defer { ticket.continuation = nil }
            return ticket.continuation
        }
    }
}
