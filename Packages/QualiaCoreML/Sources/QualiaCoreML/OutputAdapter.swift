import CoreML
import Foundation
import QualiaKit

enum RuntimeOutputAdapter {
    static func scores(_ raw: [String: Double], contract: ValidatedContract) throws -> [QualiaSignal: QualiaScore] {
        let labels = contract.manifest.outputs.labels.map(\.name)
        guard Set(raw.keys) == Set(labels) else { throw CoreMLRuntimeError.unexpectedLabels }
        let values = labels.compactMap { raw[$0] }
        guard values.allSatisfy(\.isFinite) else { throw CoreMLRuntimeError.invalidNumericOutput }
        let probabilities: [Double]
        switch contract.execution.transform {
        case "softmax":
            guard let maximum = values.max() else { throw CoreMLRuntimeError.invalidNumericOutput }
            let exponents = values.map { exp($0 - maximum) }
            let total = exponents.reduce(0, +)
            probabilities = exponents.map { $0 / total }
        case "sigmoid":
            probabilities = values.map { value in
                value >= 0 ? 1 / (1 + exp(-value)) : exp(value) / (1 + exp(value))
            }
        case "none": probabilities = values
        default: throw CoreMLRuntimeError.unsupportedExecutionContract
        }
        guard probabilities.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw CoreMLRuntimeError.invalidNumericOutput
        }
        // This tolerance only validates a probability distribution; values are never renormalized.
        if contract.execution.classification == "exclusive",
           abs(probabilities.reduce(0, +) - 1) > 0.00001 {
            throw CoreMLRuntimeError.invalidNumericOutput
        }
        var result: [QualiaSignal: QualiaScore] = [:]
        for (label, value) in zip(labels, probabilities) {
            guard let signal = contract.mapping[label] else { throw CoreMLRuntimeError.invalidSemanticMapping }
            result[signal] = try QualiaScore(value: Float(value), confidence: nil)
        }
        return result
    }

    static func extract(_ output: any MLFeatureProvider, contract: ValidatedContract) throws -> [String: Double] {
        guard let feature = output.featureValue(for: contract.manifest.outputs.scores),
              feature.type == .dictionary, !feature.isUndefined,
              let winner = output.featureValue(for: contract.execution.classLabelFeature),
              winner.type == .string, !winner.isUndefined else { throw CoreMLRuntimeError.missingOutput }
        guard contract.mapping[winner.stringValue] != nil else { throw CoreMLRuntimeError.unexpectedLabels }
        var values: [String: Double] = [:]
        for (key, value) in feature.dictionaryValue {
            guard let label = key as? String else { throw CoreMLRuntimeError.unexpectedLabels }
            values[label] = value.doubleValue
        }
        return values
    }
}

enum RuntimeModelValidation {
    private static func isFixed(_ constraint: MLMultiArrayShapeConstraint, shape: [Int]) -> Bool {
        switch constraint.type {
        case .unspecified: return true
        case .enumerated:
            return !constraint.enumeratedShapes.isEmpty && constraint.enumeratedShapes.allSatisfy { $0.map(\.intValue) == shape }
        case .range:
            let ranges = constraint.sizeRangeForDimension.map(\.rangeValue)
            return ranges.count == shape.count && zip(ranges, shape).allSatisfy { $0.location == $1 && $0.length == 1 }
        @unknown default: return false
        }
    }

    static func validate(_ description: MLModelDescription, contract: ValidatedContract) throws {
        guard Set(description.inputDescriptionsByName.keys) == Set(contract.manifest.inputs.keys),
              Set(description.outputDescriptionsByName.keys) == Set([contract.manifest.outputs.scores, contract.execution.classLabelFeature]),
              description.outputDescriptionsByName[contract.manifest.outputs.scores]?.type == .dictionary,
              description.outputDescriptionsByName[contract.manifest.outputs.scores]?.dictionaryConstraint?.keyType == .string,
              description.outputDescriptionsByName[contract.execution.classLabelFeature]?.type == .string,
              let modelLabels = description.classLabels as? [String],
              Set(modelLabels) == Set(contract.mapping.keys), modelLabels.count == contract.mapping.count else {
            throw CoreMLRuntimeError.incompatibleModel
        }
        for (name, tensor) in contract.manifest.inputs {
            guard let feature = description.inputDescriptionsByName[name], feature.type == .multiArray,
                  feature.isOptional == !tensor.required, let array = feature.multiArrayConstraint,
                  array.shape.map(\.intValue) == tensor.shape,
                  array.dataType == (try RuntimeInputBuilder.dataType(tensor.dataType)),
                  isFixed(array.shapeConstraint, shape: tensor.shape) else { throw CoreMLRuntimeError.incompatibleModel }
        }
    }
}
