import Foundation
import XCTest
import QualiaKit

final class DomainModelTests: XCTestCase {
    func testMissingSignalDiffersFromZero() throws {
        let inputID = try QualiaInputID(rawValue: "fragment-1")
        let language = try QualiaLanguage(rawValue: "ru")
        let suspense = try QualiaSignal(rawValue: "suspense")
        let analyzer = try QualiaAnalyzerIdentity(
            identifier: "com.example.fixture-analyzer",
            version: "1"
        )

        let missing = QualiaObservation(
            inputID: inputID,
            language: language,
            analyzer: analyzer
        )
        let zero = QualiaObservation(
            inputID: inputID,
            signals: [suspense: try QualiaScore(value: 0)],
            language: language,
            analyzer: analyzer
        )

        XCTAssertNil(missing.signals[suspense])
        XCTAssertEqual(zero.signals[suspense]?.value, 0)
    }

    func testScoresAcceptClosedBoundsAndRejectInvalidValues() throws {
        XCTAssertEqual(try QualiaScore(value: 0).value, 0)
        XCTAssertEqual(try QualiaScore(value: 1, confidence: 0).value, 1)
        XCTAssertEqual(try QualiaScore(value: 0.5, confidence: 1).confidence, 1)

        assertQualiaError(.invalidScore) {
            try QualiaScore(value: -0.0001)
        }
        assertQualiaError(.invalidScore) {
            try QualiaScore(value: 1.0001)
        }
        assertQualiaError(.invalidScore) {
            try QualiaScore(value: .nan)
        }
        assertQualiaError(.invalidScore) {
            try QualiaScore(value: .infinity)
        }
        assertQualiaError(.invalidConfidence) {
            try QualiaScore(value: 0.5, confidence: -0.0001)
        }
        assertQualiaError(.invalidConfidence) {
            try QualiaScore(value: 0.5, confidence: 1.0001)
        }
        assertQualiaError(.invalidConfidence) {
            try QualiaScore(value: 0.5, confidence: .nan)
        }
    }

    func testValenceUsesNegativeNeutralPositiveAnchors() throws {
        let negative = QualiaDimensions(valence: try QualiaScore(value: 0))
        let neutral = QualiaDimensions(valence: try QualiaScore(value: 0.5))
        let positive = QualiaDimensions(valence: try QualiaScore(value: 1))

        XCTAssertEqual(negative.valence?.value, 0)
        XCTAssertEqual(neutral.valence?.value, 0.5)
        XCTAssertEqual(positive.valence?.value, 1)
    }

    func testIdentifiersFollowTheirDocumentedIdentityRules() throws {
        assertQualiaError(.invalidInputID) {
            try QualiaInputID(rawValue: " \n\t")
        }
        assertQualiaError(.invalidSignal) {
            try QualiaSignal(rawValue: "\u{00A0}")
        }
        assertQualiaError(.invalidLanguage) {
            try QualiaLanguage(rawValue: "")
        }

        let inputID = try QualiaInputID(rawValue: "  Event-A  ")
        let namespaced = try QualiaSignal(rawValue: "  com.Example.Signal  ")
        let upper = try QualiaSignal(rawValue: "Signal")
        let lower = try QualiaSignal(rawValue: "signal")
        let language = try QualiaLanguage(rawValue: "RU-latn")
        let upperLanguage = try QualiaLanguage(rawValue: "RU")
        let lowerLanguage = try QualiaLanguage(rawValue: "ru")

        XCTAssertEqual(inputID.rawValue, "  Event-A  ")
        XCTAssertEqual(namespaced.rawValue, "  com.Example.Signal  ")
        XCTAssertEqual(language.rawValue, "RU-latn")
        XCTAssertNotEqual(upper, lower)
        XCTAssertEqual(Set([upper, lower]).count, 2)
        XCTAssertNotEqual(upperLanguage, lowerLanguage)
        XCTAssertEqual(upperLanguage.rawValue, "RU")
        XCTAssertEqual(Set([upperLanguage, lowerLanguage]).count, 2)
    }

    func testInputRejectsEmptyAndWhitespaceOnlyTextWithoutChangingValidText() throws {
        let inputID = try QualiaInputID(rawValue: "fragment-1")

        assertQualiaError(.emptyInput) {
            try QualiaInput(id: inputID, text: "")
        }
        assertQualiaError(.emptyInput) {
            try QualiaInput(id: inputID, text: " \n\t\u{00A0}")
        }

        let input = try QualiaInput(id: inputID, text: "  retained exactly  ")
        XCTAssertEqual(input.text, "  retained exactly  ")
        XCTAssertTrue(input.context.isEmpty)
        XCTAssertNil(input.language)
    }

