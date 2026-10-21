#if QUALIA_DEVICE_EVALUATION
import Foundation
import CoreML
import CryptoKit

struct DeviceRussianReference: Codable, Sendable {
    struct Case: Codable, Sendable {
        let id: String
        let group: String
        let text: String
        let inputIds: [Int]
        let attentionMask: [Int]
        let tokenTypeIds: [Int]
        let sourceLogits: [Double]
        let sourceLabel: String
    }
    let cases: [Case]
}
struct DeviceRussianPrediction: Codable, Sendable {
    let label: String
    let logits: [Double]
    let probabilities: [Double]
    let tokenCount: Int
    let truncated: Bool
    let stagesMilliseconds: [String: Double]
}
struct DeviceRussianParity: Codable, Sendable {
    let id: String
    let group: String
    let expectedLabel: String
    let tokenizerMatches: Bool
    let prediction: DeviceRussianPrediction
    let maximumLogitDifference: Double
    let maximumProbabilityDifference: Double
}
struct DeviceRussianModeResult: Codable, Sendable {
    let computeUnits: String
    let initializationMilliseconds: Double
    let measurements: [DeviceMeasurement]
    let parity: [DeviceRussianParity]
    let processCPUSeconds: Double
    let physicalFootprintBytes: UInt64
}
struct DeviceRussianResult: Codable, Sendable {
    let model: String
    let assetManifestSHA256: String
    let mappingStatus: String
    let modes: [DeviceRussianModeResult]
    let sustained: DeviceSustainedResult?
}

/// Experimental device-lab adapter, intentionally independent of the frozen legacy runtime.
/// Raw classes and provisional captions never become narrative signals.
actor DeviceRussianAnalyzer {
    private let model: MLModel
    private let tokenizer: DeviceRussianTokenizer
    static let captions = ["Негатив", "Нейтрально", "Позитив", "Пропуск / неоднозначно", "Речевая формула"]
    static var assetsURL: URL? { Bundle.main.url(forResource: "DeviceRussianAssets", withExtension: "bundle") }
    static func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var digest = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { digest.update(data: data) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
    init(directory: URL, computeUnits: MLComputeUnits) throws {
        try Task.checkCancellation()
        struct Manifest: Decodable { let files: [String: String] }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: directory.appendingPathComponent("asset-manifest.json")))
        guard !manifest.files.isEmpty else { throw DeviceEvaluationFailure.check("Russian asset inventory missing") }
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        var actual = Set<String>()
        while let url = enumerator?.nextObject() as? URL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw DeviceEvaluationFailure.check("Russian asset symlink") }
            if values.isRegularFile == true {
                let name = String(url.path.dropFirst(directory.path.count + 1))
                if name != "asset-manifest.json" { actual.insert(name) }
            }
        }
        guard actual == Set(manifest.files.keys) else { throw DeviceEvaluationFailure.check("Russian asset inventory mismatch") }
        for (name, checksum) in manifest.files {
            try Task.checkCancellation()
            guard !name.hasPrefix("/"), !name.split(separator: "/").contains(".."),
                  try Self.hash(directory.appendingPathComponent(name)) == checksum else {
                throw DeviceEvaluationFailure.check("Russian asset checksum mismatch")
            }
        }
        tokenizer = try DeviceRussianTokenizer(vocabURL: directory.appendingPathComponent("vocab.txt"))
        let config = MLModelConfiguration(); config.computeUnits = computeUnits
        model = try MLModel(contentsOf: directory.appendingPathComponent("RuBSentimentModel.mlmodelc"), configuration: config)
        let description = model.modelDescription
        guard Set(description.inputDescriptionsByName.keys) == ["input_ids", "attention_mask", "token_type_ids"],
              Set(description.outputDescriptionsByName.keys) == ["classLabel", "classLabel_probs"] else {
            throw DeviceEvaluationFailure.check("Russian model signature mismatch")
        }
        for input in description.inputDescriptionsByName.values {
            guard input.multiArrayConstraint?.shape.map(\.intValue) == [1, 128], input.multiArrayConstraint?.dataType == .int32 else {
                throw DeviceEvaluationFailure.check("Russian model tensor mismatch")
            }
        }
        try Task.checkCancellation()
    }
    func encoding(_ text: String) throws -> DeviceRussianTokenizer.Encoding { try tokenizer.encode(text) }
    func predict(_ text: String) throws -> DeviceRussianPrediction {
        try Task.checkCancellation()
        let start = ContinuousClock.now
        let encoded = try tokenizer.encode(text)
        let tokenized = ContinuousClock.now
        func array(_ values: [Int]) throws -> MLMultiArray {
            let result = try MLMultiArray(shape: [1, 128], dataType: .int32)
            for (index, value) in values.enumerated() { result[index] = NSNumber(value: value) }
            return result
        }
        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: array(encoded.inputIds)),
            "attention_mask": MLFeatureValue(multiArray: array(encoded.attentionMask)),
            "token_type_ids": MLFeatureValue(multiArray: array(encoded.tokenTypeIds))])
        let prepared = ContinuousClock.now
        try Task.checkCancellation()
        let output = try model.prediction(from: input)
        try Task.checkCancellation()
        let predicted = ContinuousClock.now
        guard let raw = output.featureValue(for: "classLabel_probs")?.dictionaryValue,
              Set(raw.keys.compactMap { $0 as? String }) == Set((0..<5).map { "LABEL_\($0)" }),
              let label = output.featureValue(for: "classLabel")?.stringValue else {
            throw DeviceEvaluationFailure.check("Russian model output contract")
        }
        let logits = try (0..<5).map { index -> Double in
            guard let value = raw["LABEL_\(index)"]?.doubleValue, value.isFinite else { throw DeviceEvaluationFailure.check("Russian model nonfinite score") }
            return value
        }
        guard let maximum = logits.max(), let winner = logits.firstIndex(of: maximum), label == "LABEL_\(winner)" else {
            throw DeviceEvaluationFailure.check("Russian model class/score disagreement")
        }
        let probabilities = Self.softmax(logits)
        let end = ContinuousClock.now
        func ms(_ a: ContinuousClock.Instant, _ b: ContinuousClock.Instant) -> Double { DeviceEvaluationBenchmark.milliseconds(a.duration(to: b)) }
        return .init(label: label, logits: logits, probabilities: probabilities,
            tokenCount: encoded.attentionMask.reduce(0,+), truncated: encoded.truncated,
            stagesMilliseconds: ["tokenized": ms(start,tokenized), "prepared": ms(tokenized,prepared),
                "predicted": ms(prepared,predicted), "transformed": ms(predicted,end), "total": ms(start,end)])
    }
    static func softmax(_ logits: [Double]) -> [Double] {
        let maximum = logits.max() ?? 0
        let expValues = logits.map { exp($0 - maximum) }; let sum = expValues.reduce(0,+)
        return expValues.map { $0 / sum }
    }
}

