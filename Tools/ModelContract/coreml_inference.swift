import CoreML
import Foundation

enum HelperError: Error, CustomStringConvertible {
    case usage
    case invalidRequest(String)
    case invalidOutput(String)

    var description: String {
        switch self {
        case .usage:
            return "usage: coreml_inference <compiled-model.mlmodelc> <request.json> <response.json>"
        case .invalidRequest(let detail):
            return "invalid request: \(detail)"
        case .invalidOutput(let detail):
            return "invalid model output: \(detail)"
        }
    }
}

private let labels = (0...4).map { "LABEL_\($0)" }

func intArray(_ value: Any?, field: String) throws -> [Int] {
    guard let values = value as? [NSNumber], values.count == 128 else {
        throw HelperError.invalidRequest("\(field) must contain exactly 128 integers")
    }
    return values.map(\.intValue)
}

func multiArray(_ values: [Int]) throws -> MLMultiArray {
    let array = try MLMultiArray(shape: [1, 128], dataType: .int32)
    for index in values.indices {
        array[[0, NSNumber(value: index)]] = NSNumber(value: values[index])
    }
    return array
}

func run() throws {
    guard CommandLine.arguments.count == 4 else { throw HelperError.usage }
    let modelURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let requestURL = URL(fileURLWithPath: CommandLine.arguments[2])
    let responseURL = URL(fileURLWithPath: CommandLine.arguments[3])

    let requestData = try Data(contentsOf: requestURL)
    guard
        let request = try JSONSerialization.jsonObject(with: requestData) as? [String: Any],
        let cases = request["cases"] as? [[String: Any]],
        !cases.isEmpty
    else {
        throw HelperError.invalidRequest("top-level cases must be a non-empty array")
    }

    let configuration = MLModelConfiguration()
    configuration.computeUnits = .cpuOnly
    let model = try MLModel(contentsOf: modelURL, configuration: configuration)
    var results: [[String: Any]] = []
    results.reserveCapacity(cases.count)

    for item in cases {
        guard let identifier = item["id"] as? String, !identifier.isEmpty else {
            throw HelperError.invalidRequest("case id is required")
        }
        let inputIDs = try intArray(item["inputIds"], field: "inputIds")
        let attentionMask = try intArray(item["attentionMask"], field: "attentionMask")
        let tokenTypeIDs = try intArray(item["tokenTypeIds"], field: "tokenTypeIds")

        let provider = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: try multiArray(inputIDs)),
            "attention_mask": MLFeatureValue(multiArray: try multiArray(attentionMask)),
            "token_type_ids": MLFeatureValue(multiArray: try multiArray(tokenTypeIDs)),
        ])
        let output = try model.prediction(from: provider)

        guard let label = output.featureValue(for: "classLabel")?.stringValue,
              labels.contains(label) else {
            throw HelperError.invalidOutput("classLabel missing or outside LABEL_0...LABEL_4 for \(identifier)")
        }
        guard let dictionary = output.featureValue(for: "classLabel_probs")?.dictionaryValue,
              dictionary.count == labels.count else {
            throw HelperError.invalidOutput("classLabel_probs must contain five entries for \(identifier)")
        }

        var raw: [String: Double] = [:]
        for expectedLabel in labels {
            guard let number = dictionary[expectedLabel] else {
                throw HelperError.invalidOutput("classLabel_probs is missing \(expectedLabel) for \(identifier)")
            }
            let value = number.doubleValue
            guard value.isFinite else {
                throw HelperError.invalidOutput("non-finite \(expectedLabel) for \(identifier)")
            }
            raw[expectedLabel] = value
        }
        let maximum = raw.values.max() ?? 0
        let exponentials = labels.map { Foundation.exp(raw[$0, default: 0] - maximum) }
        let denominator = exponentials.reduce(0, +)
        let currentSwiftTransformValue = exponentials[2] / denominator - exponentials[0] / denominator
        results.append([
            "id": identifier,
            "predictedLabel": label,
            "rawOutputs": raw,
            "currentSwiftTransformValue": currentSwiftTransformValue,
        ])
    }

    let response: [String: Any] = [
        "helperSchemaVersion": 1,
        "backend": "CoreML",
        "computeUnits": "cpuOnly",
        "processIdentifier": ProcessInfo.processInfo.processIdentifier,
        "cases": results,
    ]
    let data = try JSONSerialization.data(withJSONObject: response, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: responseURL, options: .atomic)
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("model-contract helper: \(error)\n".utf8))
    exit(2)
}
