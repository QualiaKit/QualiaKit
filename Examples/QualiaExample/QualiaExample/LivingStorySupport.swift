import Foundation
import QualiaKit

struct StoryFragment: Identifiable, Sendable {
    let id: String
    let text: String
}

struct AcceptedStoryEvent: Sendable {
    let id: String
    let input: QualiaInput
}

struct LivingStoryDebugState {
    var language = "not analyzed"
    var observation = "no signal scores"
    var scene = "idle · revision 0"
    var policy = "not evaluated"
    var haptics = "no command"
    var error = "none"

    static func response(_ response: QualiaResponse, languageSource: String) -> Self {
        let signalSummary = response.observation.signals
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue)=\(percent($0.value.value))" }
            .joined(separator: ", ")
        let valence = response.observation.dimensions.valence
            .map { "valence=\(percent($0.value))" }
        let observation = ([valence].compactMap { $0 } + [signalSummary].filter { !$0.isEmpty })
            .joined(separator: ", ")
        let trends = response.transition.current.trends
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { "\($0.key.rawValue)=\(String(describing: $0.value))" }
            .joined(separator: ", ")
        let phase = String(describing: response.transition.current.phase)
        let rule = response.reaction.rationale?.ruleIdentifier ?? "no rationale"
        let facts = response.reaction.rationale?.facts ?? []
        let bpm = facts.first(where: { $0.key == "bpm" })?.value
        let command = response.reaction.hapticCommands.first.map(commandSummary) ?? "no command"
        let haptics = bpm.map { "\(command), \($0) BPM" } ?? command
        let executionError = response.execution.failure.map { String(describing: $0) } ?? "none"

        return Self(
            language: "\(response.observation.language.rawValue) · \(languageSource)",
            observation: observation.isEmpty ? "no signal scores" : observation,
            scene: "\(phase) · revision \(response.transition.current.revision)" +
                (trends.isEmpty ? "" : " · \(trends)"),
            policy: rule,
            haptics: haptics,
            error: executionError
        )
    }

    static func failure(_ description: String) -> Self {
        var state = Self()
        state.error = description
        return state
    }

    nonisolated private static func percent(_ value: Float) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    nonisolated private static func commandSummary(_ command: HapticCommand) -> String {
        switch command {
        case .play(_, let channel):
            return "play · \(channelName(channel))"
        case .start(let id, _, let channel):
            return "start \(id.rawValue) · \(channelName(channel))"
        case .replace(let id, _, let channel):
            return "replace \(id.rawValue) · \(channelName(channel))"
        case .stop(let id):
            return "stop \(id.rawValue)"
        case .stopChannel(let channel):
            return "stop · \(channelName(channel))"
        case .stopAll:
            return "stop all"
        }
    }

    nonisolated private static func channelName(_ channel: HapticChannel) -> String {
        switch channel {
        case .ambient: return "ambient"
        case .accent: return "accent"
        }
    }
}

final class LivingStoryDiagnostics: QualiaDiagnosticsSink, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var latest = "none"

    var summary: String {
        lock.lock()
        defer { lock.unlock() }
        return "\(count) events · latest: \(latest)"
    }

    func record(_ event: QualiaDiagnosticEvent) {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        latest = category(of: event)
    }

    private func category(of event: QualiaDiagnosticEvent) -> String {
        switch event {
        case .fallbackSelected: return "fallback selected"
        case .model: return "model lifecycle"
        case .lifecycle: return "session lifecycle"
        case .started: return "request started"
        case .failed: return "request failed"
        case .discarded: return "stale result discarded"
        case .cancelled: return "request cancelled"
        case .completed: return "request completed"
        case .preparation: return "input prepared"
        case .correlated: return "correlated runtime event"
        }
    }
}
