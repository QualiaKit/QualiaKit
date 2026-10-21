#if QUALIA_DEVICE_EVALUATION
import Foundation
import QualiaKit
import QualiaCoreML

private final class DeviceStageCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [String: [Double]] = [:]
    func append(_ event: CoreMLRuntimeEvent) {
        lock.lock(); defer { lock.unlock() }
        samples[event.stage.rawValue, default: []].append(event.durationSeconds * 1000)
    }
    func take() -> [String: [Double]] {
        lock.lock(); defer { lock.unlock() }
        let result = samples
        samples.removeAll()
        return result
    }
}

struct DeviceCoreMLResult: Codable, Sendable {
    let model: String
    let contract: String
    let sourceModelBytes: Int
    let computeUnits: String
    let initialLoadIncludingCompilationMilliseconds: Double
    let compilationMilliseconds: [Double]
    let stages: [DeviceMeasurement]
    let checksum: Double
}

enum DeviceCoreMLBenchmark {
    static func source() throws -> FileQualiaModelSource {
        guard let url = Bundle.main.url(forResource: "DeviceEvaluationAssets", withExtension: "bundle") else {
            throw DeviceEvaluationFailure.check("Public Core ML fixture bundle missing")
        }
        return FileQualiaModelSource(directory: url)
    }
    static func run() async throws -> DeviceCoreMLResult {
        guard let url = Bundle.main.url(forResource: "DeviceEvaluationAssets", withExtension: "bundle") else {
            throw DeviceEvaluationFailure.check("Public Core ML fixture bundle missing")
        }
        let bytes = try Data(contentsOf: url.appendingPathComponent("model.mlmodel")).count
        let collector = DeviceStageCollector()
        let start = ContinuousClock.now
        let analyzer = try await CoreMLQualiaAnalyzer(source: FileQualiaModelSource(directory: url),
            configuration: .init(computeUnits: .cpuOnly, diagnostics: { collector.append($0) }))
        let initial = DeviceEvaluationBenchmark.milliseconds(start.duration(to: .now))
        let loading = collector.take()
        var total: [Double] = []
        var checksum = 0.0
        for index in 0..<220 {
            try Task.checkCancellation()
            let input = try QualiaInput(id: .init(rawValue: "public-coreml-\(index)"),
                text: index.isMultiple(of: 2) ? "quiet door" : "dark shadow impact", language: .init(rawValue: "en"))
            let tick = ContinuousClock.now
            let observation = try await analyzer.analyze(input)
            if index >= 20 { total.append(DeviceEvaluationBenchmark.milliseconds(tick.duration(to: .now))) }
            checksum += observation.signals.values.reduce(0) { $0 + Double($1.value) }
            if index == 19 { _ = collector.take() }
        }
        let stages = collector.take()
        var measured = [DeviceMeasurement("fixture-coreml-analyze-total", total)]
        for stage in ["tokenized", "prepared", "predicted", "transformed"] {
            guard let samples = stages[stage], samples.count == 200 else {
                throw DeviceEvaluationFailure.check("Missing Core ML stage samples: \(stage)")
            }
            measured.append(DeviceMeasurement("fixture-coreml-" + stage, samples))
        }
        return .init(model: analyzer.identity.identifier + "/" + analyzer.modelVersion,
                     contract: analyzer.contractVersion, sourceModelBytes: bytes, computeUnits: "cpuOnly",
                     initialLoadIncludingCompilationMilliseconds: initial,
                     compilationMilliseconds: loading["compiled"] ?? [], stages: measured, checksum: checksum)
    }
}
#endif
