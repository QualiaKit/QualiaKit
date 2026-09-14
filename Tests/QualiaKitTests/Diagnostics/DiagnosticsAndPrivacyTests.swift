import Foundation
import XCTest
@testable import QualiaKit
import QualiaTesting

@MainActor
final class DiagnosticsAndPrivacyTests: XCTestCase {
    func testAnalyzerFailureIsPrivateAndLeavesSceneContextAndPlaybackUnchanged() async throws {
        let fixture = SessionFixtureAnalyzer()
        let diagnostics = SessionDiagnostics()
        let renderer = RecordingHapticRenderer()
        let session = try await makeSession(fixture, renderer, diagnostics)
        _ = try await accept("accepted", session: session, fixture: fixture)
        let before = await session.snapshot
        let effects = renderer.activeEffects
        let commands = renderer.commands
        let secret = "PRIVATE_TEXT_AND_PATH_/Users/person/story_889"
        let task = Task { try await session.process(sessionInput("private-id", text: secret)) }
        try await waitForSessionEvent(fixture.invocation("private-id"))
        await fixture.fail("private-id", with: NSError(domain: secret, code: 7,
            userInfo: [NSLocalizedDescriptionKey: secret]))
        do { _ = try await task.value; XCTFail("Expected failure") }
        catch {
            XCTAssertEqual(error as? QualiaError, .inferenceFailed(reason: .adapterFailure))
            XCTAssertFalse(String(reflecting: error).contains(secret))
        }
        let after = await session.snapshot
        XCTAssertEqual(after.scene, before.scene)
        XCTAssertEqual(after.retainedFragments, before.retainedFragments)
        XCTAssertEqual(renderer.activeEffects, effects)
        XCTAssertEqual(renderer.commands, commands)
        XCTAssertTrue(diagnostics.events.contains { event in
            if case let .correlated(id, 2, .failure(.analysis, failure)) = event {
                return id == session.diagnosticID && failure.error == .inferenceFailed(reason: .adapterFailure)
            }
            return false
        })
        XCTAssertFalse(String(reflecting: diagnostics.events).contains(secret))
        XCTAssertFalse(String(reflecting: diagnostics.events).contains("private-id"))
    }

    func testGlobalDisableStopsHeartbeatAndInvalidatesQueuedPlayback() async throws {
        let fixture = SessionFixtureAnalyzer()
        let renderer = RecordingHapticRenderer()
        let diagnostics = SessionDiagnostics()
        let session = try await makeSession(fixture, renderer, diagnostics)
        _ = try await accept("a", session: session, fixture: fixture)
        XCTAssertEqual(renderer.activeEffects.count, 1)
        let pending = Task { try await session.process(sessionInput("queued")) }
        try await waitForSessionEvent(fixture.invocation("queued"))
        try await session.updateHapticPreferences(.disabled)
        XCTAssertTrue(renderer.activeEffects.isEmpty)
        try await fixture.complete("queued")
        await assertSessionCancelled(pending)
        let count = renderer.commands.count
        let disabled = try await accept("b", session: session, fixture: fixture)
        XCTAssertTrue(disabled.reaction.hapticCommands.isEmpty)
        XCTAssertEqual(renderer.commands.count, count)
        XCTAssertTrue(disabled.execution.suppressions.contains(.disabled))
        try await session.updateHapticPreferences(.default)
        XCTAssertEqual(renderer.commands.count, count)
        _ = try await accept("c", session: session, fixture: fixture)
        XCTAssertEqual(renderer.activeEffects.count, 1)
    }

    func testPreferenceChangePreservesSuspensionAndStopsOnDurationOrIntensityReduction() async throws {
        for preferences in [try QualiaHapticPreferences(intensityScale: 0.2),
                            try .init(maximumContinuousDuration: .seconds(1))] {
            let fixture = SessionFixtureAnalyzer()
            let renderer = RecordingHapticRenderer()
            let session = try await makeSession(fixture, renderer)
            _ = try await accept("a", session: session, fixture: fixture)
            let before = await session.snapshot
            try await session.updateHapticPreferences(preferences)
            XCTAssertTrue(renderer.activeEffects.isEmpty)
            let after = await session.snapshot
            XCTAssertEqual(after.scene, before.scene)
            XCTAssertEqual(after.retainedFragments, before.retainedFragments)
            try await session.suspend()
            try await session.updateHapticPreferences(.default)
            let suspended = await session.snapshot
            XCTAssertEqual(suspended.lifecycle, .suspended)
            do { _ = try await session.process(sessionInput("b")); XCTFail("Suspended") }
            catch { XCTAssertEqual(error as? QualiaSessionError, .suspended) }
        }
    }

