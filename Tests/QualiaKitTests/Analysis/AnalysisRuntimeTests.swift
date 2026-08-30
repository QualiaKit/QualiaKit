import XCTest
@testable import QualiaKit

final class AnalysisRuntimeTests: XCTestCase {
    func testUnsupportedPrimaryIsSkippedAndFallbackIdentityIsPreserved() async throws {
        let russian = language("ru")
        let english = language("en")
        let primaryIdentity = identity("com.example.primary")
        let fallbackIdentity = identity("com.example.fallback")
        let primary = TestAnalyzer(
            capabilities: capabilities(languages: [russian]),
            behavior: .succeed(identity: primaryIdentity, language: russian)
        )
        let fallback = TestAnalyzer(
            capabilities: capabilities(languages: [english]),
            behavior: .succeed(identity: fallbackIdentity, language: english)
        )
        let analyzer = try FallbackAnalyzer(
            primary: primary,
            fallback: fallback,
            causes: [.unsupportedLanguage]
        )

        let observation = try await analyzer.analyze(input(language: english))

        XCTAssertEqual(observation.analyzer, fallbackIdentity)
        let primaryInvocationCount = await primary.invocationCount
        let fallbackInvocationCount = await fallback.invocationCount
        XCTAssertEqual(primaryInvocationCount, 0)
        XCTAssertEqual(fallbackInvocationCount, 1)
    }

