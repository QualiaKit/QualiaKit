import Foundation
import XCTest
import QualiaKit

final class ContextAndLanguageTests: XCTestCase {
    func testRequireExplicitPreservesLanguageAndDoesNotDetect() throws {
        let detector = FixtureDetector(result: try detection("en", 1))
        let resolver = try resolver(.requireExplicit, detector: detector)
        let result = try resolver.resolve(for: input(language: "ru"))
        XCTAssertEqual(result.language, try language("ru"))
        XCTAssertEqual(result.source, .explicit)
        XCTAssertNil(result.confidence)
        XCTAssertEqual(detector.calls.value.count, 0)
    }

    func testRequireExplicitDoesNotGuessForShortOrLongText() throws {
        let detector = FixtureDetector(result: try detection("en", 1))
        let resolver = try resolver(.requireExplicit, detector: detector)
        for text in ["Hi", "This is a complete and unambiguous English sentence."] {
            assertError(.languageUndetermined) { try resolver.resolve(for: input(text: text)) }
        }
        XCTAssertEqual(detector.calls.value.count, 0)
    }

    func testPreferredExplicitLanguageWinsWithoutDetectorConfidence() throws {
        let detector = FixtureDetector(result: try detection("en", 0.1))
        let resolver = try resolver(
            .preferExplicitThenDetect(allowed: [language("ru"), language("en")]),
            detector: detector
        )
        let result = try resolver.resolve(for: input(language: "ru"))
        XCTAssertEqual(result.language, try language("ru"))
        XCTAssertEqual(result.source, .explicit)
        XCTAssertNil(result.confidence)
        XCTAssertTrue(detector.calls.value.isEmpty)
    }

    func testDisallowedExplicitLanguageDoesNotFallThroughToDetection() throws {
        let detector = FixtureDetector(result: try detection("ru", 1))
        let resolver = try resolver(.preferExplicitThenDetect(allowed: [language("ru")]), detector: detector)
        assertError(try .unsupportedLanguage(language("en"))) {
            try resolver.resolve(for: input(language: "en"))
        }
        XCTAssertTrue(detector.calls.value.isEmpty)
    }

    func testPreferExplicitDetectsWhenLanguageIsAbsent() throws {
        let detector = FixtureDetector(result: try detection("ru", 0.9))
        let resolver = try resolver(.preferExplicitThenDetect(allowed: [language("ru")]), detector: detector)
        let result = try resolver.resolve(for: input())
        XCTAssertEqual(result.language, try language("ru"))
        XCTAssertEqual(result.source, .detected)
        XCTAssertEqual(result.confidence, 0.9)
        XCTAssertEqual(detector.calls.value.count, 1)
    }

    func testDetectPolicyUsesOnlyCurrentTextEvenWithExplicitHintAndHistory() throws {
        let detector = FixtureDetector(result: try detection("ru", 0.9))
        let resolver = try resolver(.detect(allowed: [language("ru")]), detector: detector)
        let result = try resolver.resolve(for: input(text: "текущий", context: ["old history"], language: "en"))
        XCTAssertEqual(result.language, try language("ru"))
        XCTAssertEqual(result.source, .detected)
        XCTAssertEqual(detector.calls.value, ["текущий"])
    }

    func testUnknownDetectionNeverBecomesEnglish() throws {
        for policy in try detectionPolicies() {
            let resolver = try resolver(policy, detector: FixtureDetector(result: nil))
            assertError(.languageUndetermined) { try resolver.resolve(for: input(text: "42?!")) }
        }
    }

    func testConfidenceThresholdIsInclusiveAndConfigurable() throws {
        for policy in try detectionPolicies() {
            for (score, threshold, succeeds) in [(Float(0.75), Float(0.75), true),
                                                (0.74, 0.75, false), (0, 0, true), (1, 1, true),
                                                (0.9, 0.95, false)] {
                let resolver = try QualiaLanguageResolver(
                    policy: policy, minimumConfidence: threshold,
                    detector: FixtureDetector(result: detection("en", score))
                )
                if succeeds {
                    let result = try resolver.resolve(for: input())
                    XCTAssertEqual(result.confidence, score)
                } else {
                    assertError(.languageUndetermined) { try resolver.resolve(for: input()) }
                }
            }
        }
    }

