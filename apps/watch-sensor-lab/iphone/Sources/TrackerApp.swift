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
    @State private var completedSummary: TrackerSummary?
    @State private var selection: TrackerAppSection = .today

    private let store = NativeSessionStore()
    private let recentHistoryBridge = PhoneRecentHistoryBridge()

    var body: some View {
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
        .simultaneousGesture(
            SpatialTapGesture().onEnded { value in
                AppTelemetry.shared.action(
                    "ui_tap",
                    screen: selection.telemetryName,
                    fields: [
                        "x": Double(value.location.x),
                        "y": Double(value.location.y),
                    ]
                )
            }
        )
        .task {
            AppTelemetry.shared.event("tracker_root_started", screen: selection.telemetryName)
            while !Task.isCancelled {
                emitTelemetrySnapshot(reason: "heartbeat")
                do {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                } catch {
                    break
                }
            }
        }
        .task {
            WatchReliableRecovery.refreshAllAvailableSummaries()
            recentHistoryBridge.publish(summaries: store.listSummaries())
        }
        .onChange(of: scenePhase) { _, phase in
            AppTelemetry.shared.event(
                "scene_phase_changed",
                screen: selection.telemetryName,
                fields: ["phase": String(describing: phase)]
            )
            emitTelemetrySnapshot(reason: "scene_phase")
        }
        .onChange(of: selection) { previous, current in
            AppTelemetry.shared.action(
                "tab_changed",
                screen: current.telemetryName,
                fields: ["from": previous.telemetryName, "to": current.telemetryName]
            )
            emitTelemetrySnapshot(reason: "tab_changed")
        }
        .onChange(of: tracker.watchReachable) { _, reachable in
            AppTelemetry.shared.event(
                "watch_reachability_changed",
                screen: selection.telemetryName,
                fields: ["reachable": reachable]
            )
            guard reachable else { return }
            recentHistoryBridge.publish(summaries: store.listSummaries())
        }
        .onChange(of: tracker.healthAuthorized) { _, authorized in
            AppTelemetry.shared.event(
                "health_authorization_changed",
                screen: selection.telemetryName,
                fields: ["authorized": authorized]
            )
        }
        .onChange(of: tracker.statusMessage) { previous, current in
            guard previous != current else { return }
            AppTelemetry.shared.event(
                "status_changed",
                screen: selection.telemetryName,
                fields: ["previous": previous, "current": current]
            )
        }
        .onChange(of: tracker.pendingCommand) { previous, current in
            AppTelemetry.shared.event(
                "pending_command_changed",
                screen: selection.telemetryName,
                fields: [
                    "previous": previous ?? "none",
                    "current": current ?? "none",
                    "session_id": tracker.sessionID,
                ]
            )
        }
        .onChange(of: tracker.phase) { previous, current in
            AppTelemetry.shared.event(
                "workout_phase_changed",
                screen: selection.telemetryName,
                fields: [
                    "previous": previous.rawValue,
                    "current": current.rawValue,
                    "session_id": tracker.sessionID,
                ]
            )
            emitTelemetrySnapshot(reason: "phase_changed")
        }
        .onChange(of: tracker.selectedActivity) { previous, current in
            AppTelemetry.shared.event(
                "selected_activity_changed",
                screen: selection.telemetryName,
                fields: ["previous": previous.rawValue, "current": current.rawValue]
            )
        }
        .onChange(of: tracker.effectiveActivity) { previous, current in
            AppTelemetry.shared.event(
                "effective_activity_changed",
                screen: selection.telemetryName,
                fields: ["previous": previous.rawValue, "current": current.rawValue]
            )
        }
        .onChange(of: tracker.finishReviewRequired) { _, required in
            AppTelemetry.shared.event(
                "finish_review_requirement_changed",
                screen: selection.telemetryName,
                fields: [
                    "required": required,
                    "suggested_activity": tracker.suggestedFinalActivity.rawValue,
                ]
            )
            emitTelemetrySnapshot(reason: "finish_review")
        }
        .onChange(of: tracker.isActive) { _, active in
            if active { selection = .activity }
        }
        .onChange(of: tracker.lastSummary) { previous, current in
            guard let current, previous?.sessionID != current.sessionID else { return }
            AppTelemetry.shared.event(
                "summary_received",
                screen: selection.telemetryName,
                fields: [
                    "session_id": current.sessionID,
                    "activity": current.activity,
                    "distance_m": current.distanceMeters,
                    "duration_s": current.duration,
                ]
            )
            WatchReliableRecovery.refreshSummaryIfNeeded(sessionID: current.sessionID)
            let summaries = store.listSummaries()
            completedSummary = summaries.first(where: { $0.sessionID == current.sessionID }) ?? current
            recentHistoryBridge.publish(summaries: summaries)
        }
        .sheet(item: $completedSummary) { summary in
            PostActivitySummaryView(summary: summary)
                .onAppear {
                    AppTelemetry.shared.event(
                        "screen_appeared",
                        screen: "post_activity_summary",
                        fields: ["session_id": summary.sessionID, "activity": summary.activity]
                    )
                }
        }
    }

    private func emitTelemetrySnapshot(reason: String) {
        var fields: [String: Any] = [
            "reason": reason,
            "scene_phase": String(describing: scenePhase),
            "tab": selection.telemetryName,
            "phase": tracker.phase.rawValue,
            "selected_activity": tracker.selectedActivity.rawValue,
            "effective_activity": tracker.effectiveActivity.rawValue,
            "session_id": tracker.sessionID,
            "elapsed_s": tracker.elapsedSeconds,
            "distance_m": tracker.distanceMeters,
            "speed_mps": tracker.currentSpeedMps,
            "average_speed_mps": tracker.averageSpeedMps,
            "max_speed_mps": tracker.maxSpeedMps,
            "altitude_m": tracker.altitudeMeters,
            "elevation_gain_m": tracker.elevationGainMeters,
            "elevation_loss_m": tracker.elevationLossMeters,
            "heart_rate_bpm": tracker.heartRate,
            "average_heart_rate_bpm": tracker.averageHeartRate,
            "max_heart_rate_bpm": tracker.maxHeartRate,
            "active_energy_kcal": tracker.activeEnergyKcal,
            "cadence_spm": tracker.cadenceSPM,
            "steps": tracker.steps,
            "route_points": tracker.route.count,
            "horizontal_accuracy_m": tracker.horizontalAccuracy,
            "watch_reachable": tracker.watchReachable,
            "health_authorized": tracker.healthAuthorized,
            "status_message": tracker.statusMessage,
            "pending_command": tracker.pendingCommand ?? "none",
            "auto_pause_enabled": tracker.autoPauseEnabled,
            "finish_review_required": tracker.finishReviewRequired,
            "finish_review_suggested_activity": tracker.suggestedFinalActivity.rawValue,
            "historical_repair_session_id": tracker.historicalRepairSessionID,
            "historical_repair_status": tracker.historicalRepairStatus,
        ]

        if let coordinate = tracker.currentCoordinate {
            fields["latitude"] = coordinate.latitude
            fields["longitude"] = coordinate.longitude
        }
        if let summary = tracker.lastSummary {
            fields["last_summary"] = [
                "session_id": summary.sessionID,
                "activity": summary.activity,
                "distance_m": summary.distanceMeters,
                "duration_s": summary.duration,
            ]
        }

        let recovery = HistoricalHealthKitRepairV4Coordinator.shared
        fields["recovery_status"] = recovery.statusBySession
        fields["recovery_audits"] = recovery.auditBySession.mapValues { audit in
            [
                "summary_distance_m": audit.summaryDistanceMeters,
                "watch_raw_points": audit.watchRawPoints,
                "iphone_raw_points": audit.phoneRawPoints,
                "watch_filtered_points": audit.watchFilteredPoints,
                "iphone_filtered_points": audit.phoneFilteredPoints,
                "watch_geometry_m": audit.watchGeometryMeters,
                "iphone_geometry_m": audit.phoneGeometryMeters,
                "watch_raw_distance_m": audit.watchRawDistanceMeters as Any,
                "iphone_raw_distance_m": audit.phoneRawDistanceMeters as Any,
                "distance_reference": audit.distanceReferenceSource as Any,
                "chosen_source": audit.chosenSource as Any,
                "chosen_points": audit.chosenPoints,
                "selected_geometry_m": audit.selectedGeometryMeters,
                "active_gaps_over_3s": audit.activeGapsOver3Seconds,
                "max_active_gap_s": audit.maxActiveGapSeconds,
                "generated_workouts": audit.generatedWorkoutCount,
                "normal_workouts": audit.normalWorkoutCount,
                "distance_conflict": audit.distanceConflict,
                "route_geometry_conflict": audit.routeGeometryConflict,
                "route_continuity_conflict": audit.routeContinuityConflict,
                "can_reconstruct": audit.canReconstruct,
            ] as [String: Any]
        }

        AppTelemetry.shared.snapshot("app_state", screen: selection.telemetryName, fields: fields)
    }
}
