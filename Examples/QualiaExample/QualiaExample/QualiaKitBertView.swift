import QualiaExamples
import QualiaKit
import SwiftUI

struct QualiaKitBertView: View {
    @StateObject private var model = QualiaKitBertDemoModel(renderer: CoreHapticRenderer())
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var text = QualiaKitBert.scenes[0].text
    @State private var continuingStory = false
    @State private var haptics = true
    @State private var intensity = 0.5
    @State private var visible = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Turn a short English scene into a heartbeat, entirely on this device.")
                    Text("Experimental model · 11 narrative signals · English only")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Try a scene") {
                    ForEach(QualiaKitBert.scenes) { scene in
                        Button(scene.id) { text = scene.text; continuingStory = false }
                    }
                    TextField("Write a short scene in English", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                    Toggle("Continue story with previous scenes", isOn: $continuingStory)
                    Button("Analyze and feel") { model.submit(text, continuingStory: continuingStory) }
                        .disabled(!model.ready || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if model.busy { ProgressView() }
                    Text(model.status).font(.footnote).accessibilityLabel("Status: \(model.status)")
                }
                if continuingStory, !model.history.isEmpty {
                    Section("Context for the next scene") {
                        ForEach(Array(model.history.enumerated()), id: \.offset) { _, scene in Text(scene).font(.caption) }
                    }
                }
                Section("Haptics") {
                    Toggle("Enable haptics", isOn: $haptics)
                    Slider(value: $intensity, in: 0...1) { Text("Haptic intensity") }
                    Text("Intensity: \(Int(intensity * 100))% · maximum 6 seconds")
                        .font(.caption)
                    if reduceMotion { Text("Reduce Motion is on. Continuous effects are disabled.") }
                    if !model.hapticsAvailable { Text("Analysis only. Feel the effects on a compatible iPhone.") }
                }
                if !model.signals.isEmpty {
                    Section("Model scores") {
                        ForEach(model.signals.keys.sorted { $0.rawValue < $1.rawValue }, id: \.self) { signal in
                            LabeledContent(signal.rawValue, value: String(format: "%.3f", model.signals[signal]?.value ?? 0))
                        }
                        Text("Scores are uncalibrated. They do not measure your feelings or emotional intensity. This demo uses suspense and threat for the heartbeat.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Text("Keep the scene and its previous context short: 128 model tokens in total. Oversized input is rejected. Text stays on this device; nothing is uploaded or saved by this demo.")
                        .font(.caption)
                    Text("Choosing a preset starts a separate story on the next Analyze. Stop clears context. Backgrounding or leaving this tab stops playback; returning stays silent until you analyze again.")
                        .font(.caption)
                }
            }
            .navigationTitle("QualiaKitBert")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Stop", role: .destructive) { model.stop() }
                        .accessibilityLabel("Stop playback and clear story")
                }
            }
        }
        .onAppear { visible = true; updateLifecycle() }
        .onDisappear { visible = false; model.deactivate() }
        .onChange(of: scenePhase) { _, _ in updateLifecycle() }
        .onChange(of: preferences) { _, _ in updateLifecycle() }
    }

    private var preferences: QualiaHapticPreferences {
        // All controls are bounded; an invalid constant is a programming error.
        try! .init(enabled: haptics, continuousEffectsEnabled: !reduceMotion,
                   intensityScale: Float(intensity), maximumContinuousDuration: .seconds(6))
    }

    private func updateLifecycle() {
        if visible, scenePhase == .active { model.activate(preferences: preferences) }
        else { model.deactivate() }
    }
}