    func testConfidentDisallowedLanguageIsRejectedAndUncertainOneIsUndetermined() throws {
        for policy in try detectionPolicies() {
            let confident = try resolver(policy, detector: FixtureDetector(result: detection("fr", 0.9)))
            assertError(try .unsupportedLanguage(language("fr"))) { try confident.resolve(for: input()) }
            let uncertain = try resolver(policy, detector: FixtureDetector(result: detection("fr", 0.1)))
            assertError(.languageUndetermined) { try uncertain.resolve(for: input()) }
        }
    }

    func testLanguageIdentifiersAreNotSilentlyCanonicalized() throws {
        let resolver = try resolver(.preferExplicitThenDetect(allowed: [language("en")]))
        for value in ["EN", "en-US", " en "] {
            assertError(try .unsupportedLanguage(language(value))) {
                try resolver.resolve(for: input(language: value))
            }
        }
    }

    func testInvalidLanguageConfigurationAndConfidenceAreRejected() throws {
        for threshold: Float in [-0.01, 1.01, .infinity, -.infinity, .nan] {
            assertError(.invalidLanguageConfiguration) {
                try QualiaLanguageResolver(policy: .requireExplicit, minimumConfidence: threshold)
            }
            assertError(.invalidConfidence) { try detection("en", threshold) }
            assertError(.invalidConfidence) {
                try QualiaLanguageResolution(language: language("en"), source: .detected, confidence: threshold)
            }
        }
        for policy: QualiaLanguagePolicy in [.detect(allowed: []), .preferExplicitThenDetect(allowed: [])] {
            assertError(.invalidLanguageConfiguration) { try resolver(policy) }
        }
    }

    func testAppleDetectorHasNoStateAcrossLanguagesAndNoEmptyTextFallback() throws {
        let detector = AppleLanguageDetector()
        let english = "The reader opened the book and started reading a long story about a quiet village in the mountains."
        let russian = "Читатель открыл книгу и начал читать длинную историю о тихой деревне, которая находилась высоко в горах."
        for (text, code) in [(english, "en"), (russian, "ru"), (english, "en")] {
            let result = try XCTUnwrap(detector.detectLanguage(in: text))
            XCTAssertEqual(result.language, try language(code))
            XCTAssertTrue((0...1).contains(result.confidence))
        }
        XCTAssertNil(detector.detectLanguage(in: ""))
    }

    func testEmptyCurrentTextIsRejectedAtTheDomainBoundary() throws {
        for text in ["", " \n\t", "\u{2003}"] {
            assertError(.emptyInput) { try input(text: text, context: ["nonempty history"]) }
        }
    }

    func testFragmentLimitRetainsNewestSuffixAndPreservesIDs() throws {
        let original = try input(text: "current", context: ["oldest", "middle", "newest"], language: "ru")
        let result = try window(fragments: 2).window(original)
        XCTAssertEqual(result.context.map(\.text), ["middle", "newest"])
        XCTAssertEqual(result.context.map(\.id), Array(original.context.suffix(2)).map(\.id))
        XCTAssertEqual(result.id, original.id)
        XCTAssertEqual(result.language, original.language)
        XCTAssertEqual(Data(result.text.utf8), Data(original.text.utf8))
    }

    func testExactCharacterBoundaryAndCurrentTextPriority() throws {
        let original = try input(text: "CC", context: ["a", "b"])
        XCTAssertEqual(try window(characters: 4).window(original).context.map(\.text), ["a", "b"])
        let trimmed = try window(characters: 3).window(original)
        XCTAssertEqual(trimmed.context.map(\.text), ["b"])
        XCTAssertEqual(trimmed.text, "CC")
        XCTAssertTrue(try window(characters: 2).window(original).context.isEmpty)
    }

    func testByteLimitDistinguishesComposedAndDecomposedUnicodeWithoutNormalization() throws {
        let composed = "caf\u{00e9}"
        let decomposed = "cafe\u{0301}"
        XCTAssertEqual(composed.count, decomposed.count)
        XCTAssertEqual(composed.utf8.count, 5)
        XCTAssertEqual(decomposed.utf8.count, 6)
        for (text, fits) in [(composed, true), (decomposed, false)] {
            let result = try window(bytes: 6).window(input(text: "x", context: [text]))
            XCTAssertEqual(result.context.count, fits ? 1 : 0)
            if fits { XCTAssertEqual(Data(result.context[0].text.utf8), Data(text.utf8)) }
        }
        let both = try window(bytes: 12).window(input(text: "x", context: [composed, decomposed]))
        XCTAssertEqual(both.context.map { Data($0.text.utf8) }, [Data(composed.utf8), Data(decomposed.utf8)])
        XCTAssertEqual(try window(bytes: 11).window(input(text: "x", context: [composed, decomposed])).context.count, 1)
    }

