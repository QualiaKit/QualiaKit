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
        Self(
            language: "resolved · " + languageSource,
            observation: "\(response.observation.signals.count) signals; valence " +
                (response.observation.dimensions.valence == nil ? "absent" : "present") + "; scores omitted",
            scene: "revision \(response.transition.previous.revision) → \(response.transition.current.revision)",
            policy: "planned commands: \(response.reaction.hapticCommands.count)",
            haptics: response.reaction.hapticCommands.map(commandSummary).joined(separator: ", "),
            error: response.execution.failure.map { String(describing: $0) } ?? "none"
        )
    }

    static func failure(_ description: String) -> Self {
        var state = Self()
        state.error = description
        return state
    }

    nonisolated private static func commandSummary(_ command: HapticCommand) -> String {
        switch command {
        case .play(_, let channel):
            return "play · \(channelName(channel))"
        case .start(_, _, let channel):
            return "start · \(channelName(channel))"
        case .replace(_, _, let channel):
            return "replace · \(channelName(channel))"
        case .stop:
            return "stop owned effect"
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
    private var recent: [QualiaDiagnosticEvent] = []

    var summary: String {
        lock.lock()
        let snapshot = recent
        let total = count
        lock.unlock()
        do {
            let report = try QualiaDecisionReport(events: snapshot, maximumEvents: 24)
            return "\(total) events; showing last \(report.lines.count)\n" + report.text
        } catch { return "Diagnostic report configuration failed" }
    }

    func record(_ event: QualiaDiagnosticEvent) {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        if recent.count == 256 { recent.removeFirst() }
        recent.append(event)
    }

}
