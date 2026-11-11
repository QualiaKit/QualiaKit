#if DEBUG
import Darwin
import QualiaExamples
import QualiaKit
import SwiftUI
import UIKit

/// Explicit launch-only check; normal demo input is never exported.
struct QualiaKitBertDeviceCheckView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var started = false
    @State private var status = "Waiting for the app to become active…"
    @State private var reportURL: URL?

    var body: some View {
        VStack(spacing: 20) {
            Text("QualiaKitBert device check").font(.title2)
            Text(status)
            if let reportURL { ShareLink("Share report", item: reportURL) }
            Text("Fixed public scenes only. No comfort or battery claim.").font(.caption)
        }
        .padding()
        .task(id: scenePhase) {
            guard scenePhase == .active, !started else { return }
            started = true
            status = "Checking the model and bounded playback…"
            do {
                let data = try await QualiaKitBertDeviceCheck.run()
                let directory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                let url = directory.appendingPathComponent("qualiakit-bert-device.json")
                try data.write(to: url, options: .atomic)
                reportURL = url
                status = "Checks completed. The report includes timings and playback checks."
            } catch {
                status = "Check failed: \(error)"
            }
        }
    }
}

@MainActor
enum QualiaKitBertDeviceCheck {
    static func run() async throws -> Data {
        let before = try footprint()
        let evaluation = try await QualiaKitBert.evaluationReport()
        var report = try JSONSerialization.jsonObject(with: evaluation) as! [String: Any]
        report["physicalDevice"] = isPhysical
        report["deviceModel"] = hardware()
        report["appBuild"] = Bundle.main.infoDictionary?["CFBundleVersion"]
        report["processFootprintBeforeBytes"] = before
        report["processFootprintAfterModelEvaluationBytes"] = try footprint()
        report["humanComfort"] = "not-assessed"
        report["battery"] = "not-measured"
        let renderer = CoreHapticRenderer()
        let analyzer = try await QualiaKitBert.analyzer()
        let supported = renderer.capabilities.supportsContinuousHaptics
        let session = try await QualiaSession.configured(analyzer: analyzer, renderer: supported ? renderer : NoOpHapticRenderer(),
            configuration: QualiaKitBert.configuration(hapticsAvailable: supported))
        do {
            try await session.updateHapticPreferences(.init(continuousEffectsEnabled: !UIAccessibility.isReduceMotionEnabled,
                intensityScale: 0.5, maximumContinuousDuration: .seconds(6)))
            let response = try await session.process(.init(id: .init(rawValue: "device-suspense"), text: QualiaKitBert.scenes[1].text))
            if let failure = response.execution.failure { throw failure }
            let shouldPlay = supported && !UIAccessibility.isReduceMotionEnabled
            guard renderer.activeEffects.isEmpty != shouldPlay else { throw CheckFailure.unexpectedPlayback }
            report["heartbeatStarted"] = !renderer.activeEffects.isEmpty
            report["reduceMotion"] = UIAccessibility.isReduceMotionEnabled
            report["processFootprintWithSessionBytes"] = try footprint()
            try await Task.sleep(for: .milliseconds(700))
            try await session.suspend()
            guard renderer.activeEffects.isEmpty else { throw CheckFailure.didNotStop }
            try await session.resume()
            guard renderer.activeEffects.isEmpty else { throw CheckFailure.replayed }
            report["suspendStoppedAndResumeStayedSilent"] = true
            try await session.reset()
            let quiet = try await session.process(.init(id: .init(rawValue: "device-quiet"), text: QualiaKitBert.scenes[0].text))
            if let failure = quiet.execution.failure { throw failure }
            guard renderer.activeEffects.isEmpty else { throw CheckFailure.unexpectedPlayback }
            report["quietSceneStayedSilent"] = true
            try await session.reset()
        } catch {
            try await session.reset()
            throw error
        }
        return try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
    }

    private enum CheckFailure: Error { case unexpectedPlayback, didNotStop, replayed, memoryUnavailable }

    private static var isPhysical: Bool {
#if targetEnvironment(simulator)
        false
#else
        true
#endif
    }

    private static func footprint() throws -> UInt64 {
        var memory = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &memory) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { throw CheckFailure.memoryUnavailable }
        return memory.phys_footprint
    }

    private static func hardware() -> String {
        var system = utsname()
        uname(&system)
        let capacity = MemoryLayout.size(ofValue: system.machine)
        return withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
    }
}
#endif