    func testUnicodeCurrentTextIsWholeAndByteExactAtTheLimit() throws {
        for text in ["e\u{0301}", "👩‍👩‍👧‍👦", "🇷🇺", "я"] {
            XCTAssertEqual(text.count, 1)
            let result = try window(characters: 1, bytes: text.utf8.count)
                .window(input(text: text, context: ["old"]))
            XCTAssertTrue(result.context.isEmpty)
            XCTAssertEqual(Data(result.text.utf8), Data(text.utf8))
            assertError(.currentTextExceedsContextBounds) {
                try window(bytes: text.utf8.count - 1).window(input(text: text))
            }
        }
    }

    func testCharactersAreCountedPerFragmentWithoutJoiningGraphemes() throws {
        let result = try window(characters: 1).window(input(text: "\u{0301}", context: ["e"]))
        XCTAssertTrue(result.context.isEmpty)
        XCTAssertEqual(Data(result.text.utf8), Data("\u{0301}".utf8))
    }

    func testOldestFirstDoesNotSkipLargeNewestFragmentToKeepOlderOnes() throws {
        let result = try window(characters: 3).window(input(text: "x", context: ["a", "too large"]))
        XCTAssertTrue(result.context.isEmpty)
        XCTAssertEqual(result.text, "x")
    }

    func testAllBoundsApplyTogetherAndByteBoundCanBeDisabled() throws {
        let original = try input(text: "я", context: ["a", "b", "é"])
        XCTAssertEqual(try window(fragments: 2, characters: 3, bytes: 5).window(original).context.map(\.text), ["b", "é"])
        XCTAssertEqual(try window(fragments: 2, characters: 3, bytes: 4).window(original).context.map(\.text), ["é"])
        XCTAssertEqual(try window(fragments: 2, characters: 2, bytes: 5).window(original).context.map(\.text), ["é"])
        XCTAssertEqual(try window(fragments: 1, characters: 3, bytes: 5).window(original).context.map(\.text), ["é"])
        let withoutByteBound = try window(characters: 2).window(input(text: "я", context: ["👩‍👩‍👧‍👦"]))
        XCTAssertEqual(withoutByteBound.context.count, 1)
    }

    func testEmptyHistoryEmptyFragmentsAndZeroHistoryLimit() throws {
        XCTAssertTrue(try window().window(input()).context.isEmpty)
        XCTAssertTrue(try window(fragments: 0).window(input(context: ["old"])).context.isEmpty)
        let result = try window(fragments: 2, characters: 1, bytes: 1)
            .window(input(text: "x", context: ["old", "", ""]))
        XCTAssertEqual(result.context.map(\.text), ["", ""])
    }

    func testInvalidBoundsAndOversizedCurrentTextHaveTypedErrors() throws {
        for (fragments, characters, bytes) in [(-1, 10, 10), (0, 0, 10), (0, -1, 10), (0, 1, 0), (0, 1, -1)] {
            assertError(.invalidContextConfiguration) {
                try QualiaContextConfiguration(maximumFragments: fragments, maximumCharacters: characters, maximumUTF8Bytes: bytes)
            }
        }
        for context in [[], ["old"]] {
            assertError(.currentTextExceedsContextBounds) {
                try window(characters: 1).window(input(text: "XX", context: context))
            }
            assertError(.currentTextExceedsContextBounds) {
                try window(bytes: 1).window(input(text: "я", context: context))
            }
        }
        XCTAssertEqual(try window(fragments: Int.max, characters: Int.max, bytes: Int.max)
            .window(input(context: ["old"])).context.count, 1)
    }

