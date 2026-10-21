import Foundation
import XCTest
import QualiaBert
import QualiaKit
import QualiaTesting

@MainActor
final class TestingAndEvaluationTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    private func fixture<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        try JSONDecoder().decode(type, from: Data(contentsOf: root.appendingPathComponent("Tests/Fixtures/testing-v1/" + name)))
    }

    // AC-0013-001: a public oracle runs even when the licensed model is absent.
    func testIndependentTokenizerOracleMatchesEveryTokenIDAndMask() throws {
        struct Corpus: Decodable {
            struct Sample: Decodable { let id: String; let text: String; let tokens: [String]; let ids: [Int]; let mask: [Int] }
            let sequenceLength: Int
            let cases: [Sample]
        }
        let corpus = try fixture("tokenizer.json", as: Corpus.self)
        let vocabulary = root.appendingPathComponent("Tests/Fixtures/testing-v1/vocab.txt")
        let tokens = try String(contentsOf: vocabulary, encoding: .utf8).components(separatedBy: "\n")
        let tokenizer = try BertTokenizer(vocabURL: vocabulary, maxSequenceLength: corpus.sequenceLength)
        XCTAssertEqual(corpus.cases.count, 10)
        for sample in corpus.cases {
            let actual = tokenizer.tokenize(text: sample.text)
            XCTAssertEqual(actual.inputIds, sample.ids, sample.id)
            XCTAssertEqual(actual.attentionMask, sample.mask, sample.id)
            // Vocabulary entries are unique, so decoding IDs preserves exact
            // output token identity; BertTokenizer does not expose strings.
            let decoded = try actual.inputIds.map { id -> String in
                try XCTUnwrap(tokens.indices.contains(id) ? tokens[id] : nil, "Unknown token ID \(id)")
            }
            XCTAssertEqual(decoded.map { Array($0.utf8) }, sample.tokens.map { Array($0.utf8) }, sample.id)
        }
    }

    private struct Story: Decodable {
        struct Input: Decodable { let id: String; let text: String; let at: Double; let suspense: Float; let impact: Float? }
        struct Command: Decodable {
            let kind: String
            let at: Double
            let duration: Double?
            let playbackDuration: Double?
            let events: [[Double]]?
        }
        let inputs: [Input]
        let expectedSceneSuspense: [Float]
        let expectedCommands: [Command]
    }

    // AC-0013-002: compare complete descriptors, ownership, clocks and state;
    // expectations are never produced by the policy or pattern factory.
    func testDeterministicEndToEndCommandsMatchVersionedStory() async throws {
        let story = try fixture("session.json", as: Story.self)
        let identity = try QualiaAnalyzerIdentity(identifier: "synthetic-story", version: "testing-v1")
        let language = try QualiaLanguage(rawValue: "en")
        let observations = try story.inputs.map { sample -> QualiaObservation in
            var signals: [QualiaSignal: QualiaScore] = [.suspense: try .init(value: sample.suspense, confidence: 1)]
            if let impact = sample.impact { signals[.impact] = try .init(value: impact, confidence: 1) }
            return try .init(inputID: .init(rawValue: sample.id), signals: signals, language: language, analyzer: identity)
        }
        let analyzer = try FixtureAnalyzer(capabilities: capabilities(), observations: observations)
        let harness = try await QualiaSessionHarness(analyzer: analyzer, configuration: configuration())
        for (index, sample) in story.inputs.enumerated() {
            let response = try await harness.process(
                QualiaInput(id: .init(rawValue: sample.id), text: sample.text, language: language),
                advancingBy: .seconds(sample.at) - harness.clock.now
            )
            XCTAssertEqual(response.transition.current.signals[.suspense], story.expectedSceneSuspense[index])
            XCTAssertEqual(response.transition.current.revision, UInt64(index + 1))
            XCTAssertNil(response.execution.failure)
        }
        try await harness.reset()
        let effectID = try HapticEffectID(rawValue: "qualia.horror-narrative.heartbeat", scope: .owned(harness.session.owner))
        let expected = try story.expectedCommands.map { command -> HapticCommand in
            if command.kind == "stop" { return .stop(id: effectID) }
            let duration = Duration.seconds(try XCTUnwrap(command.duration))
            let pattern = try HapticPattern(duration: duration, events: XCTUnwrap(command.events).map { event in
                .transient(at: .seconds(event[0]), intensity: try HapticValue(Float(event[1])), sharpness: try HapticValue(Float(event[2])))
            }, looping: command.kind == "play" ? .none : .loop(period: duration),
                playbackDuration: command.playbackDuration.map { .seconds($0) })
            switch command.kind {
            case "start": return .start(id: effectID, pattern: pattern, channel: .ambient)
            case "replace": return .replace(id: effectID, pattern: pattern, channel: .ambient)
            case "play": return .play(pattern: pattern, channel: .accent)
            default: throw HapticError.invalidCommand
            }
        }
        XCTAssertEqual(harness.renderer.commands, expected)
        XCTAssertEqual(harness.renderer.history.map(\.timestamp), story.expectedCommands.map { .seconds($0.at) })
        XCTAssertTrue(harness.renderer.history.allSatisfy { $0.result == .success && $0.owner == harness.session.owner })
        XCTAssertTrue(harness.renderer.activeEffects.isEmpty)
        let snapshot = await harness.session.snapshot
        XCTAssertEqual(snapshot.scene.revision, 0)
        XCTAssertEqual(snapshot.retainedFragments, 0)
    }

    func testControlledStaleAndResetCompletionsCannotChangeSession() async throws {
        for behavior in [ControlledAnalyzer.CancellationBehavior.respect, .ignore] {
            let analyzer = try ControlledAnalyzer(capabilities: capabilities(), identity: .init(identifier: "controlled", version: "1"),
                                                  cancellationBehavior: behavior)
            let harness = try await QualiaSessionHarness(analyzer: analyzer, configuration: configuration())
            let first = Task { try await harness.process(input("old")) }
            _ = try await analyzer.waitForRequest(number: 1)
            let second = Task { try await harness.process(input("new")) }
            _ = try await analyzer.waitForRequest(number: 2)
            try await analyzer.complete(2, signals: [.suspense: .init(value: 1, confidence: 1)])
            let latest = try await second.value
            let commands = harness.renderer.commands
            if behavior == .ignore { try await analyzer.complete(1, signals: [.suspense: .init(value: 0)]) }
            await assertCancelled(first)
            let snapshot = await harness.session.snapshot
            XCTAssertEqual(snapshot.scene, latest.transition.current)
            XCTAssertEqual(harness.renderer.commands, commands)
            let pending = Task { try await harness.process(input("reset")) }
            _ = try await analyzer.waitForRequest(number: 3)
            try await harness.reset()
            let stopped = harness.renderer.commands
            if behavior == .ignore { try await analyzer.complete(3, signals: [.suspense: .init(value: 1, confidence: 1)]) }
            await assertCancelled(pending)
            XCTAssertEqual(harness.renderer.commands, stopped)
            XCTAssertTrue(harness.renderer.activeEffects.isEmpty)
        }
    }

    // AC-0013-003 is also covered by individual mutation tests in Python.
    func testNarrativeCapabilityEvidenceGateAndFixtureRegeneration() throws {
        try runPython(["Tools/TestingFixtures/generate.py"])
        try runPython(["-m", "unittest", "discover", "-s", "Evaluation/tests", "-v"], minimumTests: 22)
    }

    private func runPython(_ arguments: [String], minimumTests: Int? = nil) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3"] + arguments
        process.currentDirectoryURL = root
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: output, as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, text)
        if let minimumTests {
            let pattern = try NSRegularExpression(pattern: "Ran ([0-9]+) tests?")
            let match = try XCTUnwrap(pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), text)
            let range = try XCTUnwrap(Range(match.range(at: 1), in: text))
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(Int(text[range])), minimumTests,
                                        "Evidence checks must not silently disappear: \(text)")
        }
    }

    private func input(_ id: String) throws -> QualiaInput {
        try .init(id: .init(rawValue: id), text: "Synthetic \(id)", language: .init(rawValue: "en"))
    }

    private func capabilities() throws -> QualiaAnalyzerCapabilities {
        try .init(languages: [.init(rawValue: "en")], dimensions: [], signals: [.suspense, .threat, .impact],
                  acceptsContext: true, execution: .onDevice)
    }

    private func configuration() throws -> QualiaSessionConfiguration {
        try .init(language: .init(policy: .requireExplicit, minimumConfidence: 0.75),
                  context: .init(maximumFragments: 4, maximumCharacters: 1000), sceneState: .narrative,
                  reaction: .horrorNarrative(.init(heartbeat: .init(startThreshold: 0.5, stopThreshold: 0.25,
                      minimumBPM: 60, maximumBPM: 120))))
    }

    private func assertCancelled(_ task: Task<QualiaResponse, Error>) async {
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
        catch { XCTFail("Unexpected error: \(error)") }
    }
}
