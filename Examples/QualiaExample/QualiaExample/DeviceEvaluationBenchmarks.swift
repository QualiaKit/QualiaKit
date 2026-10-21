#if QUALIA_DEVICE_EVALUATION
import Darwin
import Foundation
import QualiaKit

/// Built only for an explicitly requested, local device-evaluation build.
/// Synthetic public text; no input collection or network transport.
struct DeviceMeasurement: Codable, Sendable {
    let name: String
    let milliseconds: [Double]
    let p50: Double
    let p95: Double
    let maximum: Double

    init(_ name: String, _ samples: [Double]) {
        self.name = name
        milliseconds = samples
        let sorted = samples.sorted()
        p50 = sorted[max(0, Int(ceil(Double(sorted.count) * 0.5)) - 1)]
        p95 = sorted[max(0, Int(ceil(Double(sorted.count) * 0.95)) - 1)]
        maximum = sorted.last!
    }
}

struct DeviceBenchmarkResult: Codable, Sendable {
    let measurements: [DeviceMeasurement]
    let firstAppleAnalysisMilliseconds: Double?
    let consumedObservationChecksum: Double
    let plannedCommandCount: Int
    let physicalFootprintBytes: UInt64
    let lifetimePeakPhysicalFootprintBytes: Int64
    let elapsedSeconds: Double
    let processCPUSeconds: Double
    let thermalStateBefore: Int
    let thermalStateAfter: Int
}

enum DeviceEvaluationBenchmark {
    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
    }

    static func run(appleAnalysisEnabled: Bool = true) async throws -> DeviceBenchmarkResult {
        let clock = ContinuousClock()
        let start = clock.now
        let cpuStart = cpuSeconds()
        let thermalBefore = ProcessInfo.processInfo.thermalState.rawValue
        let analyzer = AppleSentimentAnalyzer()
        let language = try QualiaLanguage(rawValue: "en")
        let sentences = [
            "The room is quiet and the morning feels pleasant.",
            String(repeating: "The traveler reads a letter and considers the journey ahead. ", count: 8),
            String(repeating: "The traveler reads a letter and considers the journey ahead. ", count: 32),
        ]
        var measurements: [DeviceMeasurement] = []
        var checksum = 0.0
        var firstDuration: Double?
        if appleAnalysisEnabled {
        let firstInput = try QualiaInput(id: .init(rawValue: "first"), text: sentences[0], language: language)
        let firstStart = clock.now
        let first = try await analyzer.analyze(firstInput)
        firstDuration = milliseconds(firstStart.duration(to: clock.now))
        checksum += Double(first.dimensions.valence?.value ?? 0)
        for (group, text) in sentences.enumerated() {
            var samples: [Double] = []
            for index in 0..<220 {
                try Task.checkCancellation()
                let input = try QualiaInput(id: .init(rawValue: "benchmark-\(group)-\(index)"), text: text, language: language)
                let tick = clock.now
                let observation = try await analyzer.analyze(input)
                let elapsed = milliseconds(tick.duration(to: clock.now))
                guard let valence = observation.dimensions.valence else { throw QualiaError.invalidConfiguration(reason: .configuration) }
                checksum += Double(valence.value)
                if index >= 20 { samples.append(elapsed) }
            }
            measurements.append(DeviceMeasurement("apple-analysis-\(text.utf8.count)-utf8-bytes", samples))
        }
        }
        let fixture = try DeviceScriptedAnalyzer()
        let reducer = QualiaSceneReducer()
        let policy = HorrorNarrativePolicy()
        let owner = try HapticOwnerID(rawValue: "device-benchmark")
        var state = QualiaSceneState.initial()
        var reaction = QualiaReactionState.empty
        var statePolicy: [Double] = []
        var commandCount = 0
        for index in 0..<1100 {
            try Task.checkCancellation()
            let input = try QualiaInput(id: .init(rawValue: index % 10 == 0 ? "impact" : "high"), text: "Synthetic fixture.", language: language)
            let observation = try await fixture.analyze(input)
            let instant = Duration.milliseconds(index * 200)
            let tick = clock.now
            let transition = reducer.reduce(state: state, observation: observation, at: instant)
            let plan = policy.plan(for: transition, context: .init(analyzerCapabilities: fixture.capabilities,
                hapticCapabilities: .full, instant: instant, effectScope: .owned(owner), state: reaction))
            let elapsed = milliseconds(tick.duration(to: clock.now))
            state = transition.current
            reaction = plan.nextState
            commandCount += plan.hapticCommands.count
            if index >= 100 { statePolicy.append(elapsed) }
        }
        measurements.append(DeviceMeasurement("scene-and-narrative-policy-no-renderer", statePolicy))
        let window = QualiaContextWindow(configuration: try .init(maximumFragments: 4, maximumCharacters: 1200, maximumUTF8Bytes: 2400))
        let history = try (0..<8).map { index in
            try QualiaContextFragment(id: .init(rawValue: "history-\(index)"), text: String(repeating: "A public synthetic context fragment. ", count: 8))
        }
        let contextInput = try QualiaInput(id: .init(rawValue: "context-current"), text: sentences[0], context: history, language: language)
        var contextSamples: [Double] = []
        for index in 0..<1100 {
            try Task.checkCancellation()
            let tick = clock.now
            let prepared = try window.window(contextInput)
            let elapsed = milliseconds(tick.duration(to: clock.now))
            checksum += Double(prepared.context.count)
            if index >= 100 { contextSamples.append(elapsed) }
        }
        measurements.append(DeviceMeasurement("bounded-context-window", contextSamples))
        let footprint = try memory()
        return DeviceBenchmarkResult(measurements: measurements, firstAppleAnalysisMilliseconds: firstDuration,
            consumedObservationChecksum: checksum, plannedCommandCount: commandCount,
            physicalFootprintBytes: footprint.current, lifetimePeakPhysicalFootprintBytes: footprint.peak,
            elapsedSeconds: milliseconds(start.duration(to: clock.now)) / 1000,
            processCPUSeconds: cpuSeconds() - cpuStart, thermalStateBefore: thermalBefore,
            thermalStateAfter: ProcessInfo.processInfo.thermalState.rawValue)
    }

    static func memory() throws -> (current: UInt64, peak: Int64) {
        var memory = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let memoryStatus = withUnsafeMutablePointer(to: &memory) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard memoryStatus == KERN_SUCCESS else { throw DeviceEvaluationFailure.check("Memory measurement unavailable") }
        return (memory.phys_footprint, memory.ledger_phys_footprint_peak)
    }

    static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
    }
}

struct DeviceScriptedAnalyzer: QualiaAnalyzing {
    let capabilities: QualiaAnalyzerCapabilities
    let identity: QualiaAnalyzerIdentity
    init() throws {
        capabilities = try .init(languages: [.init(rawValue: "en")], dimensions: [],
            signals: [.suspense, .threat, .impact], acceptsContext: true, execution: .onDevice)
        identity = try .init(identifier: "device-scripted-fixture-not-a-model", version: "1")
    }
    func analyze(_ input: QualiaInput) async throws -> QualiaObservation {
        try Task.checkCancellation()
        guard let language = input.language else { throw QualiaError.languageUndetermined }
        var signals: [QualiaSignal: QualiaScore] = [.suspense: try .init(value: input.id.rawValue == "build" ? 0.5 : 1, confidence: 1)]
        if input.id.rawValue == "impact" { signals[.impact] = try .init(value: 1, confidence: 1) }
        return .init(inputID: input.id, signals: signals, language: language, analyzer: identity)
    }
}

enum DeviceEvaluationFailure: Error { case check(String) }
#endif
