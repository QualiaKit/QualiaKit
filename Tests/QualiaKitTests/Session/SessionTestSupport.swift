import Foundation
import XCTest
@testable import QualiaKit
import QualiaTesting

final class SessionTestClock: QualiaClock, @unchecked Sendable {
    private let lock = NSLock()
    private var instant: Duration = .zero
    var now: Duration { lock.lock(); defer { lock.unlock() }; return instant }
    func set(_ value: Duration) { lock.lock(); defer { lock.unlock() }; instant = value }
    func sleep(for duration: Duration) async throws { try Task.checkCancellation() }
}

final class SessionDiagnostics: QualiaDiagnosticsSink, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [QualiaSessionDiagnostic] = []
    var events: [QualiaSessionDiagnostic] { lock.lock(); defer { lock.unlock() }; return storage }
    func record(_ event: QualiaSessionDiagnostic) { lock.lock(); defer { lock.unlock() }; storage.append(event) }
}

actor SessionFixtureAnalyzer: QualiaAnalyzing {
    nonisolated let capabilities: QualiaAnalyzerCapabilities
    nonisolated let identity = try! QualiaAnalyzerIdentity(identifier: "com.qualiakit.fixture.session", version: "1")
    let ignoresCancellation: Bool
    private(set) var inputs: [QualiaInput] = []
    private var pending: [String: (QualiaInput, CheckedContinuation<QualiaObservation, Error>)] = [:]
    private var counts: [String: Int] = [:]
    private var expectations: [String: [(Int, XCTestExpectation)]] = [:]
    private var cancellations: Set<String> = []
    private var cancelExpectations: [String: XCTestExpectation] = [:]

    init(ignoresCancellation: Bool = true, acceptsContext: Bool = true,
         languages: Set<QualiaLanguage> = [try! .init(rawValue: "en"), try! .init(rawValue: "ru")],
         signals: Set<QualiaSignal> = [.suspense, .threat, .impact]) {
        self.ignoresCancellation = ignoresCancellation
        capabilities = .init(languages: languages, dimensions: [], signals: signals,
                             acceptsContext: acceptsContext, execution: .onDevice)
    }

    func analyze(_ input: QualiaInput) async throws -> QualiaObservation {
        let id = input.id.rawValue
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if !ignoresCancellation && (Task.isCancelled || cancellations.contains(id)) {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                inputs.append(input)
                pending[id] = (input, continuation)
                counts[id, default: 0] += 1
                for (count, expectation) in expectations[id] ?? [] where counts[id, default: 0] >= count {
                    expectation.fulfill()
                }
                expectations[id] = (expectations[id] ?? []).filter { counts[id, default: 0] < $0.0 }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func invocation(_ id: String, count: Int = 1) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: "Analyzer invocation \(id) #\(count)")
        if counts[id, default: 0] >= count { expectation.fulfill() }
        else { expectations[id, default: []].append((count, expectation)) }
        return expectation
    }

    func cancellation(_ id: String) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: "Analyzer cancellation \(id)")
        if cancellations.contains(id) { expectation.fulfill() }
        else { cancelExpectations[id] = expectation }
        return expectation
    }

    private func cancel(_ id: String) {
        cancellations.insert(id)
        cancelExpectations.removeValue(forKey: id)?.fulfill()
        if !ignoresCancellation { pending.removeValue(forKey: id)?.1.resume(throwing: CancellationError()) }
    }

    func complete(_ id: String, suspense: Float = 0.91, impact: Float? = nil, outputID: String? = nil) throws {
        guard let (input, continuation) = pending.removeValue(forKey: id) else { return }
        var scores: [QualiaSignal: QualiaScore] = [:]
        if capabilities.signals.contains(.suspense) { scores[.suspense] = try .init(value: suspense, confidence: 0.9) }
        if let impact { scores[.impact] = try .init(value: impact, confidence: 0.9) }
        let observation = QualiaObservation(inputID: try outputID.map { try QualiaInputID(rawValue: $0) } ?? input.id,
                                           signals: scores, language: input.language!, analyzer: identity)
        continuation.resume(returning: observation)
    }

    func fail(_ id: String, with error: QualiaError) { pending.removeValue(forKey: id)?.1.resume(throwing: error) }
}

