import SwiftUI

@main
struct WatchSensorLabApp: App {
    @StateObject private var tracker = TrackerModel()

    var body: some Scene {
        WindowGroup {
            TrackerRootView(tracker: tracker)
                .environmentObject(tracker)
                .preferredColorScheme(.dark)
        }
    }
}

private struct TrackerRootView: View {
    @ObservedObject var tracker: TrackerModel
    @State private var completedSummary: TrackerSummary?

    private let store = NativeSessionStore()

    var body: some View {
        LiveTrackerView()
            .onChange(of: tracker.lastSummary) { previous, current in
                guard let current, previous?.sessionID != current.sessionID else { return }
                completedSummary = store.listSummaries().first(where: { $0.sessionID == current.sessionID }) ?? current
            }
            .sheet(item: $completedSummary) { summary in
                PostActivitySummaryView(summary: summary)
            }
    }
}
