import SwiftUI

@main
struct WatchSensorLabApp: App {
    @StateObject private var tracker = TrackerModel()

    var body: some Scene {
        WindowGroup {
            LiveTrackerView()
                .environmentObject(tracker)
                .preferredColorScheme(.dark)
        }
    }
}
