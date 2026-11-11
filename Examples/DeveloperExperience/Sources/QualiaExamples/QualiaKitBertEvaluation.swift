import CryptoKit
import Foundation
import QualiaKit

public extension QualiaKitBert {
    /// Runs only the public fixed probes. It never collects a user's draft text.
    static func evaluationReport() async throws -> Data {
        let start = ContinuousClock.now
        let analyzer = try await analyzer()
        let loadMilliseconds = milliseconds(start.duration(to: .now))
        let probes = try probes()
        var results: [[String: Any]] = []
        var timings: [Double] = []
        for probe in probes.cases {
            let input = try QualiaInput(id: .init(rawValue: probe.id), text: probe.text, language: .init(rawValue: "en"))
            let started = ContinuousClock.now
            let result = try await analyzer.analyze(input)
            timings.append(milliseconds(started.duration(to: .now)))
            results.append([
                "id": probe.id,
                "expectedSuspense": probe.suspense,
                "predictedSuspense": (result.signals[.suspense]?.value ?? 0) >= probes.threshold,
                "scores": Dictionary(uniqueKeysWithValues: result.signals.map { ($0.key.rawValue, $0.value.value) }),
            ])
        }
        var warmTimings: [Double] = []
        for index in 0..<30 {
            let probe = probes.cases[index % probes.cases.count]
            let started = ContinuousClock.now
            _ = try await analyzer.analyze(.init(id: .init(rawValue: "warm-\(index)"), text: probe.text, language: .init(rawValue: "en")))
            warmTimings.append(milliseconds(started.duration(to: .now)))
        }
        let manifestURL = Bundle.module.url(forResource: "manifest", withExtension: "json", subdirectory: "QualiaKitBert")!
        let checksum = SHA256.hash(data: try Data(contentsOf: manifestURL)).map { String(format: "%02x", $0) }.joined()
        let report: [String: Any] = [
            "schemaVersion": 1, "model": analyzer.identity.identifier, "version": analyzer.identity.version,
            "manifestSHA256": checksum, "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "annotation": probes.annotation, "threshold": probes.threshold,
            "loadMilliseconds": loadMilliseconds, "probeMilliseconds": timings,
            "warmPredictionMilliseconds": warmTimings, "results": results,
            "scope": "Six assistant-labeled diagnostics and local runtime timings; not independent accuracy, comfort, or battery evidence.",
        ]
        return try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }
}