    func testFailedDisableRequiresExplicitCleanupAndCannotRestartPlayback() async throws {
        let fixture = SessionFixtureAnalyzer()
        let renderer = RecordingHapticRenderer()
        let session = try await makeSession(fixture, renderer)
        _ = try await accept("a", session: session, fixture: fixture)
        renderer.failNext(with: .playerStopFailed)
        do { try await session.updateHapticPreferences(.disabled); XCTFail("Expected stop failure") }
        catch { XCTAssertEqual(error as? HapticError, .playerStopFailed) }
        let snapshot = await session.snapshot
        XCTAssertEqual(snapshot.lifecycle, .cleanupRequired)
        do { _ = try await session.process(sessionInput("b")); XCTFail("Cleanup required") }
        catch { XCTAssertEqual(error as? QualiaSessionError, .cleanupRequired) }
        try await session.resume()
        XCTAssertTrue(renderer.activeEffects.isEmpty)
        let response = try await accept("b", session: session, fixture: fixture)
        XCTAssertTrue(response.reaction.hapticCommands.isEmpty)
    }

    func testPreferenceLimitsApplyEvenToCustomPolicyThatIgnoresThem() async throws {
        let fixture = SessionFixtureAnalyzer()
        let renderer = RecordingHapticRenderer()
        let diagnostics = SessionDiagnostics()
        let deps = try sessionDependencies(analyzer: fixture, clock: SessionTestClock(),
                                           policy: UnrestrictedPrivacyPolicy(), diagnostics: diagnostics)
        let session = try await QualiaSession(dependencies: deps,
            renderer: .init(renderer: renderer, arbitration: .independentOwners),
            preferences: .init(intensityScale: 0.25, maximumContinuousDuration: .seconds(2)))
        let response = try await accept("a", session: session, fixture: fixture)
        XCTAssertEqual(response.execution.commands.count, 2)
        let pattern = try XCTUnwrap(renderer.activeEffects.values.first?.pattern)
        XCTAssertEqual(pattern.playbackDuration, .seconds(2))
        guard case let .continuous(_, _, intensity, _) = pattern.events[0] else { return XCTFail("Continuous") }
        XCTAssertEqual(intensity.rawValue, 0.25)
        try await session.updateHapticPreferences(.init(continuousEffectsEnabled: false))
        let accentsOnly = try await accept("b", session: session, fixture: fixture)
        XCTAssertEqual(accentsOnly.execution.commands.map { $0.command.diagnosticKind }, [.play])
        XCTAssertTrue(accentsOnly.execution.suppressions.contains(.continuousDisabled))
        try await session.updateHapticPreferences(.disabled)
        let none = try await accept("c", session: session, fixture: fixture)
        XCTAssertTrue(none.execution.commands.isEmpty)
        XCTAssertTrue(renderer.activeEffects.isEmpty)
        // Custom policy identifiers/facts can contain private strings. Standard
        // diagnostics retain fingerprints, never the rationale or those strings.
        XCTAssertFalse(String(reflecting: diagnostics.events).contains("PRIVATE_POLICY"))
    }

    func testReplacementCannotExtendPhysicalMaximumDuration() throws {
        let renderer = RecordingHapticRenderer()
        try renderer.prepare()
        let executor = QualiaReactionExecutor(renderer: renderer, owner: try .init(rawValue: "owner"),
            preferences: try .init(maximumContinuousDuration: .seconds(3)))
        let fixture = SessionFixtureAnalyzer()
        let transition = QualiaSceneTransitionForPrivacy.make()
        for second in 0...3 {
            _ = try executor.execute(for: transition, policy: UnrestrictedPrivacyPolicy(),
                analyzerCapabilities: fixture.capabilities, at: .seconds(second), request: executor.beginRequest())
            if second < 3 {
                XCTAssertEqual(renderer.activeEffects.values.first?.pattern.playbackDuration, .seconds(3 - second))
            }
        }
        XCTAssertTrue(renderer.activeEffects.isEmpty)
    }

