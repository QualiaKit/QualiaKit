import Foundation
import QualiaKit

/// The portable description of an app-supplied BERT sequence classifier.
/// This is a separate contract from the original audited Core ML profile.
struct BertModelManifest: Decodable, Sendable {
    let schemaVersion: Int
    let kind: String
    let identifier: String
    let version: String
    let languages: [String]
    let model: QualiaModelManifest.Asset
    let tokenizer: BertTokenizerConfiguration
    let sequence: Sequence
    let inputs: [String: Input]
    let output: Output

    struct Sequence: Decodable, Sendable {
        let maximumLength: Int
        /// singleText or contextThenText, even when context is empty.
        let template: String
        let contextSeparator: String
        let padding: String
        let overflow: String
    }
    struct Input: Decodable, Sendable {
        let role: String
        let shape: [Int]
        let dataType: String
    }
    struct Output: Decodable, Sendable {
        let feature: String
        let shape: [Int]
        let dataType: String
        let classification: String
        let transform: String
        /// Array order is the tensor's class axis; no inferred label semantics.
        let labels: [Label]
        struct Label: Decodable, Sendable {
            let name: String
            let signal: String
        }
    }

    static func decode(_ data: Data) throws -> Self {
        do { return try JSONDecoder().decode(Self.self, from: data) }
        catch { throw CoreMLRuntimeError.invalidManifest }
    }

    func validate() throws {
        guard schemaVersion == 1 else { throw CoreMLRuntimeError.unsupportedSchemaVersion(schemaVersion) }
        guard kind == "qualia-bert-sequence-classification", !identifier.isBlank, !version.isBlank,
              !languages.isEmpty, Set(languages).count == languages.count else {
            throw CoreMLRuntimeError.invalidManifest
        }
        _ = try identity()
        _ = try capabilities()
        guard tokenizer.type == "bert-wordpiece-v1", tokenizer.unicodeNormalization == "bert",
              (4...1_000_000).contains(tokenizer.vocabularyLineCount),
              (1...1_000).contains(tokenizer.maximumWordCharacters),
              !tokenizer.continuingSubwordPrefix.isEmpty,
              LocalAssets.isSHA256(tokenizer.vocabularySha256),
              Set(tokenizer.specialTokens.keys).isSuperset(of: ["pad", "unk", "cls", "sep"]),
              Set(tokenizer.specialTokens.keys).isSubset(of: ["pad", "unk", "cls", "sep", "mask"]) else {
            throw CoreMLRuntimeError.unsupportedTokenizer
        }
        guard ["singleText", "contextThenText"].contains(sequence.template),
              sequence.padding == "right", sequence.overflow == "reject",
              (3...4096).contains(sequence.maximumLength) else {
            throw CoreMLRuntimeError.unsupportedTemplate
        }
        let roles = Set(inputs.values.map(\.role))
        guard roles.count == inputs.count, roles.contains("tokenIDs"),
              roles.isSubset(of: ["tokenIDs", "attentionMask", "tokenTypeIDs", "positionIDs"]),
              inputs.allSatisfy({ name, tensor in
                  !name.isBlank && ["Int32", "Float32", "Double"].contains(tensor.dataType) &&
                  (tensor.shape == [sequence.maximumLength] || tensor.shape == [1, sequence.maximumLength])
              }), !output.feature.isBlank,
              ["Float16", "Float32", "Double"].contains(output.dataType),
              !output.labels.isEmpty,
              (output.shape == [output.labels.count] || output.shape == [1, output.labels.count]),
              ["exclusive", "independent"].contains(output.classification),
              output.transform == "none" ||
                output.transform == (output.classification == "exclusive" ? "softmax" : "sigmoid") else {
            throw CoreMLRuntimeError.unsupportedExecutionContract
        }
        guard Set(output.labels.map(\.name)).count == output.labels.count,
              Set(output.labels.map(\.signal)).count == output.labels.count,
              output.labels.allSatisfy({ !$0.name.isBlank && !$0.signal.isBlank }) else {
            throw CoreMLRuntimeError.invalidSemanticMapping
        }
        guard ["mlmodel", "mlpackage"].contains(model.format), model.path.hasSuffix("." + model.format) else {
            throw CoreMLRuntimeError.unsupportedExecutionContract
        }
    }

    func identity() throws -> QualiaAnalyzerIdentity {
        try QualiaAnalyzerIdentity(identifier: identifier, version: version)
    }

    func capabilities() throws -> QualiaAnalyzerCapabilities {
        .init(languages: try Set(languages.map { try QualiaLanguage(rawValue: $0) }), dimensions: [],
              signals: try Set(output.labels.map { try QualiaSignal(rawValue: $0.signal) }),
              acceptsContext: sequence.template == "contextThenText", execution: .onDevice)
    }
}

struct BertTokenizerConfiguration: Decodable, Sendable {
    let type: String
    let vocabulary: String
    let vocabularySha256: String
    let vocabularyLineCount: Int
    let lowercase: Bool
    let stripAccents: Bool
    let cleanText: Bool
    let tokenizeChineseCharacters: Bool
    let unicodeNormalization: String
    let maximumWordCharacters: Int
    let continuingSubwordPrefix: String
    let specialTokens: [String: QualiaModelManifest.SpecialToken]
}
