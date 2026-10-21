#if QUALIA_DEVICE_EVALUATION
import Foundation
import QualiaKit
import QualiaCoreML

struct DeviceLoadSample: Codable, Sendable {
    let elapsedSeconds: Double
    let processCPUSeconds: Double
    let physicalFootprintBytes: UInt64
    let thermalState: Int
    let completedAnalyses: Int
}
struct DeviceSustainedResult: Codable, Sendable {
    let requestedSeconds: Int
    let elapsedSeconds: Double
    let samples: [DeviceLoadSample]
    let latency: DeviceMeasurement
    let completedAnalyses: Int
    let consumedObservationChecksum: Double
    let method: String
}

enum DeviceSustainedBenchmark {
    static func run(seconds: Int = 300, publicFixture: Bool = false, progress: @escaping @Sendable (Double) async -> Void) async throws -> DeviceSustainedResult {
        guard (5...900).contains(seconds) else { throw DeviceEvaluationFailure.check("Invalid sustained duration") }
        let analyzer: any QualiaAnalyzing
        if publicFixture {
            analyzer = try await CoreMLQualiaAnalyzer(source: DeviceCoreMLBenchmark.source())
        } else { analyzer = AppleSentimentAnalyzer() }
        let input = try QualiaInput(id: .init(rawValue: "sustained-synthetic"),
            text: String(repeating: "The traveler reads a letter and considers the journey ahead. ", count: 32),
            language: .init(rawValue: "en"))
        let start = ContinuousClock.now
        let initialCPU = DeviceEvaluationBenchmark.cpuSeconds()
        var samples: [DeviceLoadSample] = []
        var timings: [Double] = []
        var iterations = 0
        var consumed = 0.0
        var nextSample = 0.0
        while start.duration(to: .now) < .seconds(seconds) {
            try Task.checkCancellation()
            let tick = ContinuousClock.now
            let value = try await analyzer.analyze(input)
            timings.append(DeviceEvaluationBenchmark.milliseconds(tick.duration(to: .now)))
            consumed += Double(value.dimensions.valence?.value ?? 0) + value.signals.values.reduce(0) { $0 + Double($1.value) }
            iterations += 1
            let elapsed = DeviceEvaluationBenchmark.milliseconds(start.duration(to: .now)) / 1000
            if elapsed >= nextSample {
                samples.append(.init(elapsedSeconds: elapsed, processCPUSeconds: DeviceEvaluationBenchmark.cpuSeconds() - initialCPU,
                    physicalFootprintBytes: try DeviceEvaluationBenchmark.memory().current,
                    thermalState: ProcessInfo.processInfo.thermalState.rawValue, completedAnalyses: iterations))
                nextSample += 5
                await progress(min(1, elapsed / Double(seconds)))
            }
            // One request every 50 ms. Avoid an unbounded busy loop or sample buffer.
            try await Task.sleep(until: tick.advanced(by: .milliseconds(50)), clock: .continuous)
        }
        let elapsed = DeviceEvaluationBenchmark.milliseconds(start.duration(to: .now)) / 1000
        samples.append(.init(elapsedSeconds: elapsed, processCPUSeconds: DeviceEvaluationBenchmark.cpuSeconds() - initialCPU,
            physicalFootprintBytes: try DeviceEvaluationBenchmark.memory().current,
            thermalState: ProcessInfo.processInfo.thermalState.rawValue, completedAnalyses: iterations))
        return .init(requestedSeconds: seconds, elapsedSeconds: elapsed, samples: samples,
            latency: DeviceMeasurement(publicFixture ? "self-test-public-coreml-load" : "sustained-apple-analysis", timings), completedAnalyses: iterations, consumedObservationChecksum: consumed,
            method: (publicFixture ? "SIMULATOR SOFTWARE SELF-TEST; public Core ML fixture. " : "Apple English valence. ") + "Single in-flight Apple English valence call at up to 20 Hz; memory/CPU/thermal every 5 s. No haptics. Not watt/joule or battery-drain measurement; use separate Instruments trace for power.")
    }
}
#endif
