import Combine
import Foundation
import QualiaKit

/// Owns one demo session; serializes lifecycle changes and cancels obsolete input.
@MainActor
public final class QualiaKitBertDemoModel: ObservableObject {
    @Published public private(set) var status = "Preparing QualiaKitBert…"
    @Published public private(set) var busy = false
    @Published public private(set) var ready = false
    @Published public private(set) var signals: [QualiaSignal: QualiaScore] = [:]
    @Published public private(set) var history: [String] = []
    public let hapticsAvailable: Bool

    private let renderer: any HapticRendering
    private let load: () async throws -> any QualiaAnalyzing
    private var session: QualiaSession?
    private var operation: Task<Void, Never>?
    private var revision = 0
    private var active = false
    private var preferences = QualiaHapticPreferences.disabled

    public init(renderer: any HapticRendering,
                load: @escaping () async throws -> any QualiaAnalyzing = { try await QualiaKitBert.analyzer() }) {
        self.load = load
        hapticsAvailable = renderer.capabilities.supportsHaptics && renderer.capabilities.supportsContinuousHaptics
        self.renderer = hapticsAvailable ? renderer : NoOpHapticRenderer()
    }

    public func activate(preferences: QualiaHapticPreferences) {
        active = true
        self.preferences = preferences
        enqueue(interruptPlayback: true) {
            if self.session == nil {
                let analyzer = try await self.load()
                try Task.checkCancellation()
                self.session = try await QualiaSession.configured(analyzer: analyzer, renderer: self.renderer,
                    configuration: QualiaKitBert.configuration(hapticsAvailable: self.hapticsAvailable))
            }
            guard let session = self.session else { return }
            try await session.updateHapticPreferences(self.preferences)
            try await session.resume()
            self.status = self.hapticsAvailable
                ? "Ready. Choose a scene or write your own."
                : "Analysis only: this device cannot play continuous haptics."
        }
    }

    public func submit(_ text: String, continuingStory: Bool) {
        guard ready, let session else { return }
        status = "Reading the scene…"
        enqueue {
            if !continuingStory {
                try await session.reset()
                self.history = []
            }
            let response = try await session.process(.init(id: .init(rawValue: UUID().uuidString), text: text))
            try Task.checkCancellation()
            if let failure = response.execution.failure { throw failure }
            self.signals = response.observation.signals
            self.history = Array((self.history + [text]).suffix(2))
            let commands = response.reaction.hapticCommands
            self.status = self.hapticsAvailable
                ? (commands.isEmpty ? "Scene analyzed. No new haptic command." : "Scene applied. Effects last at most 6 seconds; Stop ends them now.")
                : "Scene analyzed. Physical haptics are unavailable on this device."
        }
    }

    public func stop() {
        enqueue(interruptPlayback: true) {
            try await self.session?.reset()
            self.history = []
            self.signals = [:]
            self.status = "Stopped. Story context cleared."
        }
    }

    public func deactivate() {
        active = false
        enqueue(interruptPlayback: true) {
            try await self.session?.suspend()
            self.status = "Paused. Returning does not replay an effect."
        }
    }

    public func waitUntilIdle() async { await operation?.value }

    private func enqueue(interruptPlayback: Bool = false, _ work: @escaping @MainActor () async throws -> Void) {
        revision += 1
        let request = revision
        let previous = operation
        previous?.cancel()
        ready = false
        busy = true
        operation = Task {
            do {
                // Stop hardware before waiting for an analyzer that may ignore cancellation.
                if interruptPlayback { try await self.session?.suspend() }
                await previous?.value
                try Task.checkCancellation()
                if interruptPlayback, self.active { try await self.session?.resume() }
                try await work()
                try Task.checkCancellation()
            } catch is CancellationError {
                // The next queued lifecycle operation owns cleanup.
            } catch {
                self.signals = [:]
                self.history = []
                self.status = self.session == nil
                    ? "Could not load QualiaKitBert. Reopen this tab to retry."
                    : "Could not process this scene. Use English and keep the scene plus context under 128 tokens (roughly 70–90 words)."
                do { try await self.session?.reset() }
                catch {
                    self.status = "Could not stop playback. Leave this screen and try again."
                    if request == self.revision { self.busy = false }
                    return
                }
            }
            if request == self.revision {
                self.operation = nil
                self.busy = false
                self.ready = self.active && self.session != nil
            }
        }
    }
}
