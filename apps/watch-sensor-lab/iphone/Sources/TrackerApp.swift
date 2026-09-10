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

private enum TrackerAppSection: Hashable {
    case today
    case activity
    case progression
    case history
}

private struct TrackerRootView: View {
    @ObservedObject var tracker: TrackerModel
    @State private var completedSummary: TrackerSummary?
    @State private var selection: TrackerAppSection = .today

    private let store = NativeSessionStore()
    private let recentHistoryBridge = PhoneRecentHistoryBridge()

    var body: some View {
        TabView(selection: $selection) {
            TodayDashboardView(
                openActivity: { selection = .activity },
                openHistory: { selection = .history }
            )
            .tag(TrackerAppSection.today)
            .tabItem { Label("Aujourd’hui", systemImage: "sparkles") }

            ActivityHubView()
                .tag(TrackerAppSection.activity)
                .tabItem { Label("Activité", systemImage: "figure.run") }

            ProgressionDashboardView()
                .tag(TrackerAppSection.progression)
                .tabItem { Label("Progression", systemImage: "chart.xyaxis.line") }

            ActivityHistoryView()
                .tag(TrackerAppSection.history)
                .tabItem { Label("Historique", systemImage: "clock.arrow.circlepath") }
        }
        .task {
            try? await Task.sleep(for: .seconds(1))
            WatchReliableRecovery.refreshAllAvailableSummaries()
            recentHistoryBridge.publish(summaries: store.listSummaries())
        }
        .onChange(of: tracker.isActive) { _, active in
            if active { selection = .activity }
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