    func testInvalidAnalyzerOutputIsNotMaskedByFallback() async throws {
        let english = language("en")
        let primaryIdentity = identity("com.example.primary")
        let fallbackIdentity = identity("com.example.fallback")
        let primary = TestAnalyzer(
            capabilities: capabilities(languages: [english]),
            behavior: .fail(.invalidAnalyzerOutput(identity: primaryIdentity))
        )
        let fallback = TestAnalyzer(
            capabilities: capabilities(languages: [english]),
            behavior: .succeed(identity: fallbackIdentity, language: english)
        )
        let analyzer = try FallbackAnalyzer(
            primary: primary,
            fallback: fallback,
            causes: [.unsupportedLanguage]
        )

        do {
            _ = try await analyzer.analyze(input(language: english))
            XCTFail("Expected invalid analyzer output")
        } catch let error as QualiaError {
            XCTAssertEqual(error, .invalidAnalyzerOutput(identity: primaryIdentity))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let primaryInvocationCount = await primary.invocationCount
        let fallbackInvocationCount = await fallback.invocationCount
        XCTAssertEqual(primaryInvocationCount, 1)
        XCTAssertEqual(fallbackInvocationCount, 0)
    }

    func testCancellationRemainsCancellationAndDoesNotInvokeFallback() async throws {
        let english = language("en")
        let primary = TestAnalyzer(
            capabilities: capabilities(languages: [english]),
            behavior: .waitForCancellation
        )
        let fallback = TestAnalyzer(
            capabilities: capabilities(languages: [english]),
            behavior: .succeed(
                identity: identity("com.example.fallback"),
                language: english
            )
        )
        let analyzer = try FallbackAnalyzer(
            primary: primary,
            fallback: fallback,
            causes: [.languageUndetermined, .unsupportedLanguage, .analyzerUnavailable]
        )
        let task = Task {
            try await analyzer.analyze(input(language: english))
        }

        await primary.waitUntilInvoked()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let fallbackInvocationCount = await fallback.invocationCount
        XCTAssertEqual(fallbackInvocationCount, 0)
    }

    func testMismatchedObservationInputIDIsRejectedWithoutFallback() async throws {
        let english = language("en")
        let primaryIdentity = identity("com.example.primary")
        let unexpectedObservation = QualiaObservation(
            inputID: inputID("input-b"),
            language: english,
            analyzer: primaryIdentity
        )
        let primary = TestAnalyzer(
            capabilities: capabilities(languages: [english]),
            behavior: .returnObservation(unexpectedObservation)
        )
        let fallback = TestAnalyzer(
            capabilities: capabilities(languages: [english]),
            behavior: .succeed(
                identity: identity("com.example.fallback"),
                language: english
            )
        )
        let analyzer = try FallbackAnalyzer(
            primary: primary,
            fallback: fallback,
            causes: [.languageUndetermined, .unsupportedLanguage, .analyzerUnavailable]
        )

        do {
            _ = try await analyzer.analyze(input(id: "input-a", language: english))
            XCTFail("Expected contract validation failure")
        } catch let error as QualiaError {
            XCTAssertEqual(error, .invalidAnalyzerOutput(identity: primaryIdentity))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let fallbackInvocationCount = await fallback.invocationCount
        XCTAssertEqual(fallbackInvocationCount, 0)
    }

    func testEachConfiguredFallbackCauseCanInvokeTheSecondaryAnalyzer() async throws {
        let english = language("en")
        let fallbackIdentity = identity("com.example.fallback")
        let cases: [(QualiaFallbackCause, QualiaError, QualiaLanguage?)] = [
            (.languageUndetermined, .languageUndetermined, nil),
            (.unsupportedLanguage, .unsupportedLanguage(english), english),
            (
                .analyzerUnavailable,
                .analyzerUnavailable(identity: identity("com.example.primary")),
                english
            ),
        ]

        for (cause, error, inputLanguage) in cases {
            let primary = TestAnalyzer(
                capabilities: capabilities(languages: [english]),
                behavior: .fail(error)
            )
            let fallback = TestAnalyzer(
                capabilities: capabilities(languages: [english]),
                behavior: .succeed(identity: fallbackIdentity, language: english)
            )
            let analyzer = try FallbackAnalyzer(
                primary: primary,
                fallback: fallback,
                causes: [cause]
            )

            let observation = try await analyzer.analyze(input(language: inputLanguage))

            XCTAssertEqual(observation.analyzer, fallbackIdentity)
            let primaryInvocationCount = await primary.invocationCount
            let fallbackInvocationCount = await fallback.invocationCount
            XCTAssertEqual(primaryInvocationCount, 1)
            XCTAssertEqual(fallbackInvocationCount, 1)
        }
    }

    func testUnconfiguredTypedCauseDoesNotInvokeFallback() async throws {
        let english = language("en")
        let unavailableIdentity = identity("com.example.primary")
        let primary = TestAnalyzer(
            capabilities: capabilities(languages: [english]),
            behavior: .fail(.analyzerUnavailable(identity: unavailableIdentity))
        )
        let fallback = TestAnalyzer(
            capabilities: capabilities(languages: [english]),
            behavior: .succeed(
                identity: identity("com.example.fallback"),
                language: english
            )
        )
        let analyzer = try FallbackAnalyzer(
            primary: primary,
            fallback: fallback,
            causes: [.unsupportedLanguage]
        )

        do {
            _ = try await analyzer.analyze(input(language: english))
            XCTFail("Expected unavailable analyzer error")
        } catch let error as QualiaError {
            XCTAssertEqual(error, .analyzerUnavailable(identity: unavailableIdentity))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let fallbackInvocationCount = await fallback.invocationCount
        XCTAssertEqual(fallbackInvocationCount, 0)
    }

    func testFallbackRequiresMatchingOutputAndContextCapabilities() throws {
        let english = language("en")
        let base = capabilities(languages: [english])
        let primary = TestAnalyzer(capabilities: base, behavior: .waitForCancellation)

        let differentDimensions = TestAnalyzer(
            capabilities: capabilities(languages: [english], dimensions: []),
            behavior: .waitForCancellation
        )
        assertIncompatibleFallback(primary: primary, fallback: differentDimensions)

        let differentSignals = TestAnalyzer(
            capabilities: capabilities(
                languages: [english],
                signals: [signal("com.example.signal")]
            ),
            behavior: .waitForCancellation
        )
        assertIncompatibleFallback(primary: primary, fallback: differentSignals)

        let differentContext = TestAnalyzer(
            capabilities: capabilities(languages: [english], acceptsContext: true),
            behavior: .waitForCancellation
        )
        assertIncompatibleFallback(primary: primary, fallback: differentContext)
    }

    func testFallbackUnionsLanguagesAndCombinesExecutionModes() throws {
        let russian = language("ru")
        let english = language("en")
        let primary = TestAnalyzer(
            capabilities: capabilities(languages: [russian], execution: .onDevice),
            behavior: .waitForCancellation
        )
        let fallback = TestAnalyzer(
            capabilities: capabilities(languages: [english], execution: .remote),
            behavior: .waitForCancellation
        )

        let analyzer = try FallbackAnalyzer(
            primary: primary,
            fallback: fallback,
            causes: [.unsupportedLanguage]
        )

        XCTAssertEqual(analyzer.capabilities.languages, [russian, english])
        XCTAssertEqual(analyzer.capabilities.dimensions, [.valence])
        XCTAssertEqual(analyzer.capabilities.signals, [])
        XCTAssertFalse(analyzer.capabilities.acceptsContext)
        XCTAssertEqual(analyzer.capabilities.execution, .hybrid)
    }

    func testFallbackDoesNotAdvertiseFallbackOnlyLanguagesWithoutUnsupportedLanguageCause() throws {
        let russian = language("ru")
        let english = language("en")
        let primary = TestAnalyzer(
            capabilities: capabilities(languages: [russian]),
            behavior: .waitForCancellation
        )
        let fallback = TestAnalyzer(
            capabilities: capabilities(languages: [english]),
            behavior: .waitForCancellation
        )

        let analyzer = try FallbackAnalyzer(
            primary: primary,
            fallback: fallback,
            causes: [.analyzerUnavailable]
        )

        XCTAssertEqual(analyzer.capabilities.languages, [russian])
    }

    func testFallbackWithEmptyCausesKeepsPrimaryExecutionMode() throws {
        let english = language("en")
        let primary = TestAnalyzer(
            capabilities: capabilities(languages: [english], execution: .onDevice),
            behavior: .waitForCancellation
        )
        let fallback = TestAnalyzer(
            capabilities: capabilities(languages: [english], execution: .remote),
            behavior: .waitForCancellation
        )

        let analyzer = try FallbackAnalyzer(
            primary: primary,
            fallback: fallback,
            causes: []
        )

        XCTAssertEqual(analyzer.capabilities.execution, .onDevice)
    }

    func testUnsupportedContextNeverStartsFallback() async throws {
        let english = language("en")
        let primary = TestAnalyzer(
            capabilities: capabilities(languages: [english]),
            behavior: .waitForCancellation
        )
        let fallback = TestAnalyzer(
            capabilities: capabilities(languages: [english]),
            behavior: .waitForCancellation
        )
        let analyzer = try FallbackAnalyzer(
            primary: primary,
            fallback: fallback,
            causes: [.languageUndetermined, .unsupportedLanguage, .analyzerUnavailable]
        )
        let context = QualiaContextFragment(id: inputID("context"), text: "Earlier text")

        do {
            _ = try await analyzer.analyze(input(language: english, context: [context]))
            XCTFail("Expected unsupported context")
        } catch let error as QualiaError {
            XCTAssertEqual(error, .unsupportedContext)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let primaryInvocationCount = await primary.invocationCount
        let fallbackInvocationCount = await fallback.invocationCount
        XCTAssertEqual(primaryInvocationCount, 0)
        XCTAssertEqual(fallbackInvocationCount, 0)
    }

    func testUnsupportedInputStructureNeverStartsFallback() async throws {
        let english = language("en")
        let primary = TestAnalyzer(
            capabilities: capabilities(languages: [english]),
            behavior: .fail(.unsupportedInputStructure)
        )
        let fallback = TestAnalyzer(
            capabilities: capabilities(languages: [english]),
            behavior: .succeed(
                identity: identity("com.example.fallback"),
                language: english
            )
        )
        let analyzer = try FallbackAnalyzer(
            primary: primary,
            fallback: fallback,
            causes: [.languageUndetermined, .unsupportedLanguage, .analyzerUnavailable]
        )

        do {
            _ = try await analyzer.analyze(input(language: english))
            XCTFail("Expected unsupported input structure")
        } catch let error as QualiaError {
            XCTAssertEqual(error, .unsupportedInputStructure)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let fallbackInvocationCount = await fallback.invocationCount
        XCTAssertEqual(fallbackInvocationCount, 0)
    }

    func testOutputMustStayWithinAdvertisedCapabilities() async throws {
        let english = language("en")
        let analyzerIdentity = identity("com.example.primary")
        let undeclaredSignal = signal("com.example.undeclared")
        let observation = QualiaObservation(
            inputID: inputID("input"),
            signals: [undeclaredSignal: try QualiaScore(value: 1)],
            language: english,
            analyzer: analyzerIdentity
        )
        let analyzer = TestAnalyzer(
            capabilities: capabilities(languages: [english], dimensions: [], signals: []),
            behavior: .returnObservation(observation)
        )

        do {
            _ = try await QualiaAnalyzerContract.analyze(
                analyzer,
                input: input(language: english)
            )
            XCTFail("Expected invalid analyzer output")
        } catch let error as QualiaError {
            XCTAssertEqual(error, .invalidAnalyzerOutput(identity: analyzerIdentity))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testOutputLanguageAndDimensionsMustBeAdvertised() async throws {
        let english = language("en")
        let russian = language("ru")
        let analyzerIdentity = identity("com.example.primary")
        let unexpectedLanguage = QualiaObservation(
            inputID: inputID("input"),
            language: russian,
            analyzer: analyzerIdentity
        )
        let undeclaredDimension = QualiaObservation(
            inputID: inputID("input"),
            dimensions: QualiaDimensions(valence: try QualiaScore(value: 0.5)),
            language: english,
            analyzer: analyzerIdentity
        )

        for observation in [unexpectedLanguage, undeclaredDimension] {
            let analyzer = TestAnalyzer(
                capabilities: capabilities(
                    languages: [english],
                    dimensions: [],
                    signals: []
                ),
                behavior: .returnObservation(observation)
            )

            do {
                _ = try await QualiaAnalyzerContract.analyze(
                    analyzer,
                    input: input(language: english)
                )
                XCTFail("Expected invalid analyzer output")
            } catch let error as QualiaError {
                XCTAssertEqual(error, .invalidAnalyzerOutput(identity: analyzerIdentity))
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testObservationLanguageMustMatchExplicitInputLanguage() async throws {
        let english = language("en")
        let russian = language("ru")
        let analyzerIdentity = identity("com.example.primary")
        let observation = QualiaObservation(
            inputID: inputID("input"),
            language: russian,
            analyzer: analyzerIdentity
        )
        let analyzer = TestAnalyzer(
            capabilities: capabilities(languages: [english, russian], dimensions: []),
            behavior: .returnObservation(observation)
        )

        do {
            _ = try await QualiaAnalyzerContract.analyze(
                analyzer,
                input: input(language: english)
            )
            XCTFail("Expected explicit language mismatch")
        } catch let error as QualiaError {
            XCTAssertEqual(error, .invalidAnalyzerOutput(identity: analyzerIdentity))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testContractPrefersCancellationWhenAnalyzerThrowsAnotherError() async throws {
        let english = language("en")
        let analyzer = TestAnalyzer(
            capabilities: capabilities(languages: [english]),
            behavior: .replaceCancellation(with: .languageUndetermined)
        )
        let task = Task {
            try await QualiaAnalyzerContract.analyze(
                analyzer,
                input: input(language: english)
            )
        }

        await analyzer.waitUntilInvoked()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testAppleAnalyzerDeclaresMinimalCapabilities() {
        let analyzer = AppleSentimentAnalyzer()

        XCTAssertEqual(analyzer.capabilities.languages, [language("en")])
        XCTAssertEqual(analyzer.capabilities.dimensions, [.valence])
        XCTAssertEqual(analyzer.capabilities.signals, [])
        XCTAssertFalse(analyzer.capabilities.acceptsContext)
        XCTAssertEqual(analyzer.capabilities.execution, .onDevice)
    }

    func testAppleAnalyzerRequiresExplicitEnglishAndRejectsContext() async throws {
        let analyzer = AppleSentimentAnalyzer()

        do {
            _ = try await analyzer.analyze(input(language: nil))
            XCTFail("Expected undetermined language")
        } catch let error as QualiaError {
            XCTAssertEqual(error, .languageUndetermined)
        }

        let uppercaseEnglish = language("EN")
        do {
            _ = try await analyzer.analyze(input(language: uppercaseEnglish))
            XCTFail("Expected exact language mismatch")
        } catch let error as QualiaError {
            XCTAssertEqual(error, .unsupportedLanguage(uppercaseEnglish))
        }

        let context = QualiaContextFragment(id: inputID("context"), text: "Earlier text")
        do {
            _ = try await analyzer.analyze(
                input(language: language("en"), context: [context])
            )
            XCTFail("Expected unsupported context")
        } catch let error as QualiaError {
            XCTAssertEqual(error, .unsupportedContext)
        }
    }

    func testAppleScoreNormalizationUsesDomainValenceAnchors() throws {
        let negative = try AppleSentimentAnalyzer.normalizedValence(fromAppleScore: -1)
        let neutral = try AppleSentimentAnalyzer.normalizedValence(fromAppleScore: 0)
        let positive = try AppleSentimentAnalyzer.normalizedValence(fromAppleScore: 1)

        XCTAssertEqual(negative.value, 0)
        XCTAssertEqual(neutral.value, 0.5)
        XCTAssertEqual(positive.value, 1)
        XCTAssertNil(negative.confidence)
        XCTAssertNil(neutral.confidence)
        XCTAssertNil(positive.confidence)

        XCTAssertThrowsError(
            try AppleSentimentAnalyzer.normalizedValence(fromAppleScore: -.infinity)
        )
        XCTAssertThrowsError(
            try AppleSentimentAnalyzer.normalizedValence(fromAppleScore: 1.01)
        )
    }

    func testAppleAnalyzerProducesValidatedEnglishObservation() async throws {
        let analyzer = AppleSentimentAnalyzer()
        let request = input(text: "This is a wonderful day.", language: language("en"))

        let observation = try await analyzer.analyze(request)

        XCTAssertEqual(observation.inputID, request.id)
        XCTAssertEqual(observation.language, language("en"))
        XCTAssertEqual(
            observation.analyzer,
            identity("com.qualiakit.apple-sentiment")
        )
        XCTAssertNotNil(observation.dimensions.valence)
        XCTAssertNil(observation.dimensions.valence?.confidence)
        XCTAssertTrue(observation.signals.isEmpty)
    }

    func testAppleAnalyzerAcceptsMultipleSentencesInOneParagraph() async throws {
        let probe = SentimentScorerProbe(score: 0.4)
        let analyzer = AppleSentimentAnalyzer { text in
            await probe.score(text)
        }
        let request = input(
            text: "The opening is hopeful. The ending remains uncertain.",
            language: language("en")
        )

        let observation = try await analyzer.analyze(request)

        XCTAssertEqual(observation.dimensions.valence?.value, 0.7)
        let invocationCount = await probe.invocationCount
        XCTAssertEqual(invocationCount, 1)
    }

    func testAppleAnalyzerRejectsMultipleNonemptyParagraphsBeforeScoring() async throws {
        let probe = SentimentScorerProbe(score: 0)
        let analyzer = AppleSentimentAnalyzer { text in
            await probe.score(text)
        }
        let texts = [
            "This is wonderful.\r\n\r\nBut the ending is terrible.",
            "This is wonderful.\u{2029}But the ending is terrible.",
        ]

        for (index, text) in texts.enumerated() {
            do {
                _ = try await analyzer.analyze(
                    input(id: "multi-paragraph-\(index)", text: text, language: language("en"))
                )
                XCTFail("Expected unsupported input structure")
            } catch let error as QualiaError {
                XCTAssertEqual(error, .unsupportedInputStructure)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
        let invocationCount = await probe.invocationCount
        XCTAssertEqual(invocationCount, 0)
    }

    func testAppleAnalyzerAllowsTrailingParagraphSeparators() async throws {
        let probe = SentimentScorerProbe(score: 0)
        let analyzer = AppleSentimentAnalyzer { text in
            await probe.score(text)
        }

        let observation = try await analyzer.analyze(
            input(text: "One paragraph with a trailing separator.\r\n\r\n", language: language("en"))
        )

        XCTAssertEqual(observation.dimensions.valence?.value, 0.5)
        let invocationCount = await probe.invocationCount
        XCTAssertEqual(invocationCount, 1)
    }

    func testAppleAnalyzerIsShareableAcrossConcurrentCalls() async throws {
        let analyzer = AppleSentimentAnalyzer()

        let observations = try await withThrowingTaskGroup(
            of: QualiaObservation.self,
            returning: [QualiaObservation].self
        ) { group in
            for index in 0..<8 {
                group.addTask {
                    try await analyzer.analyze(
                        input(
                            id: "input-\(index)",
                            text: "This is a good day number \(index).",
                            language: language("en")
                        )
                    )
                }
            }

            var results: [QualiaObservation] = []
            for try await observation in group {
                results.append(observation)
            }
            return results
        }

        XCTAssertEqual(observations.count, 8)
        XCTAssertEqual(Set(observations.map(\.inputID)).count, 8)
    }

    private func assertIncompatibleFallback(
        primary: any QualiaAnalyzing,
        fallback: any QualiaAnalyzing,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(
            try FallbackAnalyzer(primary: primary, fallback: fallback, causes: []),
            file: file,
            line: line
        ) { error in
            XCTAssertEqual(
                error as? QualiaError,
                .incompatibleFallbackCapabilities,
                file: file,
                line: line
            )
        }
    }
}

private actor TestAnalyzer: QualiaAnalyzing {
    enum Behavior: Sendable {
        case succeed(identity: QualiaAnalyzerIdentity, language: QualiaLanguage)
        case returnObservation(QualiaObservation)
        case fail(QualiaError)
        case waitForCancellation
        case replaceCancellation(with: QualiaError)
    }

    nonisolated let capabilities: QualiaAnalyzerCapabilities
    private let behavior: Behavior
    private(set) var invocationCount = 0
    private var invocationWaiters: [CheckedContinuation<Void, Never>] = []

    init(capabilities: QualiaAnalyzerCapabilities, behavior: Behavior) {
        self.capabilities = capabilities
        self.behavior = behavior
    }

    func analyze(_ input: QualiaInput) async throws -> QualiaObservation {
        invocationCount += 1
        let waiters = invocationWaiters
        invocationWaiters.removeAll()
        waiters.forEach { $0.resume() }

        switch behavior {
        case let .succeed(identity, language):
            return QualiaObservation(
                inputID: input.id,
                dimensions: capabilities.dimensions.contains(.valence)
                    ? QualiaDimensions(valence: try QualiaScore(value: 0.5))
                    : QualiaDimensions(),
                language: language,
                analyzer: identity
            )
        case let .returnObservation(observation):
            return observation
        case let .fail(error):
            throw error
        case .waitForCancellation:
            try await Task.sleep(nanoseconds: 60_000_000_000)
            throw CancellationError()
        case let .replaceCancellation(error):
            do {
                try await Task.sleep(nanoseconds: 60_000_000_000)
            } catch {
                throw error
            }
            throw error
        }
    }

    func waitUntilInvoked() async {
        if invocationCount > 0 {
            return
        }
        await withCheckedContinuation { continuation in
            invocationWaiters.append(continuation)
        }
    }
}

private actor SentimentScorerProbe {
    private let configuredScore: Float
    private(set) var invocationCount = 0

    init(score: Float) {
        configuredScore = score
    }

    func score(_ text: String) -> Float {
        invocationCount += 1
        return configuredScore
    }
}

private func capabilities(
    languages: Set<QualiaLanguage>,
    dimensions: Set<QualiaDimension> = [.valence],
    signals: Set<QualiaSignal> = [],
    acceptsContext: Bool = false,
    execution: QualiaExecutionMode = .onDevice
) -> QualiaAnalyzerCapabilities {
    QualiaAnalyzerCapabilities(
        languages: languages,
        dimensions: dimensions,
        signals: signals,
        acceptsContext: acceptsContext,
        execution: execution
    )
}

private func input(
    id: String = "input",
    text: String = "A meaningful text.",
    language: QualiaLanguage?,
    context: [QualiaContextFragment] = []
) -> QualiaInput {
    try! QualiaInput(
        id: inputID(id),
        text: text,
        context: context,
        language: language
    )
}

private func inputID(_ value: String) -> QualiaInputID {
    try! QualiaInputID(rawValue: value)
}

private func language(_ value: String) -> QualiaLanguage {
    try! QualiaLanguage(rawValue: value)
}

private func signal(_ value: String) -> QualiaSignal {
    try! QualiaSignal(rawValue: value)
}

private func identity(_ identifier: String) -> QualiaAnalyzerIdentity {
    try! QualiaAnalyzerIdentity(identifier: identifier, version: "1")
}