    func testCustomPolicyCannotRetryVibrationAfterRendererFailure() throws {
        let renderer = RecordingHapticRenderer()
        try renderer.prepare()
        let executor = QualiaReactionExecutor(renderer: renderer, owner: try .init(rawValue: "owner"))
        renderer.failNext(with: .playerStartFailed)
        let fixture = SessionFixtureAnalyzer()
        let transition = QualiaSceneTransitionForPrivacy.make()
        XCTAssertThrowsError(try executor.execute(for: transition, policy: UnrestrictedPrivacyPolicy(),
            analyzerCapabilities: fixture.capabilities, at: .zero, request: executor.beginRequest()))
        let count = renderer.commands.count
        for second in 1...3 {
            _ = try executor.execute(for: transition, policy: UnrestrictedPrivacyPolicy(),
                analyzerCapabilities: fixture.capabilities, at: .seconds(second), request: executor.beginRequest())
        }
        XCTAssertEqual(renderer.commands.count, count)
        try executor.reset()
        _ = try executor.execute(for: transition, policy: UnrestrictedPrivacyPolicy(),
            analyzerCapabilities: fixture.capabilities, at: .seconds(4), request: executor.beginRequest())
        XCTAssertGreaterThan(renderer.commands.count, count)
    }

    func testCancellationAndStaleDiscardRemainDistinctFromInferenceFailure() async throws {
        let fixture = SessionFixtureAnalyzer()
        let diagnostics = SessionDiagnostics()
        let session = try await makeSession(fixture, RecordingHapticRenderer(), diagnostics)
        let cancelled = Task { try await session.process(sessionInput("cancel")) }
        try await waitForSessionEvent(fixture.invocation("cancel"))
        cancelled.cancel()
        try await fixture.complete("cancel")
        await assertSessionCancelled(cancelled)
        let stale = Task { try await session.process(sessionInput("stale")) }
        try await waitForSessionEvent(fixture.invocation("stale"))
        _ = try await accept("new", session: session, fixture: fixture)
        try await fixture.complete("stale")
        await assertSessionCancelled(stale)
        XCTAssertTrue(diagnostics.events.contains { if case .cancelled = $0 { return true }; return false })
        XCTAssertTrue(diagnostics.events.contains { if case .discarded = $0 { return true }; return false })
        XCTAssertFalse(diagnostics.events.contains { if case .failed = $0 { return true }; return false })
    }

