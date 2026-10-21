import SwiftUI

@main
struct QualiaExampleApp: App {
    var body: some Scene {
        WindowGroup {
#if QUALIA_DEVICE_EVALUATION
            DeviceEvaluationView()
#else
            TabView {
                ContentView().tabItem { Label("SentimentPreview", systemImage: "text.bubble") }
                ContentView(narrative: true).tabItem { Label("LivingStory", systemImage: "waveform.path.ecg") }
            }
#endif
        }
    }
}