actor SessionDispatchBarrier {
    private let held: Set<UInt64>
    private var reached: Set<UInt64> = []
    private var released: Set<UInt64> = []
    private var continuations: [UInt64: CheckedContinuation<Void, Never>] = [:]
    private var expectations: [UInt64: XCTestExpectation] = [:]
    init(holding: Set<UInt64>) { held = holding }
    func enter(_ generation: UInt64) async {
        reached.insert(generation)
        expectations.removeValue(forKey: generation)?.fulfill()
        guard held.contains(generation), !released.contains(generation) else { return }
        await withCheckedContinuation { continuations[generation] = $0 }
    }
    func arrival(_ generation: UInt64) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: "MainActor dispatch \(generation)")
        if reached.contains(generation) { expectation.fulfill() }
        else { expectations[generation] = expectation }
        return expectation
    }
    func release(_ generation: UInt64) {
        released.insert(generation)
        continuations.removeValue(forKey: generation)?.resume()
    }
}

struct SessionBlockingResolver: QualiaLanguageResolving {
    let started: XCTestExpectation
    let release: DispatchSemaphore
    func resolve(for input: QualiaInput) throws -> QualiaLanguageResolution {
        started.fulfill()
        _ = release.wait(timeout: .now() + 10)
        return try .init(language: input.language!, source: .explicit, confidence: nil)
    }
}

func sessionInput(_ id: String, text: String? = nil, language: String = "en") throws -> QualiaInput {
    try .init(id: QualiaInputID(rawValue: id), text: text ?? "text-\(id)", language: QualiaLanguage(rawValue: language))
}

@MainActor
func sessionDependencies(
    analyzer: SessionFixtureAnalyzer, clock: SessionTestClock,
    fragments: Int = 4, characters: Int = 200, bytes: Int? = 800,
    reducer: any QualiaSceneReducing = QualiaSceneReducer(),
    policy: any QualiaReactionPolicy = HorrorNarrativePolicy(),
    resolver: (any QualiaLanguageResolving)? = nil,
    diagnostics: SessionDiagnostics = SessionDiagnostics()
) throws -> QualiaSessionDependencies {
    let resolver = try resolver ?? QualiaLanguageResolver(
        policy: .requireExplicit, minimumConfidence: 0.75,
        diagnostics: { diagnostics.record(.preparation($0)) }
    )
    let window = QualiaContextWindow(configuration: try .init(
        maximumFragments: fragments, maximumCharacters: characters, maximumUTF8Bytes: bytes
    ), diagnostics: { diagnostics.record(.preparation($0)) })
    return .init(analyzer: analyzer, languageResolver: resolver, contextWindow: window,
                 stateReducer: reducer, reactionPolicy: policy, diagnostics: diagnostics, clock: clock)
}

@MainActor
func waitForSessionEvent(_ expectation: XCTestExpectation, file: StaticString = #filePath, line: UInt = #line) async throws {
    let result = await XCTWaiter.fulfillment(of: [expectation], timeout: 5)
    XCTAssertEqual(result, .completed, file: file, line: line)
    if result != .completed { throw SessionTestFailure.timeout }
}

enum SessionTestFailure: Error { case timeout }

@MainActor
func accept(_ id: String, text: String? = nil, session: QualiaSession, fixture: SessionFixtureAnalyzer,
            suspense: Float = 0.91, impact: Float? = nil, invocation: Int = 1) async throws -> QualiaResponse {
    let input = try sessionInput(id, text: text)
    let task = Task { try await session.process(input) }
    try await waitForSessionEvent(fixture.invocation(id, count: invocation))
    try await fixture.complete(id, suspense: suspense, impact: impact)
    return try await task.value
}

@MainActor
func assertSessionCancelled(_ task: Task<QualiaResponse, Error>, file: StaticString = #filePath, line: UInt = #line) async {
    do { _ = try await task.value; XCTFail("Expected cancellation", file: file, line: line) }
    catch is CancellationError { }
    catch { XCTFail("Unexpected error: \(error)", file: file, line: line) }
}

func sessionCommandKind(_ command: HapticCommand) -> String {
    switch command {
    case .start: return "start"
    case .replace: return "replace"
    case .play: return "play"
    case .stop: return "stop"
    case .stopAll: return "stopAll"
    case .stopChannel: return "stopChannel"
    }
}