    func testNoOpIsLazyAndRecordingSinkIsBoundedUnderConcurrentCalls() async throws {
        let sink = NoOpQualiaDiagnosticsSink()
        var constructed = false
        func makeEvent() -> QualiaDiagnosticEvent { constructed = true; return .lifecycle(.created) }
        sink.emit(makeEvent())
        XCTAssertFalse(constructed)
        XCTAssertFalse(sink.isEnabled)
        let start = ContinuousClock.now
        for _ in 0..<100_000 { sink.emit(makeEvent()) }
        print("No-op diagnostics benchmark: 100000 calls=\(start.duration(to: .now))")
        XCTAssertFalse(constructed)
        let recorder = try RecordingQualiaDiagnosticsSink(capacity: 16)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<1000 { group.addTask { recorder.record(.lifecycle(.created)) } }
        }
        XCTAssertEqual(recorder.entries.count, 16)
        XCTAssertEqual(recorder.droppedEventCount, 984)
        XCTAssertEqual(recorder.entries.map(\.sequence), Array(1...16).map(UInt64.init))
        XCTAssertEqual(recorder.drain().count, 16)
        XCTAssertTrue(recorder.entries.isEmpty)
        recorder.record(.lifecycle(.reset))
        XCTAssertEqual(recorder.entries.first?.sequence, 1001)
        XCTAssertThrowsError(try RecordingQualiaDiagnosticsSink(capacity: 0))
    }

    func testErrorsRemoveTextFromLanguageAndAnalyzerMetadata() throws {
        let secret = "PRIVATE_MODEL_/Users/person/story"
        let identity = try QualiaAnalyzerIdentity(identifier: secret, version: secret)
        let errors: [QualiaError] = [
            .analyzerUnavailable(identity: identity), .invalidAnalyzerOutput(identity: identity),
            .unsupportedLanguage(try .init(rawValue: secret)),
            .invalidModelManifest(reason: .manifestContract), .incompatibleModel(reason: .modelContract),
            .tokenizationFailed(reason: .tokenizerContract), .inferenceFailed(reason: .adapterFailure),
            .invalidModelOutput(reason: .modelOutput), .invalidConfiguration(reason: .configuration),
            .invalidHapticPattern(reason: .pattern), .hapticsUnavailable, .hapticExecutionFailed(reason: .renderer)
        ]
        for error in errors {
            let diagnostic = QualiaDiagnosticFailure.redacted(error, stage: .analysis)
            XCTAssertFalse(String(reflecting: diagnostic).contains(secret))
            XCTAssertFalse(String(reflecting: diagnostic.error).contains(secret))
        }
        for duration: Duration in [.zero, .seconds(-1), .seconds(3601)] {
            XCTAssertThrowsError(try QualiaHapticPreferences(maximumContinuousDuration: duration))
        }
    }

    func testVersionsCapabilitiesAndSeparateNonModelTiming() async throws {
        let recorder = try RecordingQualiaDiagnosticsSink(capacity: 4096)
        let analyzer = ImmediatePrivacyAnalyzer()
        let deps = QualiaSessionDependencies(analyzer: analyzer,
            languageResolver: try QualiaLanguageResolver(policy: .requireExplicit, minimumConfidence: 0.75),
            contextWindow: .init(configuration: try .init(maximumFragments: 0, maximumCharacters: 100)),
            stateReducer: QualiaSceneReducer(), reactionPolicy: NoReactionPolicy(), diagnostics: recorder,
            clock: QualiaContinuousClock())
        let session = try await QualiaSession(dependencies: deps,
            renderer: .init(renderer: NoOpHapticRenderer(), arbitration: .independentOwners))
        for index in 0..<100 { _ = try await session.process(sessionInput("input-\(index)")) }
        let capabilities = await session.hapticCapabilities
        XCTAssertEqual(capabilities, .unavailable)
        let events = recorder.entries.map(\.event)
        XCTAssertTrue(events.contains { if case .correlated(_, _, .installed(analyzer.diagnosticIdentity, _, _)) = $0 { return true }; return false })
        XCTAssertTrue(events.contains { if case .correlated(_, _, .suppressed(.hardwareUnavailable)) = $0 { return true }; return false })
        var preparation: [Duration] = [], stateAndPolicy: [Duration] = [], inference: [Duration] = [], dispatch: [Duration] = []
        for event in events {
            guard case let .correlated(_, _, .timing(stage, duration)) = event else { continue }
            switch stage {
            case .preparation: preparation.append(duration)
            case .stateAndPolicy: stateAndPolicy.append(duration)
            case .inference: inference.append(duration)
            case .dispatch: dispatch.append(duration)
            }
        }
        XCTAssertEqual(preparation.count, 100)
        XCTAssertEqual(inference.count, 100)
        XCTAssertEqual(stateAndPolicy.count, 100)
        XCTAssertEqual(dispatch.count, 100)
        let overhead = zip(preparation, stateAndPolicy).map(+).sorted()
        // Evidence for this local fixture, not a physical-device latency promise.
        print("Diagnostics benchmark: non-model p95=\(overhead[94]), dispatch p95=\(dispatch.sorted()[94])")
        XCTAssertLessThan(overhead[94], .milliseconds(5))
    }

    func testPreferenceUpdateSupersedesResetAfterOwnedStopWithoutLeavingExecutorSuspended() async throws {
        let fixture = SessionFixtureAnalyzer()
        let renderer = RecordingHapticRenderer()
        let barrier = SessionDispatchBarrier(holding: [2])
        let bridge = QualiaSessionRenderer(renderer: renderer, arbitration: .independentOwners,
            afterDispatch: nil, afterStop: { await barrier.enter($0) })
        let session = try await QualiaSession(dependencies: sessionDependencies(analyzer: fixture, clock: SessionTestClock()),
                                             renderer: bridge)
        _ = try await accept("a", session: session, fixture: fixture)
        let reset = Task { try await session.reset() }
        try await waitForSessionEvent(barrier.arrival(2))
        try await session.updateHapticPreferences(.default)
        await barrier.release(2)
        do { try await reset.value; XCTFail("Reset must be superseded") }
        catch { XCTAssertTrue(error is CancellationError) }
        _ = try await accept("b", session: session, fixture: fixture)
        XCTAssertEqual(renderer.activeEffects.count, 1)
    }

    func testFallbackSelectionUsesSharedSinkWithoutAttachingOperationalFactsToObservation() async throws {
        let diagnostics = try RecordingQualiaDiagnosticsSink()
        let fallback = ImmediatePrivacyAnalyzer()
        let primary = UnavailablePrivacyAnalyzer(capabilities: fallback.capabilities)
        let analyzer = try FallbackAnalyzer(primary: primary, fallback: fallback, causes: [.analyzerUnavailable],
                                            diagnostics: diagnostics)
        let observation = try await analyzer.analyze(sessionInput("fallback"))
        XCTAssertEqual(observation.analyzer.identifier, "fixture")
        XCTAssertTrue(diagnostics.entries.contains { entry in
            if case .fallbackSelected(.analyzerUnavailable, fallback.diagnosticIdentity) = entry.event { return true }
            return false
        })
    }

    private func makeSession(_ analyzer: SessionFixtureAnalyzer, _ renderer: RecordingHapticRenderer,
                             _ diagnostics: SessionDiagnostics = SessionDiagnostics()) async throws -> QualiaSession {
        try await QualiaSession(dependencies: sessionDependencies(analyzer: analyzer, clock: SessionTestClock(),
                                                                 diagnostics: diagnostics),
            renderer: .init(renderer: renderer, arbitration: .independentOwners))
    }
}

