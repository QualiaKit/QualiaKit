import Combine
import Foundation
import QualiaKit
import SwiftUI

/// Programmatic session example; no custom text heuristics or raw-text logging.
struct ContentView: View {
    @StateObject private var model = ExampleModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var text = ""
    @State private var enabled = true
    @State private var continuous = true
    @State private var intensity = 0.5
    @State private var maximumDuration = 10.0

    var body: some View {
        NavigationStack {
            Form {
                Section("On-device text preview") {
                    TextField("One paragraph in English", text: $text, axis: .vertical)
                    Button("Analyze accepted text") { model.process(text) }
                        .disabled(!model.ready || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text(model.status)
                        .accessibilityLabel("Analysis status: \(model.status)")
                    Text("This describes text tone, not your feelings or health.")
                        .font(.footnote)
                }
                Section("Haptic preferences") {
                    Toggle("Enable haptics", isOn: $enabled)
                    Toggle("Allow continuous effects", isOn: $continuous)
                    Slider(value: $intensity, in: 0...1) { Text("Intensity") }
                    Text("Intensity: \(Int(intensity * 100))%")
                    Stepper("Maximum continuous duration: \(Int(maximumDuration)) seconds",
                            value: $maximumDuration, in: 1...30)
                    Text(model.capability)
                        .font(.footnote)
                    Text("This Apple sentiment preview uses brief accents. The continuous settings also apply when a narrative policy is installed.")
                        .font(.footnote)
                }
                Button("Reset and stop effects") { model.reset() }
            }
            .navigationTitle("QualiaKit Preview")
        }
        .task { await model.start(preferences: preferences, active: scenePhase == .active) }
        .onChange(of: preferences) { value in model.update(value) }
        .onChange(of: scenePhase) { value in model.setActive(value == .active) }
        .onDisappear { model.reset() }
    }

    private var preferences: QualiaHapticPreferences {
        // Controls constrain these to validated ranges.
        try! .init(enabled: enabled, continuousEffectsEnabled: continuous, intensityScale: Float(intensity),
                   maximumContinuousDuration: .seconds(maximumDuration))
    }
}

@MainActor
private final class ExampleModel: ObservableObject {
    @Published private(set) var ready = false
    @Published private(set) var status = "Ready for one English paragraph."
    @Published private(set) var capability = "Checking haptic support…"
    private var session: QualiaSession?
    private var active = true
    private var revision = 0
    private var desiredPreferences = QualiaHapticPreferences.default

    func start(preferences: QualiaHapticPreferences, active: Bool) async {
        guard session == nil else { return }
        self.active = active
        desiredPreferences = preferences
        let physical = CoreHapticRenderer()
        let supportsHaptics = physical.capabilities.supportsHaptics
        capability = supportsHaptics ? "Haptic hardware available." : "Haptic hardware unavailable; analysis remains available."
        do {
            let renderer: any HapticRendering = supportsHaptics ? physical : NoOpHapticRenderer()
            let policy: any QualiaReactionPolicy = supportsHaptics ? SentimentPulsePolicy() : NoReactionPolicy()
            let dependencies = QualiaSessionDependencies(analyzer: AppleSentimentAnalyzer(),
                languageResolver: try QualiaLanguageResolver(policy: .requireExplicit, minimumConfidence: 0.8),
                contextWindow: .init(configuration: try .init(maximumFragments: 0, maximumCharacters: 4000,
                                                              maximumUTF8Bytes: 16000)),
                stateReducer: QualiaSceneReducer(), reactionPolicy: policy, clock: QualiaContinuousClock())
            let created = try await QualiaSession(dependencies: dependencies,
                renderer: .init(renderer: renderer, arbitration: .independentOwners), preferences: preferences)
            session = created
            if desiredPreferences != preferences { try await created.updateHapticPreferences(desiredPreferences) }
            if !self.active { try await created.suspend() }
            ready = self.active
        } catch { status = "The session could not be prepared." }
    }

    func process(_ text: String) {
        guard let session, ready else { return }
        revision += 1
        let request = revision
        Task {
            do {
                let response = try await session.process(.init(id: .init(rawValue: UUID().uuidString), text: text,
                                                               language: .init(rawValue: "en")))
                guard revision == request else { return }
                if let valence = response.observation.dimensions.valence {
                    status = "Text valence: \(Int(valence.value * 100)) / 100."
                }
                if response.execution.failure != nil { status += " Haptic playback failed; reset to retry." }
            } catch is CancellationError { }
            catch { if revision == request { status = "Analysis unavailable. Enter one English paragraph and try again." } }
        }
    }

    func update(_ preferences: QualiaHapticPreferences) {
        desiredPreferences = preferences
        guard let session else { return }
        revision += 1
        let request = revision
        ready = false
        Task {
            do {
                try await session.updateHapticPreferences(preferences)
                if revision == request { ready = active }
            } catch is CancellationError { }
            catch { status = "Could not stop playback. Reset before continuing." }
        }
    }

    func setActive(_ active: Bool) {
        self.active = active
        revision += 1
        ready = false
        guard let session else { return }
        let request = revision
        Task {
            do {
                if active { try await session.resume() } else { try await session.suspend() }
                if revision == request { ready = active }
            } catch is CancellationError { }
            catch { status = "Haptic cleanup required. Reset before continuing." }
        }
    }

    func reset() {
        guard let session else { return }
        revision += 1
        let request = revision
        ready = false
        Task {
            do {
                try await session.reset()
                if revision == request { ready = active; status = "Context cleared and owned effects stopped." }
            } catch is CancellationError { }
            catch { status = "Cleanup failed. Try reset again." }
        }
    }
}
