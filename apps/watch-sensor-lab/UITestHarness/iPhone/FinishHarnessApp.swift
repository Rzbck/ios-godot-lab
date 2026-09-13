import SwiftUI

@main
struct WatchSensorLabFinishUIHarnessApp: App {
    @StateObject private var tracker = TrackerModel()

    var body: some Scene {
        WindowGroup {
            ActivityExperienceView()
                .environmentObject(tracker)
                .overlay(alignment: .topLeading) {
                    Text(tracker.finishResult)
                        .font(.caption2)
                        .padding(4)
                        .background(.black.opacity(0.6), in: Capsule())
                        .accessibilityIdentifier("harness.finish.result")
                        .padding(4)
                }
                .preferredColorScheme(.dark)
        }
    }
}
