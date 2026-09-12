import Foundation
import XCTest
@testable import QualiaCoreML

extension CoreMLRuntimeTests {
    func testVocabularyLookupRequiresExactUnicodeEncoding() throws {
        let composed = "caf\u{00E9}"
        let decomposed = "cafe\u{0301}"
        for (present, absent) in [(composed, decomposed), (decomposed, composed)] {
            let tokenizer = try tokenizerWithVocabulary(["[PAD]", "[UNK]", "[CLS]", "[SEP]", present])
            XCTAssertEqual(try tokenizer.prepare(present).ids, [2, 4, 3, 0, 0, 0, 0, 0])
            XCTAssertEqual(try tokenizer.prepare(absent).ids, [2, 1, 3, 0, 0, 0, 0, 0])
        }
    }

    func testVocabularyKeepsCanonicallyEquivalentEntriesDistinct() throws {
        let tokenizer = try tokenizerWithVocabulary([
            "[PAD]", "[UNK]", "[CLS]", "[SEP]", "caf\u{00E9}", "cafe\u{0301}",
        ])
        XCTAssertEqual(try tokenizer.prepare("caf\u{00E9} cafe\u{0301}").ids, [2, 4, 5, 3, 0, 0, 0, 0])
        XCTAssertEqual(try tokenizer.prepare("CAF\u{00E9} CAFE\u{0301}").ids, [2, 4, 5, 3, 0, 0, 0, 0])
    }

    func testVocabularyRejectsExactByteDuplicates() throws {
        for token in ["caf\u{00E9}", "cafe\u{0301}"] {
            XCTAssertThrowsError(try tokenizerWithVocabulary([
                "[PAD]", "[UNK]", "[CLS]", "[SEP]", token, token,
            ])) {
                XCTAssertEqual($0 as? CoreMLRuntimeError, .invalidVocabulary)
            }
        }
    }

    func testSpecialTokensRequireExactUnicodeEncoding() throws {
        let composed = "[caf\u{00E9}]"
        let decomposed = "[cafe\u{0301}]"
        for (present, different) in [(composed, decomposed), (decomposed, composed)] {
            let vocabulary = [present, "[UNK]", "[CLS]", "[SEP]", "quiet"]
            XCTAssertThrowsError(try tokenizerWithVocabulary(vocabulary, padToken: different)) {
                XCTAssertEqual($0 as? CoreMLRuntimeError, .invalidVocabulary)
            }
            let tokenizer = try tokenizerWithVocabulary(vocabulary, padToken: present)
            XCTAssertEqual(try tokenizer.prepare("quiet").ids, [2, 4, 3, 0, 0, 0, 0, 0])
        }
    }

    private func tokenizerWithVocabulary(_ vocabulary: [String], padToken: String = "[PAD]") throws -> RuntimeTokenizer {
        let fixture = try copyFixture()
        let data = Data((vocabulary.joined(separator: "\n") + "\n").utf8)
        try edit(fixture) { document in
            var tokenizer = document["tokenizer"] as! [String: Any]
            tokenizer["vocabularyLineCount"] = vocabulary.count
            tokenizer["vocabularySha256"] = LocalAssets.digest(data)
            var specialTokens = tokenizer["specialTokens"] as! [String: Any]
            specialTokens["pad"] = ["token": padToken, "id": 0]
            tokenizer["specialTokens"] = specialTokens
            document["tokenizer"] = tokenizer
        }
        let manifest = try QualiaModelManifest.decode(Data(contentsOf: fixture.appendingPathComponent("manifest.json")))
        return try RuntimeTokenizer(configuration: manifest.tokenizer, data: data)
    }
}
