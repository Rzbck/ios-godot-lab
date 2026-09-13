import SwiftUI

@main
struct WatchSensorLabWatchFinishUIHarnessApp: App {
    @StateObject private var model = SensorModel()

    var body: some Scene {
        WindowGroup {
            ActiveWorkoutView()
                .environmentObject(model)
                .overlay(alignment: .topLeading) {
                    Text(model.finishResult)
                        .font(.system(size: 7))
                        .padding(2)
                        .background(.black.opacity(0.55), in: Capsule())
                        .accessibilityIdentifier("harness.finish.result")
                }
        }
    }
}
