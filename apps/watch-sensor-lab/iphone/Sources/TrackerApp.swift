import Combine
import SwiftUI

@main
struct WatchSensorLabApp: App {
    @StateObject private var startupPermissions = StartupPermissionCoordinator()

    var body: some Scene {
        WindowGroup {
            Group {
                if startupPermissions.healthRequestFinished {
                    TrackerAppContainer(startupPermissions: startupPermissions)
                } else {
                    StartupPermissionView()
                }
            }
            .preferredColorScheme(.dark)
            .onAppear { startupPermissions.start() }
        }
    }
}

private struct StartupPermissionView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.mint)
            Text("Préparation de Watch Tracker")
                .font(.title3.weight(.bold))
            Text("Autorise les données utilisées par l’historique, la progression et le suivi sportif.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            ProgressView()
        }
        .padding(28)
    }
}

private struct TrackerAppContainer: View {
    @ObservedObject var startupPermissions: StartupPermissionCoordinator
    @StateObject private var tracker = TrackerModel()

    var body: some View {
        TrackerRootView(tracker: tracker, startupPermissions: startupPermissions)
            .environmentObject(tracker)
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
    @ObservedObject var startupPermissions: StartupPermissionCoordinator
    @ObservedObject private var osmContext = OSMRouteContextService.shared
    @State private var completedSummary: TrackerSummary?
    @State private var selection: TrackerAppSection = .today

    private let store = NativeSessionStore()
    private let recentHistoryBridge = PhoneRecentHistoryBridge()

    var body: some View {
        TabView(selection: $selection) {
            TodayExperienceView(
                openActivity: { selection = .activity },
                openProgression: { selection = .progression },
                openHistory: { selection = .history }
            )
            .tag(TrackerAppSection.today)
            .tabItem { Label("Aujourd’hui", systemImage: "sparkles") }

            ActivityProductContainerView()
                .tag(TrackerAppSection.activity)
                .tabItem { Label("Activité", systemImage: "figure.run") }

            ProgressionEntryView()
                .tag(TrackerAppSection.progression)
                .tabItem { Label("Progression", systemImage: "chart.xyaxis.line") }

            HistoryEntryView()
                .tag(TrackerAppSection.history)
                .tabItem { Label("Historique", systemImage: "clock.arrow.circlepath") }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if tracker.isActive, selection == .activity, OSMSurfacePreferences.enabled {
                OSMLiveSurfaceBar()
            }
        }
        .task {
            WatchReliableRecovery.refreshAllAvailableSummaries()
            recentHistoryBridge.publish(summaries: store.listSummaries())
        }
        .onChange(of: tracker.watchReachable) { _, reachable in
            guard reachable else { return }
            recentHistoryBridge.publish(summaries: store.listSummaries())
        }
        .onChange(of: tracker.isActive) { _, active in
            if active {
                selection = .activity
                osmContext.begin(sessionID: tracker.sessionID, activity: tracker.displayActivity.rawValue)
            }
        }
        .onReceive(tracker.$currentCoordinate) { coordinate in
            guard tracker.isActive, let coordinate else { return }
            if osmContext.currentSnapshot() == nil {
                osmContext.begin(sessionID: tracker.sessionID, activity: tracker.displayActivity.rawValue)
            }
            osmContext.ingest(
                coordinate: coordinate,
                horizontalAccuracy: tracker.horizontalAccuracy,
                activity: tracker.displayActivity.rawValue
            )
        }
        .onChange(of: tracker.lastSummary) { previous, current in
            guard let current, previous?.sessionID != current.sessionID else { return }
            osmContext.finish(sessionID: current.sessionID, endedAt: current.endedAt)
            WatchReliableRecovery.refreshSummaryIfNeeded(sessionID: current.sessionID)
            let summaries = store.listSummaries()
            completedSummary = summaries.first(where: { $0.sessionID == current.sessionID }) ?? current
            recentHistoryBridge.publish(summaries: summaries)
        }
        .sheet(item: $completedSummary) { summary in
            OSMPostActivitySummaryContainer(summary: summary)
        }
    }
}
