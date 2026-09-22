#if canImport(SwiftUI)
import SwiftUI
import XCTest
@testable import QualiaKit
import QualiaTesting

@MainActor
final class SwiftUIIntegrationTests: XCTestCase {
    func testStableEventIdentityProcessesAndRendersOnlyOnce() async throws {
        let clock = SessionTestClock()
        let analyzer = SessionFixtureAnalyzer()
        let renderer = RecordingHapticRenderer()
        let session = try await QualiaSession(
            dependencies: sessionDependencies(analyzer: analyzer, clock: clock),
            renderer: QualiaSessionRenderer(
                renderer: renderer,
                arbitration: .independentOwners
            )
        )
        let coordinator = QualiaEventReactionCoordinator<String>()
        let input = try sessionInput("accepted-event")

        let first = Task {
            try await coordinator.process(
                eventID: "stable-event-id",
                input: input,
                session: session
            )
        }
        try await waitForSessionEvent(analyzer.invocation("accepted-event"))

        let duplicate = try await coordinator.process(
            eventID: "stable-event-id",
            input: input,
            session: session
        )
        XCTAssertNil(duplicate)

        try await analyzer.complete("accepted-event")
        let firstResponse = try await first.value
        let analyzedInputs = await analyzer.inputs
        XCTAssertNotNil(firstResponse)
        XCTAssertEqual(analyzedInputs.count, 1)
        XCTAssertEqual(renderer.commands.count, 1)
        try await session.reset()
    }

    func testRapidLiveInputIsDebouncedIntoSeparatePreviewSession() async throws {
        let debounceClock = SwiftUIDebounceClock()
        let previewAnalyzer = try SwiftUIImmediateAnalyzer()
        let productionAnalyzer = try SwiftUIImmediateAnalyzer()
        let previewSession = try await makePreviewSession(analyzer: previewAnalyzer)
        let productionSession = try await makePreviewSession(analyzer: productionAnalyzer)
        let coordinator = QualiaLiveReactionCoordinator(clock: debounceClock)
        let configuration = try QualiaLiveReactionConfiguration(
            debounce: .milliseconds(350),
            minimumCharacters: 3
        )

        let firstSleep = await debounceClock.gate.arrival(1)
        let first = Task {
            try await coordinator.process(
                text: "old",
                configuration: configuration,
                session: previewSession
            )
        }
        try await waitForSessionEvent(firstSleep)

        let secondSleep = await debounceClock.gate.arrival(2)
        let second = Task {
            try await coordinator.process(
                text: "new draft",
                configuration: configuration,
                session: previewSession
            )
        }
        try await waitForSessionEvent(secondSleep)
        await debounceClock.gate.releaseAll()

        do {
            _ = try await first.value
            XCTFail("Superseded draft should be cancelled")
        } catch is CancellationError {
            // Expected: even a cancellation-ignoring clock cannot submit stale text.
        }
        let secondResponse = try await second.value
        XCTAssertNotNil(secondResponse)

        let submitted = await previewAnalyzer.inputs
        let requestedDurations = await debounceClock.gate.requestedDurations
        let previewSnapshot = await previewSession.snapshot
        let productionSnapshot = await productionSession.snapshot
        let productionInputs = await productionAnalyzer.inputs
        XCTAssertEqual(submitted.map(\.text), ["new draft"])
        XCTAssertEqual(requestedDurations, [.milliseconds(350), .milliseconds(350)])
        XCTAssertEqual(previewSnapshot.scene.revision, 1)
        XCTAssertEqual(productionSnapshot.scene.revision, 0)
        XCTAssertTrue(productionInputs.isEmpty)

        let belowMinimum = try await coordinator.process(
            text: "ab",
            configuration: configuration,
            session: previewSession
        )
        let requestsAfterMinimumCheck = await debounceClock.gate.requestedDurations
        XCTAssertNil(belowMinimum)
        XCTAssertEqual(requestsAfterMinimumCheck.count, 2)
        try await previewSession.reset()
        try await productionSession.reset()
    }

    func testModifiersRequireExplicitSessionAndDoNoWorkWhenConstructed() async throws {
        let analyzer = try SwiftUIImmediateAnalyzer()
        let session = try await makePreviewSession(analyzer: analyzer)
        let input = try QualiaInput(
            id: QualiaInputID(rawValue: "compile-check"),
            text: "accepted text",
            language: QualiaLanguage(rawValue: "en")
        )
        var draft = "preview"
        let binding = Binding(get: { draft }, set: { draft = $0 })

        _ = EmptyView().qualiaReaction(
            eventID: "event-id",
            input: input,
            session: session
        )
        _ = EmptyView().qualiaLiveReaction(
            text: binding,
            debounce: .milliseconds(10),
            minimumCharacters: 3,
            session: session
        )

        let inputs = await analyzer.inputs
        let snapshot = await session.snapshot
        let hapticCapabilities = await session.hapticCapabilities
        XCTAssertTrue(inputs.isEmpty)
        XCTAssertEqual(snapshot.scene.revision, 0)
        XCTAssertEqual(session.analyzerCapabilities, analyzer.capabilities)
        XCTAssertEqual(session.analyzerDiagnosticIdentity, nil)
        XCTAssertEqual(hapticCapabilities, .unavailable)
        try await session.reset()
    }

