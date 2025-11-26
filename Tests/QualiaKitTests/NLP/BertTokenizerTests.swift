import XCTest

@testable import QualiaKit

final class BertTokenizerTests: XCTestCase {

    var tokenizer: BertTokenizer!
    var vocabURL: URL!

    override func setUpWithError() throws {
        // Get test vocab file from bundle
        let bundle = Bundle.module
        guard
            let url = bundle.url(
                forResource: "test_vocab", withExtension: "txt", subdirectory: "Resources")
        else {
            XCTFail("Could not find test_vocab.txt in test resources")
            return
        }
        vocabURL = url
        tokenizer = try BertTokenizer(vocabURL: vocabURL, maxSequenceLength: 16)
    }

    override func tearDownWithError() throws {
        tokenizer = nil
        vocabURL = nil
    }

    // MARK: - Vocabulary Loading Tests

    func testVocabularyLoading() throws {
        XCTAssertNotNil(tokenizer, "Tokenizer should be initialized")
        // Vocabulary loading happens in init, if we got here it worked
    }

    func testInvalidVocabularyURL() {
        let invalidURL = URL(fileURLWithPath: "/nonexistent/vocab.txt")
        XCTAssertThrowsError(try BertTokenizer(vocabURL: invalidURL)) { error in
            XCTAssertTrue(error is CocoaError, "Should throw file reading error")
        }
    }

    // MARK: - Tokenization Tests

    func testBasicTokenization() {
        let (inputIds, attentionMask) = tokenizer.tokenize(text: "the")

        // Should have [CLS], "the", [SEP], and padding
        XCTAssertEqual(inputIds.count, 16, "Should have 16 tokens (max sequence length)")
        XCTAssertEqual(attentionMask.count, 16, "Attention mask should have 16 elements")

        // First should be [CLS] (id 2), then "the" (id 24), then [SEP] (id 3)
        XCTAssertEqual(inputIds[0], 2, "First token should be [CLS]")
        XCTAssertEqual(inputIds[1], 24, "Second token should be 'the'")
        XCTAssertEqual(inputIds[2], 3, "Third token should be [SEP]")

        // Attention mask: 1 for real tokens, 0 for padding
        XCTAssertEqual(attentionMask[0], 1, "Attention for [CLS] should be 1")
        XCTAssertEqual(attentionMask[1], 1, "Attention for 'the' should be 1")
        XCTAssertEqual(attentionMask[2], 1, "Attention for [SEP] should be 1")
        XCTAssertEqual(attentionMask[3], 0, "Attention for padding should be 0")
    }

    func testEmptyString() {
        let (inputIds, attentionMask) = tokenizer.tokenize(text: "")

        // Should have [CLS], [SEP], and padding
        XCTAssertEqual(inputIds[0], 2, "First token should be [CLS]")
        XCTAssertEqual(inputIds[1], 3, "Second token should be [SEP]")
        XCTAssertEqual(attentionMask[0], 1, "Attention for [CLS] should be 1")
        XCTAssertEqual(attentionMask[1], 1, "Attention for [SEP] should be 1")
        XCTAssertEqual(attentionMask[2], 0, "Attention for padding should be 0")
    }

    func testWhitespaceString() {
        let (inputIds, attentionMask) = tokenizer.tokenize(text: "   ")

        // Whitespace should be trimmed, should behave like empty string
        XCTAssertEqual(inputIds[0], 2, "First token should be [CLS]")
        XCTAssertEqual(inputIds[1], 3, "Second token should be [SEP]")
        XCTAssertEqual(attentionMask[2], 0, "Should have padding after [CLS] and [SEP]")
    }

    func testRussianText() {
        let (inputIds, attentionMask) = tokenizer.tokenize(text: "кровь")

        XCTAssertEqual(inputIds[0], 2, "First token should be [CLS]")
        XCTAssertGreaterThan(inputIds[1], 0, "Should tokenize Russian word")
        XCTAssertEqual(inputIds.filter { $0 == 0 }.count, 13, "Should have 13 padding tokens")
    }

    func testUnknownToken() {
        let (inputIds, _) = tokenizer.tokenize(text: "xyzabc123unknown")

        // Unknown words should be tokenized as [UNK] (id 1)
        XCTAssertEqual(inputIds[0], 2, "First token should be [CLS]")
        XCTAssertEqual(inputIds[1], 1, "Unknown word should be [UNK]")
        XCTAssertEqual(inputIds[2], 3, "Third token should be [SEP]")
    }

    // MARK: - Padding and Truncation Tests

    func testPadding() {
        let (inputIds, attentionMask) = tokenizer.tokenize(text: "a")

        // Count padding tokens (id 0)
        let paddingCount = inputIds.filter { $0 == 0 }.count
        XCTAssertEqual(paddingCount, 13, "Should have 13 padding tokens (16 - [CLS] - 'a' - [SEP])")

        // Count attention mask zeros
        let maskZeros = attentionMask.filter { $0 == 0 }.count
        XCTAssertEqual(maskZeros, 13, "Attention mask should have 13 zeros")
    }

    func testTruncation() {
        // Create a very long text that exceeds max sequence length
        let longText = Array(repeating: "word", count: 20).joined(separator: " ")
        let (inputIds, attentionMask) = tokenizer.tokenize(text: longText)

        XCTAssertEqual(inputIds.count, 16, "Should truncate to max sequence length")
        XCTAssertEqual(inputIds[0], 2, "First token should be [CLS]")
        XCTAssertEqual(inputIds[15], 3, "Last token should be [SEP] after truncation")

        // All attention should be 1 (no padding when truncated)
        XCTAssertTrue(
            attentionMask.allSatisfy { $0 == 1 }, "All attention should be 1 for truncated sequence"
        )
    }

    // MARK: - Case Sensitivity Tests

    func testCaseInsensitivity() {
        let (ids1, _) = tokenizer.tokenize(text: "The")
        let (ids2, _) = tokenizer.tokenize(text: "the")
        let (ids3, _) = tokenizer.tokenize(text: "THE")

        XCTAssertEqual(ids1, ids2, "Should be case insensitive")
        XCTAssertEqual(ids2, ids3, "Should be case insensitive")
    }

    // MARK: - Attention Mask Tests

    func testAttentionMaskCorrectness() {
        let (inputIds, attentionMask) = tokenizer.tokenize(text: "hello world")

        // Find first padding token
        let firstPaddingIndex = inputIds.firstIndex(of: 0) ?? inputIds.count

        // All attention before padding should be 1
        for i in 0..<firstPaddingIndex {
            XCTAssertEqual(attentionMask[i], 1, "Attention before padding should be 1")
        }

        // All attention after padding starts should be 0
        for i in firstPaddingIndex..<attentionMask.count {
            XCTAssertEqual(attentionMask[i], 0, "Attention for padding should be 0")
        }
    }
}
