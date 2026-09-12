import Foundation
import QualiaKit

/// Execution errors deliberately contain no paths, input text, tokens or framework errors.
public enum CoreMLRuntimeError: Error, Equatable, Sendable {
    case invalidManifest
    case unsupportedSchemaVersion(Int)
    case unresolvedEvidence
    case unsupportedExecutionContract
    case unsupportedTokenizer
    case unsupportedTemplate
    case invalidSemanticMapping
    case invalidAssetPath
    case missingAsset
    case checksumMismatch
    case compilationFailed
    case modelLoadFailed
    case incompatibleModel
    case invalidVocabulary
    case inputPreparationFailed
    case predictionFailed
    case missingOutput
    case unexpectedLabels
    case invalidNumericOutput
}

/// Read-only decoding projection of the v1 audit document plus its optional `runtime` extension.
/// Decoding alone does not establish execution readiness; the analyzer validates it.
public struct QualiaModelManifest: Decodable, Sendable {
    public let schemaVersion: Int
    public let contractVersion: String
    public let model: Model
    public let tokenizer: Tokenizer
    public let inputs: [String: Tensor]
    public let outputs: Output
    public let provenance: [String: Evidence<JSONValue>]
    public let runtimeRefactorGate: Gate
    public let runtime: Execution?

    public struct Evidence<Value: Codable & Sendable>: Codable, Sendable {
        public let status: String
        public let value: Value?
        public let evidence: String?

        func verified() throws -> Value {
            guard status == "verified", let value, let evidence, !evidence.isBlank else {
                throw CoreMLRuntimeError.unresolvedEvidence
            }
            return value
        }
    }

