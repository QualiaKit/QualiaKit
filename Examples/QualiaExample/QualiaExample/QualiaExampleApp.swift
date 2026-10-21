import SwiftUI

@main
struct QualiaExampleApp: App {
    var body: some Scene {
        WindowGroup {
#if QUALIA_DEVICE_EVALUATION
            DeviceEvaluationView()
#else
            ContentView()
#endif
        }
    }
}
