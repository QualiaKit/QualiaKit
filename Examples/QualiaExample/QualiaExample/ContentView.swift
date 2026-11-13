import SwiftUI

@MainActor
struct ContentView: View {
    @StateObject private var model = SentimentModel()
    @State private var text = "This is a wonderful, joyful day!"
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Form {
                Section("English text") {
                    TextField("Enter one paragraph", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                    Button("Analyze and feel") {
                        Task { await model.analyze(text) }
                    }
                    .disabled(!model.isReady || model.isProcessing || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Section("Result") {
                    Text(model.status)
                    Button("Reset") { model.setActive(scenePhase == .active, reset: true) }
                }
                Section {
                    Text("Apple's on-device sentiment analyzer produces a short pulse for positive or negative English text. Scores run from 0 (negative) to 100 (positive). Neutral text may produce no pulse. A compatible iPhone is required.")
                        .font(.footnote)
                }
            }
            .navigationTitle("QualiaKit")
        }
        .onAppear { model.setActive(scenePhase == .active) }
        .onChange(of: scenePhase) { phase in model.setActive(phase == .active) }
        .onDisappear { model.setActive(false, reset: true) }
    }
}
