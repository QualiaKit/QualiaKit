import CoreML
import Foundation

/// Intentionally small, fully specified tokenizer, unrelated to the frozen BERT reconstruction.
struct RuntimeTokenizer: Sendable {
    let configuration: QualiaModelManifest.Tokenizer
    // UTF-8 keys preserve the exact scalar identity required by this contract.
    let vocabulary: [Data: Int]

    init(configuration: QualiaModelManifest.Tokenizer, data: Data) throws {
        guard let text = String(data: data, encoding: .utf8) else { throw CoreMLRuntimeError.invalidVocabulary }
        var tokens = text.components(separatedBy: "\n")
        if tokens.last == "" { tokens.removeLast() }
        let keys = tokens.map { Data($0.utf8) }
        guard tokens.count == configuration.vocabularyLineCount,
              !tokens.contains(where: { $0.isEmpty || $0.contains("\r") }),
              Set(keys).count == tokens.count else { throw CoreMLRuntimeError.invalidVocabulary }
        for special in configuration.specialTokens.values {
            guard keys.indices.contains(special.id), keys[special.id] == Data(special.token.utf8) else {
                throw CoreMLRuntimeError.invalidVocabulary
            }
        }
        guard Set(configuration.specialTokens.values.map(\.id)).count == 4 else {
            throw CoreMLRuntimeError.invalidVocabulary
        }
        self.configuration = configuration
        vocabulary = Dictionary(uniqueKeysWithValues: keys.enumerated().map { ($1, $0) })
    }

    func prepare(_ text: String) throws -> PreparedText {
        try Task.checkCancellation()
        // ASCII case folding and whitespace only; all other Unicode scalars are preserved.
        let scalars = text.unicodeScalars.map { scalar -> Unicode.Scalar in
            if configuration.lowercase, (65...90).contains(scalar.value) {
                return Unicode.Scalar(scalar.value + 32)!
            }
            return scalar
        }
        let words = scalars.split { $0.value == 32 || (9...13).contains($0.value) }
            .map { String(String.UnicodeScalarView($0)) }
        let contentLimit = configuration.maxSequenceLength - 2
        // Validated at initialization; no inferred IDs or fallback special tokens.
        guard let cls = configuration.specialTokens["cls"]?.id,
              let sep = configuration.specialTokens["sep"]?.id,
              let pad = configuration.specialTokens["pad"]?.id,
              let unk = configuration.specialTokens["unk"]?.id else {
            throw CoreMLRuntimeError.invalidVocabulary
        }
        let content = words.prefix(contentLimit).map { vocabulary[Data($0.utf8)] ?? unk }
        let count = content.count + 2
        let ids = [cls] + content + [sep] + Array(repeating: pad, count: configuration.maxSequenceLength - count)
        try Task.checkCancellation()
        return PreparedText(ids: ids, mask: Array(repeating: 1, count: count) + Array(repeating: 0, count: ids.count - count),
                            tokenCount: count, truncatedCount: max(0, words.count - contentLimit))
    }
}

struct PreparedText: Sendable, Equatable {
    let ids: [Int]
    let mask: [Int]
    let tokenCount: Int
    let truncatedCount: Int
}

enum RuntimeInputBuilder {
    static func build(_ text: PreparedText, contract: ValidatedContract) throws -> MLDictionaryFeatureProvider {
        var features: [String: MLFeatureValue] = [:]
        for (name, tensor) in contract.manifest.inputs {
            let values: [Int]
            switch contract.execution.inputRoles[name] {
            case "tokenIDs": values = text.ids
            case "attentionMask": values = text.mask
            case "tokenTypeIDs": values = Array(repeating: 0, count: text.ids.count)
            default: throw CoreMLRuntimeError.inputPreparationFailed
            }
            let array = try MLMultiArray(shape: tensor.shape.map(NSNumber.init), dataType: try dataType(tensor.dataType))
            for (index, value) in values.enumerated() { array[index] = NSNumber(value: value) }
            features[name] = MLFeatureValue(multiArray: array)
        }
        return try MLDictionaryFeatureProvider(dictionary: features)
    }

    static func dataType(_ name: String) throws -> MLMultiArrayDataType {
        switch name {
        case "Int32": return .int32
        case "Float32": return .float32
        case "Double": return .double
        default: throw CoreMLRuntimeError.incompatibleModel
        }
    }
}