    func testLiveConfigurationRejectsInvalidValues() throws {
        XCTAssertThrowsError(try QualiaLiveReactionConfiguration(debounce: .milliseconds(-1))) {
            XCTAssertEqual($0 as? QualiaLiveReactionConfigurationError, .negativeDebounce)
        }
        XCTAssertThrowsError(try QualiaLiveReactionConfiguration(minimumCharacters: -1)) {
            XCTAssertEqual($0 as? QualiaLiveReactionConfigurationError, .negativeMinimumCharacters)
        }
    }

    func testConfiguredFactoryWiresEveryConfigurationFamily() async throws {
        let analyzer = try SwiftUIImmediateAnalyzer()
        let renderer = RecordingHapticRenderer()
        let diagnostics = SessionDiagnostics()
        let preferences = try QualiaHapticPreferences(
            enabled: false,
            continuousEffectsEnabled: false,
            intensityScale: 0.25,
            maximumContinuousDuration: .seconds(7)
        )
        let configuration = QualiaSessionConfiguration(
            language: try .init(policy: .requireExplicit, minimumConfidence: 0.91),
            context: try .init(
                maximumFragments: 0,
                maximumCharacters: 120,
                maximumUTF8Bytes: 480
            ),
            sceneState: .sentimentPreview,
            reaction: .sentimentPreview(.default),
            haptics: .init(preferences: preferences, arbitration: .exclusiveAmbient),
            diagnostics: .init(sink: diagnostics)
        )
        let session = try await QualiaSession.configured(
            analyzer: analyzer,
            renderer: renderer,
            configuration: configuration,
            clock: SessionTestClock()
        )

        let response = try await session.process(QualiaInput(
            id: QualiaInputID(rawValue: "configured"),
            text: "A deliberately positive accepted fragment.",
            language: QualiaLanguage(rawValue: "en")
        ))
        let snapshot = await session.snapshot
        let inputs = await analyzer.inputs
        let english = try QualiaLanguage(rawValue: "en")

        XCTAssertEqual(inputs.first?.language, english)
        XCTAssertEqual(inputs.first?.context.count, 0)
        XCTAssertEqual(snapshot.retainedFragments, 0)
        XCTAssertEqual(response.transition.current.dimensions.valence?.value, 0.75)
        XCTAssertEqual(response.reaction.rationale?.ruleIdentifier, "haptics-disabled")
        XCTAssertTrue(response.execution.commands.isEmpty)
        XCTAssertTrue(response.execution.suppressions.contains(.disabled))
        XCTAssertEqual(session.rendererArbitration, .exclusiveAmbient)
        XCTAssertFalse(diagnostics.events.isEmpty)
        try await session.reset()
    }

    func testNamedFactoriesRejectDishonestCapabilitiesAtConstruction() async throws {
        let language = try QualiaLanguageConfiguration(
            policy: .requireExplicit,
            minimumConfidence: 0.8
        )
        let context = try QualiaContextConfiguration(
            maximumFragments: 0,
            maximumCharacters: 100
        )
        let valenceAnalyzer = try SwiftUIImmediateAnalyzer()

        do {
            _ = try await QualiaSession.sentimentPreview(
                analyzer: valenceAnalyzer,
                renderer: NoOpHapticRenderer(),
                language: language,
                context: context,
                clock: SessionTestClock()
            )
            XCTFail("Sentiment preview must require haptic capability")
        } catch {
            XCTAssertEqual(
                error as? QualiaReactionConfigurationError,
                .hapticsUnavailable
            )
        }

        do {
            _ = try await QualiaSession.horrorNarrative(
                analyzer: valenceAnalyzer,
                renderer: RecordingHapticRenderer(),
                language: language,
                context: context,
                clock: SessionTestClock()
            )
            XCTFail("Horror narrative must require narrative signals")
        } catch {
            XCTAssertEqual(
                error as? QualiaError,
                .invalidConfiguration(reason: .configuration)
            )
        }
    }

