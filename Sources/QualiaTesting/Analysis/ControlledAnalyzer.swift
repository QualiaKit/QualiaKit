import Foundation
import QualiaKit

/// Test-only analyzer whose invocations can be completed in any order. Request
/// numbers distinguish repeated input IDs, including across shared sessions.
/// Retains synthetic inputs in memory until `clearHistory()` is called.
public actor ControlledAnalyzer: QualiaAnalyzing {
    public enum CancellationBehavior: Sendable { case respect, ignore }

    public struct Request: Sendable {
        public let number: UInt64
        public let input: QualiaInput
    }

    public nonisolated let capabilities: QualiaAnalyzerCapabilities
    public nonisolated let identity: QualiaAnalyzerIdentity
    private let cancellationBehavior: CancellationBehavior
    private var nextNumber: UInt64 = 0
    private var history: [Request] = []
    private var pending: [UInt64: (Request, CheckedContinuation<QualiaObservation, Error>)] = [:]
    private var waiters: [UUID: (UInt64, CheckedContinuation<Request, Error>)] = [:]

    public init(capabilities: QualiaAnalyzerCapabilities, identity: QualiaAnalyzerIdentity,
                cancellationBehavior: CancellationBehavior = .respect) {
        self.capabilities = capabilities
        self.identity = identity
        self.cancellationBehavior = cancellationBehavior
    }

    public var requests: [Request] { history }
    public var pendingRequests: [Request] { pending.values.map(\.0).sorted { $0.number < $1.number } }

    public func analyze(_ input: QualiaInput) async throws -> QualiaObservation {
        precondition(nextNumber < .max, "ControlledAnalyzer request counter overflow")
        nextNumber += 1
        let request = Request(number: nextNumber, input: input)
        let observation = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { install(request, continuation: $0) }
        } onCancel: {
            Task { await self.cancel(request.number) }
        }
        if cancellationBehavior == .respect { try Task.checkCancellation() }
        return observation
    }

    /// A scheduling barrier, independent of wall time. Numbers are one-based
    /// and remain monotonic after history is cleared. Cancellation releases it.
    public func waitForRequest(number: UInt64) async throws -> Request {
        guard number > 0 else { throw QualiaTestingError.invalidWaitCount }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            if let request = history.first(where: { $0.number == number }) { return request }
            if number <= nextNumber { throw QualiaTestingError.unknownRequest(number) }
            return try await withCheckedThrowingContinuation { installWaiter(id, number: number, continuation: $0) }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    /// Raw completion also permits deliberately invalid observations for
    /// analyzer-contract tests. Unknown or already completed requests throw.
    public func complete(_ number: UInt64, with result: Result<QualiaObservation, Error>) throws {
        guard let entry = pending.removeValue(forKey: number) else {
            throw QualiaTestingError.unknownRequest(number)
        }
        entry.1.resume(with: result)
    }

    public func complete(_ number: UInt64, dimensions: QualiaDimensions = .init(),
                         signals: [QualiaSignal: QualiaScore] = [:]) throws {
        guard let request = pending[number]?.0 else { throw QualiaTestingError.unknownRequest(number) }
        guard let language = request.input.language else { throw QualiaTestingError.missingLanguage }
        try complete(number, with: .success(QualiaObservation(
            inputID: request.input.id, dimensions: dimensions, signals: signals,
            language: language, analyzer: identity
        )))
    }

    /// Explicit teardown releases all continuations, even in `.ignore` mode.
    public func cancelAll() {
        let calls = Array(pending.values)
        let observers = Array(waiters.values)
        pending.removeAll()
        waiters.removeAll()
        for call in calls { call.1.resume(throwing: CancellationError()) }
        for observer in observers { observer.1.resume(throwing: CancellationError()) }
    }

    public func clearHistory() { history.removeAll() }

    private func install(_ request: Request, continuation: CheckedContinuation<QualiaObservation, Error>) {
        history.append(request)
        if cancellationBehavior == .respect && Task.isCancelled {
            continuation.resume(throwing: CancellationError())
        } else {
            pending[request.number] = (request, continuation)
        }
        let ready = waiters.filter { $0.value.0 == request.number }
        for (id, observer) in ready {
            waiters.removeValue(forKey: id)
            observer.1.resume(returning: request)
        }
    }

    private func installWaiter(_ id: UUID, number: UInt64, continuation: CheckedContinuation<Request, Error>) {
        if Task.isCancelled { continuation.resume(throwing: CancellationError()) }
        else { waiters[id] = (number, continuation) }
    }

    private func cancel(_ number: UInt64) {
        guard cancellationBehavior == .respect else { return }
        pending.removeValue(forKey: number)?.1.resume(throwing: CancellationError())
    }

    private func cancelWaiter(_ id: UUID) {
        waiters.removeValue(forKey: id)?.1.resume(throwing: CancellationError())
    }
}
