import SwiftUI

@main
struct QualiaExampleApp: App {
    var body: some Scene {
        WindowGroup {
#if QUALIA_DEVICE_EVALUATION
            DeviceEvaluationView()
#else
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--qualiakit-bert-check") {
                QualiaKitBertDeviceCheckView()
            } else { examples }
#else
            examples
#endif
#endif
        }
    }

    private var examples: some View {
        TabView {
            QualiaKitBertView().tabItem { Label("QualiaKitBert", systemImage: "brain.head.profile") }
            ContentView().tabItem { Label("SentimentPreview", systemImage: "text.bubble") }
            ContentView(narrative: true).tabItem { Label("LivingStory", systemImage: "waveform.path.ecg") }
        }
    }
}