    func testAnalyzerIdentityIsValidatedWithoutNormalizingValues() throws {
        assertQualiaError(.invalidAnalyzerIdentifier) {
            try QualiaAnalyzerIdentity(identifier: " ", version: "1")
        }
        assertQualiaError(.invalidAnalyzerVersion) {
            try QualiaAnalyzerIdentity(identifier: "analyzer", version: "\n")
        }
        let identity = try QualiaAnalyzerIdentity(
            identifier: "  com.Example.Analyzer  ",
            version: "  V1  "
        )

        XCTAssertEqual(identity.identifier, "  com.Example.Analyzer  ")
        XCTAssertEqual(identity.version, "  V1  ")
    }

    func testCapabilitiesUseTheApprovedMinimalShape() throws {
        let russian = try QualiaLanguage(rawValue: "ru")
        let customSignal = try QualiaSignal(rawValue: "com.example.signal")
        let capabilities = QualiaAnalyzerCapabilities(
            languages: [russian],
            dimensions: [.valence],
            signals: [customSignal],
            acceptsContext: false,
            execution: .onDevice
        )

        XCTAssertEqual(capabilities.languages, [russian])
        XCTAssertEqual(capabilities.dimensions, [.valence])
        XCTAssertEqual(capabilities.signals, [customSignal])
        XCTAssertFalse(capabilities.acceptsContext)
        XCTAssertEqual(capabilities.execution, .onDevice)
    }

    func testObservationCarriesOnlyDomainValuesAndProvenance() throws {
        let inputID = try QualiaInputID(rawValue: "fragment-1")
        let language = try QualiaLanguage(rawValue: "ru")
        let analyzer = try QualiaAnalyzerIdentity(
            identifier: "com.example.fixture-analyzer",
            version: "1"
        )
        let valence = try QualiaScore(value: 0.25, confidence: 0.8)
        let suspenseSignal = try QualiaSignal(rawValue: "suspense")
        let suspense = try QualiaScore(value: 0.9)

        let observation = QualiaObservation(
            inputID: inputID,
            dimensions: .init(valence: valence),
            signals: [suspenseSignal: suspense],
            language: language,
            analyzer: analyzer
        )

        XCTAssertEqual(observation.inputID, inputID)
        XCTAssertEqual(observation.dimensions.valence, valence)
        XCTAssertEqual(observation.signals[suspenseSignal], suspense)
        XCTAssertEqual(observation.language, language)
        XCTAssertEqual(observation.analyzer, analyzer)
    }

    func testApprovedCodableValuesRoundTripAndDecodedValuesRemainValidated() throws {
        let inputID = try QualiaInputID(rawValue: "fragment-1")
        let context = QualiaContextFragment(id: inputID, text: "sensitive context")
        let signal = try QualiaSignal(rawValue: "com.example.collision")
        let score = try QualiaScore(value: 0.75, confidence: 0.5)

        try assertRoundTrip(inputID)
        try assertRoundTrip(context)
        try assertRoundTrip(signal)
        try assertRoundTrip(score)

        XCTAssertThrowsError(
            try JSONDecoder().decode(
                QualiaInputID.self,
                from: Data(#"{"rawValue":"   "}"#.utf8)
            )
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                QualiaScore.self,
                from: Data(#"{"value":2}"#.utf8)
            )
        )
    }

    func testPublicDomainValuesAreSendable() {
        assertSendable(QualiaInputID.self)
        assertSendable(QualiaContextFragment.self)
        assertSendable(QualiaInput.self)
        assertSendable(QualiaLanguage.self)
        assertSendable(QualiaSignal.self)
        assertSendable(QualiaScore.self)
        assertSendable(QualiaDimension.self)
        assertSendable(QualiaDimensions.self)
        assertSendable(QualiaAnalyzerIdentity.self)
        assertSendable(QualiaAnalyzerCapabilities.self)
        assertSendable(QualiaExecutionMode.self)
        assertSendable(QualiaObservation.self)
        assertSendable(QualiaError.self)
    }

    func testSensitiveDomainContainersAreNotCodable() {
        let inputType: Any.Type = QualiaInput.self
        let observationType: Any.Type = QualiaObservation.self

        XCTAssertFalse(inputType is any Encodable.Type)
        XCTAssertFalse(inputType is any Decodable.Type)
        XCTAssertFalse(observationType is any Encodable.Type)
        XCTAssertFalse(observationType is any Decodable.Type)
    }

    private func assertQualiaError<T>(
        _ expected: QualiaError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () throws -> T
    ) {
        XCTAssertThrowsError(try operation(), file: file, line: line) { error in
            XCTAssertEqual(error as? QualiaError, expected, file: file, line: line)
        }
    }

    private func assertRoundTrip<T: Codable & Equatable>(
        _ value: T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let encoded = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(T.self, from: encoded)
        XCTAssertEqual(decoded, value, file: file, line: line)
    }

    private func assertSendable<T: Sendable>(_: T.Type) {}
}