    func testWindowDiagnosticsReportExactCountsAndTruncation() throws {
        let events = Locked<[QualiaPreparationDiagnostic]>([])
        let window = try window(fragments: 1, diagnostics: { event in events.mutate { $0.append(event) } })
        _ = try window.window(input(text: "я", context: ["ab", "é"]))
        guard case let .context(before, after, outcome) = try XCTUnwrap(events.value.first) else {
            return XCTFail("Expected context metadata")
        }
        XCTAssertEqual(before.fragments, 2)
        XCTAssertEqual(before.characters, 4)
        XCTAssertEqual(before.utf8Bytes, 6)
        XCTAssertEqual(after.fragments, 1)
        XCTAssertEqual(after.characters, 2)
        XCTAssertEqual(after.utf8Bytes, 4)
        XCTAssertEqual(outcome, .trimmed)
    }

    func testWindowDiagnosticsDistinguishUnchangedAndFailedPreparation() throws {
        let events = Locked<[QualiaPreparationDiagnostic]>([])
        let window = try window(characters: 1, diagnostics: { event in events.mutate { $0.append(event) } })
        _ = try window.window(input(text: "x"))
        assertError(.currentTextExceedsContextBounds) { try window.window(input(text: "XX")) }
        guard case let .context(before, after, outcome) = events.value[0],
              case let .context(failedBefore, failedAfter, failedOutcome) = events.value[1] else {
            return XCTFail("Expected context metadata")
        }
        XCTAssertEqual(before, after)
        XCTAssertEqual(outcome, .unchanged)
        XCTAssertEqual(failedBefore, failedAfter)
        XCTAssertEqual(failedOutcome, .currentTextTooLarge)
    }

    func testLanguageDiagnosticsCoverPolicySourceConfidenceAndFailure() throws {
        let events = Locked<[QualiaPreparationDiagnostic]>([])
        let sink: @Sendable (QualiaPreparationDiagnostic) -> Void = { event in events.mutate { $0.append(event) } }
        let allowed = try Set([language("en")])
        let explicit = try QualiaLanguageResolver(policy: .requireExplicit, minimumConfidence: 0.75, diagnostics: sink)
        _ = try explicit.resolve(for: input(language: "en"))
        assertError(.languageUndetermined) { try explicit.resolve(for: input()) }
        let preferred = try QualiaLanguageResolver(policy: .preferExplicitThenDetect(allowed: allowed), minimumConfidence: 0.75, diagnostics: sink)
        assertError(try .unsupportedLanguage(language("ru"))) { try preferred.resolve(for: input(language: "ru")) }
        for hypothesis in try [nil, detection("en", 0.2), detection("en", 0.9), detection("ru", 0.9)] {
            let resolver = try QualiaLanguageResolver(
                policy: .detect(allowed: allowed), minimumConfidence: 0.75,
                detector: FixtureDetector(result: hypothesis), diagnostics: sink
            )
            _ = try? resolver.resolve(for: input())
        }
        XCTAssertEqual(events.value, [
            .language(policy: .requireExplicit, source: .explicit, confidence: nil, outcome: .resolved),
            .language(policy: .requireExplicit, source: nil, confidence: nil, outcome: .undetermined),
            .language(policy: .preferExplicitThenDetect, source: .explicit, confidence: nil, outcome: .unsupported),
            .language(policy: .detect, source: .detected, confidence: nil, outcome: .undetermined),
            .language(policy: .detect, source: .detected, confidence: .belowThreshold, outcome: .undetermined),
            .language(policy: .detect, source: .detected, confidence: .meetsThreshold, outcome: .resolved),
            .language(policy: .detect, source: .detected, confidence: .meetsThreshold, outcome: .unsupported),
        ])
    }

    func testFixtureAnalyzerReceivesResolvedBoundedInputAndReturnsObservation() async throws {
        let fixture = try FixtureAnalyzer(languages: [language("ru")])
        let detector = FixtureDetector(result: try detection("ru", 0.9))
        let preparer = try preparer(
            policy: .preferExplicitThenDetect(allowed: [language("ru")]),
            detector: detector, fragments: 2, characters: 10, bytes: 20
        )
        let original = try input(text: "сейчас", context: ["old", "a", "b", "c"])
        let observation = try await analyze(original, preparer: preparer, fixture: fixture)
        let recordedInputs = await fixture.inputs
        let received = try XCTUnwrap(recordedInputs.first)
        XCTAssertEqual(received.context.map(\.text), ["b", "c"])
        XCTAssertEqual(received.language, try language("ru"))
        XCTAssertEqual(Data(received.text.utf8), Data(original.text.utf8))
        XCTAssertEqual(observation.inputID, original.id)
        XCTAssertEqual(observation.language, try language("ru"))
        XCTAssertEqual(observation.analyzer, fixture.identity)
        XCTAssertEqual(observation.dimensions.valence?.value, 0.6)
        XCTAssertEqual(detector.calls.value, ["сейчас"])
    }

