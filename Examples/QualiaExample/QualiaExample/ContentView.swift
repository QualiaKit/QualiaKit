import QualiaKit
import SwiftUI

/// LivingStory uses accepted events for production state and an isolated,
/// opt-in session for draft preview. It contains no analyzer heuristics.
struct ContentView: View {
    @StateObject private var model = LivingStoryModel()
    @Environment(\.scenePhase) private var scenePhase
    @State private var hapticsEnabled = true
    @State private var continuousEffectsEnabled = true
    @State private var intensity = 0.5
    @State private var maximumDuration = 10.0

    var body: some View {
        Group {
            if let storySession = model.storySession,
               let previewSession = model.previewSession {
                LivingStoryView(
                    model: model,
                    storySession: storySession,
                    previewSession: previewSession,
                    hapticsEnabled: $hapticsEnabled,
                    continuousEffectsEnabled: $continuousEffectsEnabled,
                    intensity: $intensity,
                    maximumDuration: $maximumDuration
                )
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Label("Preparing LivingStory", systemImage: "waveform")
                    Text(model.status)
                        .font(.footnote)
                }
                .padding()
            }
        }
        .task {
            await model.start(
                preferences: preferences,
                active: scenePhase == .active
            )
        }
        .task(id: preferences) { model.updatePreferences(preferences) }
        .task(id: scenePhase) { model.setActive(scenePhase == .active) }
        .onDisappear { model.leaveStory() }
    }

    private var preferences: QualiaHapticPreferences {
        do {
            return try .init(
                enabled: hapticsEnabled,
                continuousEffectsEnabled: continuousEffectsEnabled,
                intensityScale: Float(intensity),
                maximumContinuousDuration: .seconds(maximumDuration)
            )
        } catch {
            preconditionFailure("LivingStory controls produced invalid preferences")
        }
    }
}

private struct LivingStoryView: View {
    @ObservedObject var model: LivingStoryModel
    let storySession: QualiaSession
    let previewSession: QualiaSession
    @Binding var hapticsEnabled: Bool
    @Binding var continuousEffectsEnabled: Bool
    @Binding var intensity: Double
    @Binding var maximumDuration: Double
    @State private var draft = ""
    @State private var showDebug = true

    var body: some View {
        NavigationStack {
            Form {
                storySection
                previewSection
                capabilitySection
                hapticSection
#if DEBUG
                debugSection
#endif
                lifecycleSection
            }
            .navigationTitle("LivingStory")
        }
        .background {
            if let event = model.acceptedEvent {
                Color.clear
                    .frame(width: 0, height: 0)
                    .qualiaReaction(
                        eventID: event.id,
                        input: event.input,
                        session: storySession,
                        onResult: model.consumeStoryResult
                    )
            }
        }
    }

    private var storySection: some View {
        Section("Accepted story events") {
            ForEach(model.visibleFragments) { fragment in
                Text(fragment.text)
                    .accessibilityLabel("Accepted story fragment: \(fragment.text)")
            }
            Button(model.hasNextFragment ? "Accept next fragment" : "Story complete") {
                model.acceptNextFragment()
            }
            .disabled(!model.ready || !model.hasNextFragment)
            Text(model.status)
                .font(.footnote)
                .accessibilityLabel("Story analysis status: \(model.status)")
        }
    }

    private var previewSection: some View {
        Section("Opt-in isolated draft preview") {
            TextField("Try one English paragraph", text: $draft, axis: .vertical)
                .qualiaLiveReaction(
                    text: $draft,
                    debounce: .milliseconds(350),
                    minimumCharacters: 3,
                    session: previewSession,
                    onResult: model.consumePreviewResult
                )
            Text(model.previewStatus)
                .font(.footnote)
                .accessibilityLabel("Draft preview status: \(model.previewStatus)")
            Text("Draft text is analyzed after debounce in a separate analysis-only session; it never advances the accepted story scene.")
                .font(.caption)
        }
    }

    private var capabilitySection: some View {
        Section("Capabilities") {
            Label(model.analyzerCapability, systemImage: "brain.head.profile")
            Label(model.hapticCapability, systemImage: "hand.tap")
        }
    }

    private var hapticSection: some View {
        Section("Haptic accessibility") {
            Toggle("Enable haptics", isOn: $hapticsEnabled)
            Toggle("Allow continuous effects", isOn: $continuousEffectsEnabled)
            Slider(value: $intensity, in: 0...1) {
                Text("Haptic intensity")
            }
            Text("Intensity: \(Int(intensity * 100))%")
                .accessibilityLabel("Haptic intensity \(Int(intensity * 100)) percent")
            Stepper(
                "Maximum continuous duration: \(Int(maximumDuration)) seconds",
                value: $maximumDuration,
                in: 1...30
            )
        }
    }

#if DEBUG
    private var debugSection: some View {
        Section("Redacted diagnostics") {
            Toggle("Show debug details", isOn: $showDebug)
            if showDebug {
                DebugRow(label: "Language", value: model.debug.language)
                DebugRow(label: "Observation", value: model.debug.observation)
                DebugRow(label: "Scene", value: model.debug.scene)
                DebugRow(label: "Policy", value: model.debug.policy)
                DebugRow(label: "Haptic plan", value: model.debug.haptics)
                DebugRow(label: "Error", value: model.debug.error)
                DebugRow(label: "Diagnostic events", value: model.diagnosticSummary)
            }
        }
    }
#endif

    private var lifecycleSection: some View {
        Section {
            Button("Reset story and stop owned effects") {
                draft = ""
                model.resetStory()
            }
            .disabled(!model.hasSessions)
        } footer: {
            Text("Leaving resets both sessions. Backgrounding suspends them; returning resumes without replaying an old effect.")
        }
    }
}

private struct DebugRow: View {
    let label: String
    let value: String

    var body: some View {
        LabeledContent(label, value: value)
            .font(.caption.monospaced())
    }
}
