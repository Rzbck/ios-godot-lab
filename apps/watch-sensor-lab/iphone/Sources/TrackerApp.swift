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
    private let recentHistoryBridge = PhoneRecentHistoryBridge()

    var body: some View {
        LiveTrackerView()
            .task {
                try? await Task.sleep(for: .seconds(1))
                WatchReliableRecovery.refreshAllAvailableSummaries()
                recentHistoryBridge.publish(summaries: store.listSummaries())
            }
            .onChange(of: tracker.lastSummary) { previous, current in
                guard let current, previous?.sessionID != current.sessionID else { return }
                WatchReliableRecovery.refreshSummaryIfNeeded(sessionID: current.sessionID)
                let summaries = store.listSummaries()
                completedSummary = summaries.first(where: { $0.sessionID == current.sessionID }) ?? current
                recentHistoryBridge.publish(summaries: summaries)
            }
            .sheet(item: $completedSummary) { summary in
                PostActivitySummaryView(summary: summary)
            }
    }
}