    func testExplicitEnglishIsRejectedBeforeRussianFixtureOrDetectionForEveryPolicy() async throws {
        let english = try language("en")
        let russian = try language("ru")
        for policy: QualiaLanguagePolicy in [.requireExplicit, .detect(allowed: [russian]),
                                             .preferExplicitThenDetect(allowed: [english, russian])] {
            let fixture = try FixtureAnalyzer(languages: [russian])
            let detector = FixtureDetector(result: try detection("ru", 1))
            let preparer = try preparer(policy: policy, detector: detector)
            do {
                _ = try await analyze(input(language: "en"), preparer: preparer, fixture: fixture)
                XCTFail("Expected unsupported explicit language")
            } catch {
                XCTAssertEqual(error as? QualiaError, .unsupportedLanguage(english))
            }
            let count = await fixture.inputs.count
            XCTAssertEqual(count, 0)
            XCTAssertTrue(detector.calls.value.isEmpty)
        }
    }

    func testUndeterminedAndDetectedUnsupportedLanguageNeverReachFixture() async throws {
        for hypothesis in try [nil, detection("en", 0.1), detection("en", 0.9)] {
            let fixture = try FixtureAnalyzer(languages: [language("ru")])
            let preparer = try preparer(
                policy: .detect(allowed: [language("en"), language("ru")]),
                detector: FixtureDetector(result: hypothesis)
            )
            do {
                _ = try await analyze(input(), preparer: preparer, fixture: fixture)
                XCTFail("Expected language rejection")
            } catch {
                let expected: QualiaError = (hypothesis?.confidence ?? 0) >= 0.75
                    ? try .unsupportedLanguage(language("en")) : .languageUndetermined
                XCTAssertEqual(error as? QualiaError, expected)
            }
            let count = await fixture.inputs.count
            XCTAssertEqual(count, 0)
        }
    }

    func testContextDisabledAnalyzerRejectsRetainedHistoryBeforeInference() async throws {
        let fixture = try FixtureAnalyzer(languages: [language("en")], acceptsContext: false)
        do {
            _ = try await analyze(input(context: ["old"], language: "en"), preparer: preparer(), fixture: fixture)
            XCTFail("Expected unsupported context")
        } catch {
            XCTAssertEqual(error as? QualiaError, .unsupportedContext)
        }
        let rejectedCount = await fixture.inputs.count
        XCTAssertEqual(rejectedCount, 0)
        _ = try await analyze(input(context: ["old"], language: "en"), preparer: preparer(fragments: 0), fixture: fixture)
        let received = await fixture.inputs
        XCTAssertEqual(received.count, 1)
        XCTAssertTrue(received[0].context.isEmpty)
    }

    func testOversizedCurrentTextFailsBeforeFixtureInference() async throws {
        let fixture = try FixtureAnalyzer(languages: [language("en")])
        do {
            _ = try await analyze(input(text: "oversized", language: "en"), preparer: preparer(characters: 1), fixture: fixture)
            XCTFail("Expected context limit error")
        } catch {
            XCTAssertEqual(error as? QualiaError, .currentTextExceedsContextBounds)
        }
        let count = await fixture.inputs.count
        XCTAssertEqual(count, 0)
    }

    func testPreparerDoesNotAccumulateHistoryBetweenRequests() async throws {
        let fixture = try FixtureAnalyzer(languages: [language("en")])
        let preparer = try preparer()
        _ = try await analyze(input(context: ["previous"], language: "en"), preparer: preparer, fixture: fixture)
        _ = try await analyze(input(language: "en"), preparer: preparer, fixture: fixture)
        let received = await fixture.inputs
        XCTAssertEqual(received[0].context.count, 1)
        XCTAssertTrue(received[1].context.isEmpty)
        // This is stateless preparation, not evidence for QualiaSession.reset().
    }