private enum QualiaSceneTransitionForPrivacy {
    static func make() -> QualiaSceneTransition {
        let state = QualiaSceneState.initial(at: .zero)
        let observation = QualiaObservation(inputID: try! .init(rawValue: "fixture"),
            language: try! .init(rawValue: "en"), analyzer: try! .init(identifier: "fixture", version: "1"))
        return QualiaSceneReducer().reduce(state: state, observation: observation, at: .zero)
    }
}

private struct ImmediatePrivacyAnalyzer: QualiaAnalyzing {
    let capabilities = QualiaAnalyzerCapabilities(languages: [try! .init(rawValue: "en")], dimensions: [],
                                                 signals: [], acceptsContext: false, execution: .onDevice)
    var diagnosticIdentity: QualiaDiagnosticIdentity? { .init(identifier: "fixture", version: "1") }
    func analyze(_ input: QualiaInput) async throws -> QualiaObservation {
        XCTAssertFalse(Thread.isMainThread)
        return QualiaObservation(inputID: input.id, language: input.language!,
                                analyzer: try .init(identifier: "fixture", version: "1"))
    }
}

private struct UnrestrictedPrivacyPolicy: QualiaReactionPolicy {
    func plan(for transition: QualiaSceneTransition, context: QualiaReactionContext) -> QualiaReactionPlan {
        let id = try! HapticEffectID(rawValue: "PRIVATE_POLICY", scope: context.effectScope)
        let pattern = try! HapticPattern(duration: .seconds(1), events: [
            .continuous(at: .zero, duration: .seconds(1), intensity: .init(1), sharpness: .init(0.5))
        ], looping: .loop(period: .seconds(1)))
        let accent = try! HapticPattern(duration: .milliseconds(10), events: [
            .transient(at: .zero, intensity: .init(1), sharpness: .init(0.5))
        ])
        let command: HapticCommand = context.state.activeEffects.contains(id)
            ? .replace(id: id, pattern: pattern, channel: .ambient) : .start(id: id, pattern: pattern, channel: .ambient)
        return .init(hapticCommands: [command, .play(pattern: accent, channel: .accent)],
            rationale: .init(policyIdentifier: "PRIVATE_POLICY", policyVersion: "PRIVATE_POLICY", ruleIdentifier: "PRIVATE_POLICY"),
            nextState: context.state.applying(try! .init(effectID: id, normalizedValue: 1, intensityScale: 1, pattern: pattern)))
    }
}

private struct UnavailablePrivacyAnalyzer: QualiaAnalyzing {
    let capabilities: QualiaAnalyzerCapabilities
    func analyze(_ input: QualiaInput) async throws -> QualiaObservation {
        throw QualiaError.analyzerUnavailable(identity: try .init(identifier: "unavailable", version: "1"))
    }
}
