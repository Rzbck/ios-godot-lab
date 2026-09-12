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
            .onAppear {
                AppTelemetry.shared.configure(platform: "iphone", buildSHA: BuildInfo.gitSHA)
                AppTelemetry.shared.event("app_root_appeared", screen: "startup")
                startupPermissions.start()
            }
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
        .onAppear {
            AppTelemetry.shared.event("screen_appeared", screen: "startup_permissions")
        }
    }
}

private struct TrackerAppContainer: View {
    @ObservedObject var startupPermissions: StartupPermissionCoordinator
    @StateObject private var tracker = TrackerModel()
    @StateObject private var telemetry = TrackerTelemetryCoordinator()

    var body: some View {
        TrackerRootView(
            tracker: tracker,
            startupPermissions: startupPermissions,
            telemetry: telemetry
        )
        .environmentObject(tracker)
    }
}

private enum TrackerAppSection: Hashable {
    case today
    case activity
    case progression
    case history
    case recovery

    var telemetryName: String {
        switch self {
        case .today: return "today"
        case .activity: return "activity"
        case .progression: return "progression"
        case .history: return "history"
        case .recovery: return "recovery"
        }
    }
}

private struct TrackerRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var tracker: TrackerModel
    @ObservedObject var startupPermissions: StartupPermissionCoordinator
    @ObservedObject var telemetry: TrackerTelemetryCoordinator
    @State private var completedSummary: TrackerSummary?
    @State private var selection: TrackerAppSection = .today

    private let store = NativeSessionStore()
    private let recentHistoryBridge = PhoneRecentHistoryBridge()

    var body: some View {
        rootTabs
            .simultaneousGesture(
                SpatialTapGesture().onEnded { value in
                    telemetry.recordTap(
                        x: Double(value.location.x),
                        y: Double(value.location.y)
                    )
                }
            )
            .onAppear {
                telemetry.start(tracker: tracker)
                telemetry.setScreen(selection.telemetryName)
            }
            .task {
                WatchReliableRecovery.refreshAllAvailableSummaries()
                recentHistoryBridge.publish(summaries: store.listSummaries())
            }
            .onChange(of: scenePhase) { _, phase in
                telemetry.scenePhaseChanged(String(describing: phase))
            }
            .onChange(of: selection) { previous, current in
                telemetry.setScreen(
                    current.telemetryName,
                    previous: previous.telemetryName
                )
            }
            .onReceive(tracker.$watchReachable.removeDuplicates()) { reachable in
                guard reachable else { return }
                recentHistoryBridge.publish(summaries: store.listSummaries())
            }
            .onReceive(tracker.$phase.removeDuplicates()) { phase in
                if phase == .active || phase == .paused {
                    selection = .activity
                }
            }
            .onReceive(tracker.$lastSummary.compactMap { $0 }) { summary in
                handleCompletedSummary(summary)
            }
            .sheet(item: $completedSummary) { summary in
                PostActivitySummaryView(summary: summary)
                    .onAppear {
                        AppTelemetry.shared.event(
                            "screen_appeared",
                            screen: "post_activity_summary",
                            fields: [
                                "session_id": summary.sessionID,
                                "activity": summary.activity,
                            ]
                        )
                    }
            }
    }

    private var rootTabs: some View {
        TabView(selection: $selection) {
            TodayCommandCenterView(
                openActivity: {
                    AppTelemetry.shared.action("open_activity", screen: selection.telemetryName)
                    selection = .activity
                },
                openProgression: {
                    AppTelemetry.shared.action("open_progression", screen: selection.telemetryName)
                    selection = .progression
                },
                openHistory: {
                    AppTelemetry.shared.action("open_history", screen: selection.telemetryName)
                    selection = .history
                }
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

            HistoricalRecoveryDiagnosticHostView()
                .tag(TrackerAppSection.recovery)
                .tabItem { Label("Récupération", systemImage: "arrow.clockwise.heart.fill") }
        }
    }

    private func handleCompletedSummary(_ summary: TrackerSummary) {
        WatchReliableRecovery.refreshSummaryIfNeeded(sessionID: summary.sessionID)
        let summaries = store.listSummaries()
        completedSummary = summaries.first(where: { $0.sessionID == summary.sessionID }) ?? summary
        recentHistoryBridge.publish(summaries: summaries)
        telemetry.emitSnapshot(reason: "summary_received")
    }
}
