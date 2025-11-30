import Qualia
import XCTest

/// Tests for NLTagger workarounds (stop-words, double negations, short text)
///
/// These tests verify the critical bug fixes for Apple's NLTagger
final class NLTaggerWorkaroundsTests: XCTestCase {

    var client: QualiaClient!

    override func setUpWithError() throws {
        // Use default NLTagger provider
        client = QualiaClient()
    }

    override func tearDownWithError() throws {
        client = nil
    }

    // MARK: - Short Text Preprocessing Tests

    func testShortTextWithoutPunctuation() async throws {
        // Test that short words like "good" get preprocessed with period
        let (emotion, score) = await client.analyze("good")

        XCTAssertNotEqual(score, 0.0, "Short positive text should return non-zero score")
        XCTAssertEqual(emotion, .positive, "Short positive text should be detected as positive")
    }

    func testShortTextWithPunctuation() async throws {
        // Text with punctuation should work without modification
        let (emotion, _) = await client.analyze("good!")

        XCTAssertEqual(emotion, .positive, "Short text with punctuation should be positive")
    }

    func testLongTextNotAffected() async throws {
        // Long text shouldn't be modified by preprocessing
        let (emotion, _) = await client.analyze("This is a longer sentence that should work fine")

        // Should get some sentiment (not necessarily positive/negative, but not error)
        XCTAssertTrue([.positive, .negative, .neutral].contains(emotion))
    }

    // MARK: - Stop-Word Filter Tests

    func testStopWordArticles() async throws {
        let articles = ["the", "a", "an"]

        for article in articles {
            let (emotion, score) = await client.analyze(article)

            XCTAssertEqual(emotion, .neutral, "'\(article)' should be neutral (stop-word)")
            XCTAssertEqual(score, 0.0, "'\(article)' should return 0.0 score")
        }
    }

    func testStopWordPronouns() async throws {
        let pronouns = ["it", "i", "you", "he", "she", "we", "they"]

        for pronoun in pronouns {
            let (emotion, score) = await client.analyze(pronoun)

            XCTAssertEqual(emotion, .neutral, "'\(pronoun)' should be neutral (stop-word)")
            XCTAssertEqual(score, 0.0, "'\(pronoun)' should return 0.0 score")
        }
    }

    func testStopWordAuxiliaryVerbs() async throws {
        let verbs = ["is", "am", "are", "was", "were", "have", "has", "had"]

        for verb in verbs {
            let (emotion, score) = await client.analyze(verb)

            XCTAssertEqual(emotion, .neutral, "'\(verb)' should be neutral (stop-word)")
            XCTAssertEqual(score, 0.0, "'\(verb)' should return 0.0 score")
        }
    }

    // MARK: - Double Negation Filter Tests

    func testDoubleNegationNotBad() async throws {
        let (emotion, score) = await client.analyze("not bad")

        XCTAssertEqual(emotion, .positive, "'not bad' should be positive (double negation)")
        XCTAssertEqual(score, 0.5, "'not bad' should return positive score")
    }

    func testDoubleNegationNotTerrible() async throws {
        let (emotion, score) = await client.analyze("not terrible")

        XCTAssertEqual(emotion, .positive, "'not terrible' should be positive (double negation)")
        XCTAssertEqual(score, 0.5, "'not terrible' should return positive score")
    }

    func testDoubleNegationInSentence() async throws {
        let (emotion, _) = await client.analyze("The movie was not bad at all")

        XCTAssertEqual(emotion, .positive, "Sentence with 'not bad' should be positive")
    }

    func testDoubleNegationNotAwful() async throws {
        let phrases = ["not awful", "not horrible", "not wrong", "not poor"]

        for phrase in phrases {
            let (emotion, _) = await client.analyze(phrase)
            XCTAssertEqual(emotion, .positive, "'\(phrase)' should be positive (double negation)")
        }
    }

    // MARK: - Combined Workarounds Test

    func testNormalPositiveText() async throws {
        // Ensure normal text still works
        let (emotion, _) = await client.analyze("I am happy")

        XCTAssertEqual(emotion, .positive, "Normal positive text should work")
    }

    func testNormalNegativeText() async throws {
        // Ensure normal negative text still works
        let (emotion, _) = await client.analyze("I am sad and depressed")

        XCTAssertEqual(emotion, .negative, "Normal negative text should work")
    }
}