    func testSharedPreparationIsSafeAcrossConcurrentRequests() async throws {
        let english = try language("en")
        let fixture = try FixtureAnalyzer(languages: [english])
        let detector = FixtureDetector(result: try detection("en", 0.9))
        let preparer = try preparer(policy: .detect(allowed: [english]), detector: detector, fragments: 1)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                let request = try input(id: "input-\(index)", text: "current-\(index)", context: ["old", "recent-\(index)"])
                group.addTask {
                    let prepared = try await preparer.prepare(request, for: fixture.capabilities)
                    XCTAssertEqual(prepared.id, request.id)
                    XCTAssertEqual(prepared.context.map(\.text), ["recent-\(index)"])
                    _ = try await fixture.analyze(prepared)
                }
            }
            try await group.waitForAll()
        }
        let received = await fixture.inputs
        XCTAssertEqual(Set(received.map(\.id)).count, 40)
        XCTAssertEqual(detector.calls.value.count, 40)
    }

    @MainActor
    func testPreparationRunsOffMainActorAndCancellationStopsBeforeInference() async throws {
        let started = expectation(description: "Detector started")
        let release = DispatchSemaphore(value: 0)
        let workerWasMain = Locked<Bool?>(nil)
        let english = try language("en")
        let result = try detection("en", 1)
        let detector = ClosureDetector { _ in
            workerWasMain.mutate { $0 = Thread.isMainThread }
            started.fulfill()
            _ = release.wait(timeout: .now() + 10)
            return result
        }
        let fixture = try FixtureAnalyzer(languages: [english])
        let preparer = try preparer(policy: .detect(allowed: [english]), detector: detector)
        let request = try input()
        let task = Task {
            let prepared = try await preparer.prepare(request, for: fixture.capabilities)
            return try await fixture.analyze(prepared)
        }
        await fulfillment(of: [started], timeout: 5)
        task.cancel()
        release.signal()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected; no prepared input escapes.
        }
        XCTAssertEqual(workerWasMain.value, false)
        let count = await fixture.inputs.count
        XCTAssertEqual(count, 0)
    }

    func testAlreadyCancelledRequestSkipsAllPreparation() async throws {
        let detector = FixtureDetector(result: try detection("en", 1))
        let preparer = try preparer(policy: .detect(allowed: [language("en")]), detector: detector)
        let fixture = try FixtureAnalyzer(languages: [language("en")])
        let request = try input()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await preparer.prepare(request, for: fixture.capabilities)
        }
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }
        XCTAssertTrue(detector.calls.value.isEmpty)
    }

    func testDiagnosticsContainNoTextIdentifiersOrOpaqueLanguageStrings() async throws {
        let secrets = ["CURRENT_PRIVATE_3a71", "HISTORY_PRIVATE_7b42", "ID_PRIVATE_4f99", "LANGUAGE_PRIVATE_fa88"]
        let events = Locked<[QualiaPreparationDiagnostic]>([])
        let sink: @Sendable (QualiaPreparationDiagnostic) -> Void = { event in events.mutate { $0.append(event) } }
        let resolver = try QualiaLanguageResolver(policy: .requireExplicit, minimumConfidence: 0.75, diagnostics: sink)
        let window = try window(fragments: 0, diagnostics: sink)
        let preparer = QualiaInputPreparer(languageResolver: resolver, contextWindow: window, diagnostics: sink)
        let fixture = try FixtureAnalyzer(languages: [language(secrets[3])])
        let request = try input(id: secrets[2], text: secrets[0], context: [secrets[1]], language: secrets[3])
        _ = try await analyze(request, preparer: preparer, fixture: fixture)
        let unsupportedFixture = try FixtureAnalyzer(languages: [language("ru")])
        do {
            _ = try await preparer.prepare(request, for: unsupportedFixture.capabilities)
            XCTFail("Expected language rejection")
        } catch {
            XCTAssertEqual(error as? QualiaError, try .unsupportedLanguage(language(secrets[3])))
        }
        XCTAssertEqual(events.value.count, 3)
        XCTAssertEqual(events.value.last, .analyzerRejected(.unsupportedLanguage))
        for event in events.value {
            assertNoStringPayload(event)
            for secret in secrets { XCTAssertFalse(String(reflecting: event).contains(secret)) }
        }
    }
}

