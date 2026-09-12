import Combine
import CoreLocation
import Foundation

/// Central telemetry observer for the iPhone tracker model.
///
/// This deliberately uses Combine subscriptions instead of a long chain of SwiftUI
/// `onChange` modifiers so telemetry stays independent from view composition and can
/// grow as product state grows.
@MainActor
final class TrackerTelemetryCoordinator: ObservableObject {
    private var cancellables = Set<AnyCancellable>()
    private weak var tracker: TrackerModel?
    private var currentScreen = "today"
    private var started = false

    func start(tracker: TrackerModel) {
        guard !started else { return }
        started = true
        self.tracker = tracker

        subscribe(to: tracker)
        AppTelemetry.shared.event("tracker_telemetry_started", screen: currentScreen)
        emitSnapshot(reason: "telemetry_started")

        Timer.publish(every: 2.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.emitSnapshot(reason: "heartbeat")
            }
            .store(in: &cancellables)
    }

    func setScreen(_ screen: String, previous: String? = nil) {
        if let previous, previous != screen {
            AppTelemetry.shared.action(
                "tab_changed",
                screen: screen,
                fields: ["from": previous, "to": screen]
            )
        }
        currentScreen = screen
        emitSnapshot(reason: "screen_changed")
    }

    func scenePhaseChanged(_ phase: String) {
        AppTelemetry.shared.event(
            "scene_phase_changed",
            screen: currentScreen,
            fields: ["phase": phase]
        )
        emitSnapshot(reason: "scene_phase")
    }

    func recordTap(x: Double, y: Double) {
        AppTelemetry.shared.action(
            "ui_tap",
            screen: currentScreen,
            fields: ["x": x, "y": y]
        )
    }

    func emitSnapshot(reason: String) {
        guard let tracker else { return }
        var fields = trackerFields(tracker)
        fields["reason"] = reason
        fields["screen"] = currentScreen
        appendRecoveryFields(to: &fields)
        AppTelemetry.shared.snapshot("app_state", screen: currentScreen, fields: fields)
    }

    private func subscribe(to tracker: TrackerModel) {
        tracker.$watchReachable
            .removeDuplicates()
            .sink { [weak self] reachable in
                guard let self else { return }
                AppTelemetry.shared.event(
                    "watch_reachability_changed",
                    screen: self.currentScreen,
                    fields: ["reachable": reachable]
                )
            }
            .store(in: &cancellables)

        tracker.$healthAuthorized
            .removeDuplicates()
            .sink { [weak self] authorized in
                guard let self else { return }
                AppTelemetry.shared.event(
                    "health_authorization_changed",
                    screen: self.currentScreen,
                    fields: ["authorized": authorized]
                )
            }
            .store(in: &cancellables)

        tracker.$statusMessage
            .removeDuplicates()
            .sink { [weak self] message in
                guard let self else { return }
                AppTelemetry.shared.event(
                    "status_changed",
                    screen: self.currentScreen,
                    fields: ["status": message]
                )
            }
            .store(in: &cancellables)

        tracker.$pendingCommand
            .removeDuplicates()
            .sink { [weak self, weak tracker] command in
                guard let self, let tracker else { return }
                AppTelemetry.shared.event(
                    "pending_command_changed",
                    screen: self.currentScreen,
                    fields: [
                        "command": command ?? "none",
                        "session_id": tracker.sessionID,
                    ]
                )
            }
            .store(in: &cancellables)

        tracker.$phase
            .removeDuplicates()
            .sink { [weak self, weak tracker] phase in
                guard let self, let tracker else { return }
                AppTelemetry.shared.event(
                    "workout_phase_changed",
                    screen: self.currentScreen,
                    fields: [
                        "phase": phase.rawValue,
                        "session_id": tracker.sessionID,
                    ]
                )
                self.emitSnapshot(reason: "phase_changed")
            }
            .store(in: &cancellables)

        tracker.$selectedActivity
            .removeDuplicates()
            .sink { [weak self] activity in
                guard let self else { return }
                AppTelemetry.shared.event(
                    "selected_activity_changed",
                    screen: self.currentScreen,
                    fields: ["activity": activity.rawValue]
                )
            }
            .store(in: &cancellables)

        tracker.$effectiveActivity
            .removeDuplicates()
            .sink { [weak self] activity in
                guard let self else { return }
                AppTelemetry.shared.event(
                    "effective_activity_changed",
                    screen: self.currentScreen,
                    fields: ["activity": activity.rawValue]
                )
            }
            .store(in: &cancellables)

        tracker.$finishReviewRequired
            .removeDuplicates()
            .sink { [weak self, weak tracker] required in
                guard let self, let tracker else { return }
                AppTelemetry.shared.event(
                    "finish_review_requirement_changed",
                    screen: self.currentScreen,
                    fields: [
                        "required": required,
                        "suggested_activity": tracker.suggestedFinalActivity.rawValue,
                    ]
                )
                self.emitSnapshot(reason: "finish_review")
            }
            .store(in: &cancellables)

        tracker.$suggestedFinalActivity
            .removeDuplicates()
            .sink { [weak self] activity in
                guard let self else { return }
                AppTelemetry.shared.event(
                    "finish_review_suggestion_changed",
                    screen: self.currentScreen,
                    fields: ["activity": activity.rawValue]
                )
            }
            .store(in: &cancellables)

        tracker.$sessionID
            .removeDuplicates()
            .sink { [weak self] sessionID in
                guard let self else { return }
                AppTelemetry.shared.event(
                    "session_id_changed",
                    screen: self.currentScreen,
                    fields: ["session_id": sessionID]
                )
            }
            .store(in: &cancellables)

        tracker.$lastSummary
            .compactMap { $0 }
            .sink { [weak self] summary in
                guard let self else { return }
                AppTelemetry.shared.event(
                    "summary_received",
                    screen: self.currentScreen,
                    fields: [
                        "session_id": summary.sessionID,
                        "activity": summary.activity,
                        "distance_m": summary.distanceMeters,
                        "duration_s": summary.duration,
                    ]
                )
            }
            .store(in: &cancellables)

        tracker.$historicalRepairStatus
            .removeDuplicates()
            .sink { [weak self, weak tracker] status in
                guard let self, let tracker else { return }
                AppTelemetry.shared.event(
                    "historical_repair_status_changed",
                    screen: self.currentScreen,
                    fields: [
                        "session_id": tracker.historicalRepairSessionID,
                        "status": status,
                    ]
                )
            }
            .store(in: &cancellables)
    }

    private func trackerFields(_ tracker: TrackerModel) -> [String: Any] {
        var fields: [String: Any] = [
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
        if let weather = tracker.currentWeather {
            fields["weather"] = String(describing: weather)
        }
        return fields
    }

    private func appendRecoveryFields(to fields: inout [String: Any]) {
        let recovery = HistoricalHealthKitRepairV4Coordinator.shared
        fields["recovery_status"] = recovery.statusBySession

        var audits: [String: Any] = [:]
        for (sessionID, audit) in recovery.auditBySession {
            audits[sessionID] = recoveryAuditFields(audit)
        }
        fields["recovery_audits"] = audits
    }

    private func recoveryAuditFields(
        _ audit: HistoricalHealthKitRepairV4Coordinator.Audit
    ) -> [String: Any] {
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
        ]
    }
}