    /// Evidence payloads outside the execution profile retain their JSON shape.
    public enum JSONValue: Codable, Sendable {
        case string(String), number(Double), bool(Bool), array([JSONValue]), object([String: JSONValue]), null
        public init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if value.decodeNil() { self = .null }
            else if let item = try? value.decode(Bool.self) { self = .bool(item) }
            else if let item = try? value.decode(String.self) { self = .string(item) }
            else if let item = try? value.decode(Double.self) { self = .number(item) }
            else if let item = try? value.decode([JSONValue].self) { self = .array(item) }
            else { self = .object(try value.decode([String: JSONValue].self)) }
        }
        public func encode(to encoder: Encoder) throws {
            var value = encoder.singleValueContainer()
            switch self {
            case .string(let item): try value.encode(item)
            case .number(let item): try value.encode(item)
            case .bool(let item): try value.encode(item)
            case .array(let item): try value.encode(item)
            case .object(let item): try value.encode(item)
            case .null: try value.encodeNil()
            }
        }
    }

    public struct Model: Codable, Sendable {
        public let identifier: String
        public let version: String
        public let languages: [String]
        public let task: Evidence<String>
        public let architectureFamily: Evidence<JSONValue>
        public let license: Evidence<JSONValue>
        public let componentSha256: [String: String]
    }

    public struct Tokenizer: Codable, Sendable {
        public let type: String
        public let vocabulary: String
        public let vocabularySha256: String
        public let vocabularyLineCount: Int
        public let lowercase: Bool
        public let unicodeNormalization: String
        public let maxSequenceLength: Int
        public let specialTokens: [String: SpecialToken]
        public let trainingIdentity: Evidence<String>
        public let trainingVersion: Evidence<String>
        public let contextPairSupport: Evidence<Template>
    }

    public struct SpecialToken: Codable, Sendable {
        public let token: String
        public let id: Int
    }

    public struct Template: Codable, Sendable {
        public let mode: String
        public let template: String
    }

    public struct Tensor: Codable, Sendable {
        public let dataType: String
        public let shape: [Int]
        /// Required by this model, rather than whether the runtime should emit it.
        public let required: Bool
    }

    public struct Output: Codable, Sendable {
        /// Type of the class label, preserving the meaning of this v1 field.
        public let classLabel: String
        public let scores: String
        public let scoresType: String
        public let kind: Evidence<String>
        public let labels: [Label]
    }

    public struct Label: Codable, Sendable {
        public let name: String
        public let productSignal: String?
        public let semanticMeaning: Evidence<Meaning>
    }

    public struct Meaning: Codable, Sendable {
        public let canonicalMeaning: String
    }

    public struct Gate: Codable, Sendable {
        public let status: String
        public let conditions: [String: String]
    }

    public struct Execution: Codable, Sendable {
        public let version: Int
        public let model: Asset
        public let compiledFrom: CompiledOrigin?
        /// Feature name -> tokenIDs, attentionMask or tokenTypeIDs.
        public let inputRoles: [String: String]
        public let classLabelFeature: String
        public let classification: String
        public let transform: String
        public let confidence: String
        public let truncation: String
        public let padding: String
    }

    public struct Asset: Codable, Sendable {
        public let path: String
        public let format: String
        public let sha256: String?
        public let files: [String: String]?
    }

    public struct CompiledOrigin: Codable, Sendable {
        public let source: Asset
        public let compiler: String
        public let evidence: String
    }

    public static func decode(_ data: Data) throws -> Self {
        struct Header: Decodable { let schemaVersion: Int }
        do {
            let version = try JSONDecoder().decode(Header.self, from: data).schemaVersion
            guard version == 1 else { throw CoreMLRuntimeError.unsupportedSchemaVersion(version) }
            return try JSONDecoder().decode(Self.self, from: data)
        } catch let error as CoreMLRuntimeError {
            throw error
        } catch {
            throw CoreMLRuntimeError.invalidManifest
        }
    }

    func validateForExecution() throws -> ValidatedContract {
        guard schemaVersion == 1 else { throw CoreMLRuntimeError.unsupportedSchemaVersion(schemaVersion) }
        let conditions = ["labelSemantics", "outputKind", "provenance", "tokenizerTrainingParity"]
        guard runtimeRefactorGate.status == "open",
              Set(runtimeRefactorGate.conditions.keys) == Set(conditions),
              runtimeRefactorGate.conditions.values.allSatisfy({ $0 == "resolved" }) else {
            throw CoreMLRuntimeError.unresolvedEvidence
        }
        guard let runtime, runtime.version == 1 else {
            throw CoreMLRuntimeError.unsupportedExecutionContract
        }
        // A self-reported open gate cannot replace evidence in the document.
        let provenanceFields = ["source", "dataset", "domain", "classBalance", "trainingConfiguration"]
        for field in provenanceFields {
            guard let state = provenance[field] else { throw CoreMLRuntimeError.unresolvedEvidence }
            _ = try state.verified()
        }
        _ = try model.architectureFamily.verified()
        _ = try model.license.verified()
        let task = try model.task.verified()
        let kind = try outputs.kind.verified()
        guard task == runtime.classification,
              ["exclusive", "independent"].contains(task),
              (kind == "logits" && runtime.transform == (task == "exclusive" ? "softmax" : "sigmoid")) ||
                (kind == "mutually-exclusive-probabilities" && task == "exclusive" && runtime.transform == "none") ||
                (kind == "independent-probabilities" && task == "independent" && runtime.transform == "none") else {
            throw CoreMLRuntimeError.unsupportedExecutionContract
        }
        guard tokenizer.type == "qualia-ascii-whitespace-v1",
              tokenizer.unicodeNormalization == "none",
              try tokenizer.trainingIdentity.verified() == tokenizer.type,
              try tokenizer.trainingVersion.verified() == "1" else {
            throw CoreMLRuntimeError.unsupportedTokenizer
        }
        let template = try tokenizer.contextPairSupport.verified()
        guard template.mode == "singleText", template.template == "[CLS] text [SEP]" else {
            throw CoreMLRuntimeError.unsupportedTemplate
        }
        guard runtime.padding == "right", runtime.truncation == "right-preserve-sep",
              (3...4096).contains(tokenizer.maxSequenceLength),
              Set(tokenizer.specialTokens.keys) == Set(["pad", "unk", "cls", "sep"]),
              (4...1_000_000).contains(tokenizer.vocabularyLineCount),
              Set(inputs.keys) == Set(runtime.inputRoles.keys),
              Set(runtime.inputRoles.values).count == inputs.count,
              runtime.inputRoles.values.contains("tokenIDs"),
              runtime.inputRoles.values.allSatisfy({ ["tokenIDs", "attentionMask", "tokenTypeIDs"].contains($0) }),
              inputs.allSatisfy({ name, tensor in
                  !name.isBlank && ["Int32", "Float32", "Double"].contains(tensor.dataType) &&
                  (tensor.shape == [tokenizer.maxSequenceLength] || tensor.shape == [1, tokenizer.maxSequenceLength])
              }), outputs.classLabel == "String", outputs.scoresType == "Dictionary<String,Double>",
              !outputs.scores.isBlank, !runtime.classLabelFeature.isBlank,
              outputs.scores != runtime.classLabelFeature else {
            throw CoreMLRuntimeError.unsupportedExecutionContract
        }
        guard runtime.confidence == "unavailable", !outputs.labels.isEmpty else {
            throw CoreMLRuntimeError.invalidSemanticMapping
        }
        let rawLabels = Set(outputs.labels.map(\.name))
        guard rawLabels.count == outputs.labels.count, !rawLabels.contains(where: \.isBlank) else {
            throw CoreMLRuntimeError.invalidSemanticMapping
        }
        var mapping: [String: QualiaSignal] = [:]
        for label in outputs.labels {
            guard !(try label.semanticMeaning.verified()).canonicalMeaning.isBlank,
                  let signal = label.productSignal, !signal.isBlank, !rawLabels.contains(signal) else {
                throw CoreMLRuntimeError.invalidSemanticMapping
            }
            mapping[label.name] = try QualiaSignal(rawValue: signal)
        }
        guard Set(mapping.values).count == mapping.count else { throw CoreMLRuntimeError.invalidSemanticMapping }
        guard !contractVersion.isBlank, !model.identifier.isBlank, !model.version.isBlank,
              !model.languages.isEmpty, Set(model.languages).count == model.languages.count else {
            throw CoreMLRuntimeError.invalidManifest
        }
        do {
            let languages = try Set(model.languages.map { try QualiaLanguage(rawValue: $0) })
            let identity = try QualiaAnalyzerIdentity(identifier: model.identifier, version: contractVersion)
            return ValidatedContract(
                manifest: self, execution: runtime, identity: identity, mapping: mapping,
                capabilities: .init(languages: languages, dimensions: [], signals: Set(mapping.values),
                                    acceptsContext: false, execution: .onDevice)
            )
        } catch { throw CoreMLRuntimeError.invalidManifest }
    }
}

struct ValidatedContract: Sendable {
    let manifest: QualiaModelManifest
    let execution: QualiaModelManifest.Execution
    let identity: QualiaAnalyzerIdentity
    let mapping: [String: QualiaSignal]
    let capabilities: QualiaAnalyzerCapabilities
}

extension String {
    var isBlank: Bool { allSatisfy(\.isWhitespace) }
}