// Private fixtures exercise the public preparation/analyzer contracts. Public
// QualiaTesting fixture infrastructure and session orchestration belong elsewhere.
private actor FixtureAnalyzer: QualiaAnalyzing {
    nonisolated let capabilities: QualiaAnalyzerCapabilities
    nonisolated let identity: QualiaAnalyzerIdentity
    private(set) var inputs: [QualiaInput] = []

    init(languages: Set<QualiaLanguage>, acceptsContext: Bool = true) throws {
        capabilities = QualiaAnalyzerCapabilities(languages: languages, dimensions: [.valence], signals: [],
                                                  acceptsContext: acceptsContext, execution: .onDevice)
        identity = try QualiaAnalyzerIdentity(identifier: "com.qualiakit.fixture.context-language", version: "1")
    }

    func analyze(_ input: QualiaInput) async throws -> QualiaObservation {
        try Task.checkCancellation()
        inputs.append(input)
        guard let language = input.language else { throw QualiaError.languageUndetermined }
        return QualiaObservation(inputID: input.id, dimensions: QualiaDimensions(valence: try QualiaScore(value: 0.6)),
                                 language: language, analyzer: identity)
    }
}

private struct FixtureDetector: QualiaLanguageDetecting {
    let result: QualiaLanguageDetection?
    let calls = Locked<[String]>([])
    func detectLanguage(in text: String) -> QualiaLanguageDetection? {
        calls.mutate { $0.append(text) }
        return result
    }
}

private struct ClosureDetector: QualiaLanguageDetecting {
    let detect: @Sendable (String) -> QualiaLanguageDetection?
    func detectLanguage(in text: String) -> QualiaLanguageDetection? { detect(text) }
}

private final class Locked<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value
    init(_ value: Value) { storage = value }
    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
    func mutate(_ body: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body(&storage)
    }
}

private func language(_ code: String) throws -> QualiaLanguage { try QualiaLanguage(rawValue: code) }
private func detection(_ code: String, _ confidence: Float) throws -> QualiaLanguageDetection {
    try QualiaLanguageDetection(language: language(code), confidence: confidence)
}
private func detectionPolicies() throws -> [QualiaLanguagePolicy] {
    try [.detect(allowed: [language("en")]), .preferExplicitThenDetect(allowed: [language("en")])]
}
private func resolver(
    _ policy: QualiaLanguagePolicy, detector: any QualiaLanguageDetecting = FixtureDetector(result: nil)
) throws -> QualiaLanguageResolver {
    try QualiaLanguageResolver(policy: policy, minimumConfidence: 0.75, detector: detector)
}
private func input(
    id: String = "current-id", text: String = "current", context: [String] = [], language code: String? = nil
) throws -> QualiaInput {
    try QualiaInput(id: QualiaInputID(rawValue: id), text: text,
                   context: context.enumerated().map { index, text in
                       try QualiaContextFragment(id: QualiaInputID(rawValue: "history-\(index)"), text: text)
                   }, language: code.map(language))
}
private func window(
    fragments: Int = 8, characters: Int = 1_000, bytes: Int? = nil,
    diagnostics: (@Sendable (QualiaPreparationDiagnostic) -> Void)? = nil
) throws -> QualiaContextWindow {
    try QualiaContextWindow(configuration: QualiaContextConfiguration(
        maximumFragments: fragments, maximumCharacters: characters, maximumUTF8Bytes: bytes
    ), diagnostics: diagnostics)
}
private func preparer(
    policy: QualiaLanguagePolicy = .requireExplicit,
    detector: any QualiaLanguageDetecting = FixtureDetector(result: nil),
    fragments: Int = 8, characters: Int = 1_000, bytes: Int? = nil
) throws -> QualiaInputPreparer {
    try QualiaInputPreparer(languageResolver: resolver(policy, detector: detector),
                           contextWindow: window(fragments: fragments, characters: characters, bytes: bytes))
}
private func analyze(
    _ input: QualiaInput, preparer: QualiaInputPreparer, fixture: FixtureAnalyzer
) async throws -> QualiaObservation {
    let prepared = try await preparer.prepare(input, for: fixture.capabilities)
    return try await fixture.analyze(prepared)
}
private func assertError<T>(
    _ expected: QualiaError, file: StaticString = #filePath, line: UInt = #line, _ body: () throws -> T
) {
    XCTAssertThrowsError(try body(), file: file, line: line) { error in
        XCTAssertEqual(error as? QualiaError, expected, file: file, line: line)
    }
}
private func assertNoStringPayload(_ value: Any, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertFalse(value is String, "Diagnostics must not carry arbitrary strings", file: file, line: line)
    for child in Mirror(reflecting: value).children { assertNoStringPayload(child.value, file: file, line: line) }
}
