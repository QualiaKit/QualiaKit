#if QUALIA_DEVICE_EVALUATION
import Combine
import Foundation
import QualiaKit
import SwiftUI
import UIKit

struct DeviceCommandRecord: Codable {
    let kind: String
    let elapsedMilliseconds: Double
    let successful: Bool
    let owner: String?
    let activeAmbientCount: Int
}

/// Records successful calls to the real Core Haptics renderer, not a mock.
@MainActor
final class DeviceTracingRenderer: HapticRendering {
    let core = CoreHapticRenderer()
    var records: [DeviceCommandRecord] = []
    var capabilities: HapticCapabilities { core.capabilities }
    var activeEffects: [HapticEffectID: HapticActiveEffect] { core.activeEffects }
    func prepare() throws { try core.prepare() }
    func execute(_ command: HapticCommand) throws { try perform(command, owner: nil) }
    func execute(_ command: HapticCommand, ownedBy owner: HapticOwnerID) throws { try perform(command, owner: owner) }
    func stopEffects(ownedBy owner: HapticOwnerID) throws {
        let start = ContinuousClock.now
        do {
            try core.stopEffects(ownedBy: owner)
            record("stop-owned", start, true, owner)
        } catch {
            record("stop-owned", start, false, owner)
            throw error
        }
    }
    func suspend() async { await core.suspend() }
    func resume() async throws { try await core.resume() }
    private func perform(_ command: HapticCommand, owner: HapticOwnerID?) throws {
        let kind: String
        switch command {
        case .start: kind = "start"
        case .replace: kind = "replace"
        case .play: kind = "play"
        case .stop: kind = "stop"
        case .stopAll: kind = "stop-all"
        case .stopChannel: kind = "stop-channel"
        }
        let start = ContinuousClock.now
        do {
            if let owner { try core.execute(command, ownedBy: owner) }
            else { try core.execute(command) }
            record(kind, start, true, owner)
        } catch {
            record(kind, start, false, owner)
            throw error
        }
    }
    private func record(_ kind: String, _ start: ContinuousClock.Instant, _ success: Bool, _ owner: HapticOwnerID?) {
        records.append(.init(kind: kind, elapsedMilliseconds: DeviceEvaluationBenchmark.milliseconds(start.duration(to: .now)),
                             successful: success, owner: owner?.rawValue, activeAmbientCount: activeEffects.count))
    }
}

struct DeviceEvaluationReport: Codable {
    var schemaVersion = 2
    var runID = UUID().uuidString
    var startedAt = ISO8601DateFormatter().string(from: Date())
    var automaticStatus = "not-started"
    var metadata: [String: String] = [:]
    var benchmarks: [DeviceBenchmarkResult] = []
    var coreML: DeviceCoreMLResult?
    var sustained: DeviceSustainedResult?
    var russian: DeviceRussianResult?
    var russianStatus: String?
    var technicalChecks: [String: String] = [:]
    var commands: [DeviceCommandRecord] = []
    var trials: [DeviceTactileTrial] = []
    var humanAssessment: [String: String] = [:]
    var errors: [String] = []
}

struct DeviceTactileTrial: Codable, Identifiable {
    let id: String
    let profile: String
    let intensityScale: Float
    var status: String
    var assessment: [String: String] = [:]
}

enum DeviceTactileProfile: String, CaseIterable, Identifiable {
    case baseline, medium, strong
    var id: String { rawValue }
    var title: String {
        switch self {
        case .baseline: return "A · исходный"
        case .medium: return "B · средний"
        case .strong: return "C · выраженный"
        }
    }
    var scale: Float {
        switch self {
        case .baseline: return 0.5
        case .medium: return 0.75
        case .strong: return 1
        }
    }
}
#endif