enum DeviceRussianBenchmark {
    static func run(seconds: Int?, progress: @escaping @Sendable (String, Double) async -> Void) async throws -> DeviceRussianResult {
        guard let directory = DeviceRussianAnalyzer.assetsURL else { throw DeviceEvaluationFailure.check("Russian model was not included in this local build") }
        let reference = try JSONDecoder().decode(DeviceRussianReference.self, from: Data(contentsOf: directory.appendingPathComponent("reference.json")))
        var modes: [DeviceRussianModeResult] = []
        var sustained: DeviceSustainedResult?
        for (name, units) in [("cpuOnly", MLComputeUnits.cpuOnly), ("all", MLComputeUnits.all)] {
            try Task.checkCancellation()
            await progress("RuBERT: загрузка (\(name))", 0)
            let begin = ContinuousClock.now
            let analyzer = try DeviceRussianAnalyzer(directory: directory, computeUnits: units)
            let load = DeviceEvaluationBenchmark.milliseconds(begin.duration(to: .now))
            let cpu = DeviceEvaluationBenchmark.cpuSeconds()
            var parity: [DeviceRussianParity] = []
            for item in reference.cases {
                try Task.checkCancellation()
                let encoding = try await analyzer.encoding(item.text)
                let prediction = try await analyzer.predict(item.text)
                parity.append(.init(id: item.id, group: item.group, expectedLabel: item.sourceLabel,
                    tokenizerMatches: encoding.inputIds == item.inputIds && encoding.attentionMask == item.attentionMask && encoding.tokenTypeIds == item.tokenTypeIds,
                    prediction: prediction, maximumLogitDifference: zip(prediction.logits, item.sourceLogits).map { abs($0-$1) }.max() ?? 0,
                    maximumProbabilityDifference: zip(prediction.probabilities, DeviceRussianAnalyzer.softmax(item.sourceLogits)).map { abs($0-$1) }.max() ?? 0))
            }
            guard parity.allSatisfy(\.tokenizerMatches) else { throw DeviceEvaluationFailure.check("Russian tokenizer parity failed") }
            var measurements: [DeviceMeasurement] = []
            for repeats in [1, 8, 40] {
                let text = String(repeating: "Мне понравилась эта книга, я читаю её с удовольствием. ", count: repeats)
                await progress("RuBERT: скорость (\(name), длина \(repeats))", 0)
                var samples: [String: [Double]] = [:]
                for index in 0..<35 {
                    let value = try await analyzer.predict(text)
                    if index >= 5 { for (stage, ms) in value.stagesMilliseconds { samples[stage, default: []].append(ms) } }
                }
                for key in samples.keys.sorted() { measurements.append(DeviceMeasurement("ru-\(repeats)-\(key)", samples[key] ?? [])) }
            }
            modes.append(.init(computeUnits: name, initializationMilliseconds: load, measurements: measurements,
                parity: parity, processCPUSeconds: DeviceEvaluationBenchmark.cpuSeconds() - cpu,
                physicalFootprintBytes: try DeviceEvaluationBenchmark.memory().current))
            if name == "all", let seconds {
                guard (5...900).contains(seconds) else { throw DeviceEvaluationFailure.check("Invalid Russian load duration") }
                let start = ContinuousClock.now; let cpuStart = DeviceEvaluationBenchmark.cpuSeconds()
                var timings: [Double] = []; var samples: [DeviceLoadSample] = []; var consumed = 0.0; var next = 0.0
                let text = String(repeating: "За дверью слышались шаги. Он продолжал читать письмо. ", count: 8)
                while start.duration(to: .now) < .seconds(seconds) {
                    try Task.checkCancellation()
                    let tick = ContinuousClock.now
                    let prediction = try await analyzer.predict(text)
                    timings.append(DeviceEvaluationBenchmark.milliseconds(tick.duration(to: .now)))
                    consumed += prediction.probabilities.enumerated().reduce(0) { $0 + Double($1.offset + 1) * $1.element }
                    let elapsed = DeviceEvaluationBenchmark.milliseconds(start.duration(to: .now)) / 1000
                    if elapsed >= next {
                        samples.append(.init(elapsedSeconds: elapsed, processCPUSeconds: DeviceEvaluationBenchmark.cpuSeconds() - cpuStart,
                            physicalFootprintBytes: try DeviceEvaluationBenchmark.memory().current, thermalState: ProcessInfo.processInfo.thermalState.rawValue, completedAnalyses: timings.count))
                        next += 5
                        await progress("RuBERT: длительная нагрузка", min(1, elapsed / Double(seconds)))
                    }
                    try await Task.sleep(until: tick.advanced(by: .milliseconds(100)), clock: .continuous)
                }
                let elapsed = DeviceEvaluationBenchmark.milliseconds(start.duration(to: .now)) / 1000
                samples.append(.init(elapsedSeconds: elapsed, processCPUSeconds: DeviceEvaluationBenchmark.cpuSeconds() - cpuStart,
                    physicalFootprintBytes: try DeviceEvaluationBenchmark.memory().current, thermalState: ProcessInfo.processInfo.thermalState.rawValue, completedAnalyses: timings.count))
                sustained = .init(requestedSeconds: seconds, elapsedSeconds: elapsed, samples: samples,
                    latency: DeviceMeasurement("sustained-rubert-all", timings), completedAnalyses: timings.count,
                    consumedObservationChecksum: consumed, method: "Actual RuBERT; computeUnits=all (backend selected by Core ML, not an ANE assertion); one request in flight; up to 10Hz; no haptics; CPU/memory/thermal, not watts or joules.")
            }
        }
        return .init(model: "sismetanin/rubert-ru-sentiment-rusentiment@f3d755e", assetManifestSHA256: try DeviceRussianAnalyzer.hash(directory.appendingPathComponent("asset-manifest.json")),
            mappingStatus: "Empirical hypothesis: 0 negative, 1 neutral, 2 positive, 3 skip, 4 speech. Author mapping unavailable. Diagnostics are not semantic accuracy or narrative signals.", modes: modes, sustained: sustained)
    }
}
#endif