    func testViewTaskCancellationPropagatesAndTypedErrorsStayErrors() async throws {
        let clock = SessionTestClock()
        let analyzer = SessionFixtureAnalyzer(ignoresCancellation: false)
        let renderer = RecordingHapticRenderer()
        let session = try await QualiaSession(
            dependencies: sessionDependencies(analyzer: analyzer, clock: clock),
            renderer: QualiaSessionRenderer(
                renderer: renderer,
                arbitration: .independentOwners
            )
        )
        let coordinator = QualiaEventReactionCoordinator<String>()
        let cancellation = await analyzer.cancellation("cancelled-view-event")
        let task = Task {
            try await coordinator.process(
                eventID: "view-event",
                input: sessionInput("cancelled-view-event"),
                session: session
            )
        }
        try await waitForSessionEvent(analyzer.invocation("cancelled-view-event"))

        task.cancel()
        try await waitForSessionEvent(cancellation)
        do {
            _ = try await task.value
            XCTFail("Cancelled view task must not produce a response")
        } catch is CancellationError {
            // Cancellation is intentionally distinct from a runtime failure.
        }
        let cancelledSnapshot = await session.snapshot
        XCTAssertEqual(cancelledSnapshot.scene.revision, 0)
        XCTAssertTrue(renderer.commands.isEmpty)

        try await session.suspend()
        do {
            _ = try await QualiaEventReactionCoordinator<String>().process(
                eventID: "suspended-event",
                input: sessionInput("suspended-event"),
                session: session
            )
            XCTFail("Suspended session must surface its typed lifecycle error")
        } catch {
            XCTAssertEqual(error as? QualiaSessionError, .suspended)
        }
        let suspendedSnapshot = await session.snapshot
        XCTAssertEqual(suspendedSnapshot.scene.revision, 0)
        try await session.reset()
    }

    private func makePreviewSession(
        analyzer: SwiftUIImmediateAnalyzer
    ) async throws -> QualiaSession {
        let context = QualiaContextWindow(configuration: try .init(
            maximumFragments: 0,
            maximumCharacters: 1_000,
            maximumUTF8Bytes: 4_000
        ))
        let dependencies = QualiaSessionDependencies(
            analyzer: analyzer,
            languageResolver: try SwiftUIEnglishResolver(),
            contextWindow: context,
            stateReducer: QualiaSceneReducer(),
            reactionPolicy: NoReactionPolicy(),
            clock: SessionTestClock()
        )
        return try await QualiaSession(
            dependencies: dependencies,
            renderer: QualiaSessionRenderer(
                renderer: NoOpHapticRenderer(),
                arbitration: .independentOwners
            )
        )
    }
}

private struct SwiftUIEnglishResolver: QualiaLanguageResolving {
    private let english: QualiaLanguage

    init() throws {
        english = try QualiaLanguage(rawValue: "en")
    }

    func resolve(for input: QualiaInput) throws -> QualiaLanguageResolution {
        _ = input
        return try .init(language: english, source: .detected, confidence: 1)
    }
}

private actor SwiftUIImmediateAnalyzer: QualiaAnalyzing {
    nonisolated let capabilities: QualiaAnalyzerCapabilities
    nonisolated let identity: QualiaAnalyzerIdentity
    private(set) var inputs: [QualiaInput] = []

    init() throws {
        let english = try QualiaLanguage(rawValue: "en")
        capabilities = QualiaAnalyzerCapabilities(
            languages: [english],
            dimensions: [.valence],
            signals: [],
            acceptsContext: false,
            execution: .onDevice
        )
        identity = try QualiaAnalyzerIdentity(
            identifier: "com.qualiakit.fixture.swiftui",
            version: "1"
        )
    }

    func analyze(_ input: QualiaInput) async throws -> QualiaObservation {
        inputs.append(input)
        guard let language = input.language else {
            throw QualiaError.languageUndetermined
        }
        return QualiaObservation(
            inputID: input.id,
            dimensions: .init(valence: try .init(value: 0.75, confidence: 1)),
            language: language,
            analyzer: identity
        )
    }
}

private final class SwiftUIDebounceClock: QualiaClock, @unchecked Sendable {
    let gate = SwiftUIDebounceGate()
    var now: Duration { .zero }

    func sleep(for duration: Duration) async throws {
        // The gate deliberately ignores task cancellation. The coordinator's
        // generation check must still reject a superseded draft.
        await gate.sleep(for: duration)
    }
}

private actor SwiftUIDebounceGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var arrivals: [Int: XCTestExpectation] = [:]
    private(set) var requestedDurations: [Duration] = []

    func sleep(for duration: Duration) async {
        requestedDurations.append(duration)
        arrivals.removeValue(forKey: requestedDurations.count)?.fulfill()
        await withCheckedContinuation { waiters.append($0) }
    }

    func arrival(_ count: Int) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: "Debounce sleep \(count)")
        if requestedDurations.count >= count {
            expectation.fulfill()
        } else {
            arrivals[count] = expectation
        }
        return expectation
    }

    func releaseAll() {
        let continuations = waiters
        waiters.removeAll()
        continuations.forEach { $0.resume() }
    }
}
#endif
