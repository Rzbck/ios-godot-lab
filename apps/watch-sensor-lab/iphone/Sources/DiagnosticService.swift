import Foundation
import Network

/// Read-only diagnostic API for local development.
///
/// The server is intentionally small and dependency-free. It accepts one newline-delimited
/// JSON request per TCP connection and returns one JSON response. Windows reaches the device
/// port through usbmux, so normal debugging does not require Wi-Fi, Bonjour, or screenshots.
///
/// V1 is strictly read-only: it can inspect live state, refresh the existing read-only
/// historical recovery audit, and read the app's bounded local telemetry. It cannot mutate
/// HealthKit or workout state.
final class DiagnosticService {
    static let shared = DiagnosticService()

    static let protocolName = "wsl_diag_v1"
    static let devicePort: UInt16 = 37991

    private let queue = DispatchQueue(
        label: "com.rzbck.watchsensorlab.diagnostic-api",
        qos: .utility
    )
    private var listener: NWListener?
    private weak var tracker: TrackerModel?

    private init() {}

    @MainActor
    func start(tracker: TrackerModel) {
        self.tracker = tracker
        guard listener == nil else { return }
        guard let port = NWEndpoint.Port(rawValue: Self.devicePort) else {
            AppTelemetry.shared.error(
                "diagnostic_api_invalid_port",
                fields: ["port": Self.devicePort]
            )
            return
        }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true

            let listener = try NWListener(using: parameters, on: port)
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    AppTelemetry.shared.event(
                        "diagnostic_api_ready",
                        fields: [
                            "port": Self.devicePort,
                            "protocol": Self.protocolName,
                            "read_only": true,
                        ]
                    )
                case .failed(let error):
                    AppTelemetry.shared.error(
                        "diagnostic_api_failed",
                        error: error,
                        fields: ["port": Self.devicePort]
                    )
                default:
                    break
                }
            }

            self.listener = listener
            listener.start(queue: queue)
        } catch {
            AppTelemetry.shared.error(
                "diagnostic_api_start_failed",
                error: error,
                fields: ["port": Self.devicePort]
            )
        }
    }

    @MainActor
    func stop() {
        guard let listener else { return }
        listener.cancel()
        self.listener = nil
        AppTelemetry.shared.event(
            "diagnostic_api_stopped",
            fields: ["port": Self.devicePort]
        )
    }

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                // The normal transport is usbmux. Reject ordinary Wi-Fi/cellular paths so
                // sensitive diagnostics are not exposed as a LAN service.
                if self.isDisallowedNetworkPath(connection.currentPath) {
                    AppTelemetry.shared.error(
                        "diagnostic_api_rejected_network_client",
                        fields: ["endpoint": String(describing: connection.endpoint)]
                    )
                    connection.cancel()
                    return
                }
                self.receiveRequest(on: connection, buffer: Data())
            case .failed(_), .cancelled:
                break
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func isDisallowedNetworkPath(_ path: NWPath?) -> Bool {
        guard let path else { return false }
        return path.usesInterfaceType(.wifi) || path.usesInterfaceType(.cellular)
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 4_096
        ) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }

            if let error {
                self.sendError(
                    "receive_failed: \(error.localizedDescription)",
                    command: nil,
                    on: connection
                )
                return
            }

            var next = buffer
            if let data { next.append(data) }

            if next.count > 64 * 1_024 {
                self.sendError("request_too_large", command: nil, on: connection)
                return
            }

            if let newline = next.firstIndex(of: 0x0A) {
                let requestData = Data(next[..<newline])
                self.handle(requestData, on: connection)
                return
            }

            if isComplete {
                guard !next.isEmpty else {
                    connection.cancel()
                    return
                }
                self.handle(next, on: connection)
                return
            }

            self.receiveRequest(on: connection, buffer: next)
        }
    }

    private func handle(_ data: Data, on connection: NWConnection) {
        guard let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            sendError("invalid_json", command: nil, on: connection)
            return
        }

        Task { @MainActor [weak self, weak connection] in
            guard let self, let connection else { return }
            let response = await self.response(for: request)
            self.send(response, on: connection)
        }
    }

    @MainActor
    private func response(for request: [String: Any]) async -> [String: Any] {
        if let requestedProtocol = request["protocol"] as? String,
           requestedProtocol != Self.protocolName {
            return envelope(
                ok: false,
                command: request["command"] as? String,
                error: "unsupported_protocol"
            )
        }

        let command = (request["command"] as? String ?? "status").lowercased()
        let requestedLimit = (request["limit"] as? NSNumber)?.intValue ?? 50
        let limit = min(200, max(1, requestedLimit))

        switch command {
        case "ping":
            return envelope(
                ok: true,
                command: command,
                data: [
                    "app": "WatchSensorLab",
                    "read_only": true,
                    "transport": "usbmux_tcp",
                    "device_port": Self.devicePort,
                    "capabilities": ["ping", "status", "recovery", "errors", "logs"],
                ]
            )

        case "status":
            guard let tracker else {
                return envelope(ok: false, command: command, error: "tracker_not_ready")
            }
            return envelope(ok: true, command: command, data: trackerSnapshot(tracker))

        case "recovery":
            guard let sessionID = request["session_id"] as? String,
                  !sessionID.isEmpty else {
                return envelope(ok: false, command: command, error: "session_id_required")
            }

            let recovery = HistoricalHealthKitRepairV4Coordinator.shared
            if let active = recovery.activeSessionID, active != sessionID {
                return envelope(
                    ok: false,
                    command: command,
                    error: "recovery_busy_with_\(active)"
                )
            }

            if recovery.activeSessionID == nil {
                // inspect(sessionID:) is the existing read-only HealthKit/raw audit.
                recovery.inspect(sessionID: sessionID)
            }

            let deadline = Date().addingTimeInterval(15)
            while recovery.activeSessionID == sessionID, Date() < deadline {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }

            var data = recoverySnapshot(sessionID: sessionID, recovery: recovery)
            data["timed_out"] = recovery.activeSessionID == sessionID
            return envelope(ok: true, command: command, data: data)

        case "errors":
            return envelope(
                ok: true,
                command: command,
                data: [
                    "records": recentTelemetry(limit: limit, kind: "error"),
                    "limit": limit,
                ]
            )

        case "logs":
            let kind = request["kind"] as? String
            return envelope(
                ok: true,
                command: command,
                data: [
                    "records": recentTelemetry(limit: limit, kind: kind),
                    "limit": limit,
                    "kind": kind.map { $0 as Any } ?? NSNull(),
                ]
            )

        default:
            return envelope(ok: false, command: command, error: "unknown_command")
        }
    }

    @MainActor
    private func trackerSnapshot(_ tracker: TrackerModel) -> [String: Any] {
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

    @MainActor
    private func recoverySnapshot(
        sessionID: String,
        recovery: HistoricalHealthKitRepairV4Coordinator
    ) -> [String: Any] {
        var data: [String: Any] = [
            "session_id": sessionID,
            "status": recovery.statusBySession[sessionID] ?? "not_inspected",
            "active": recovery.activeSessionID == sessionID,
            "internally_verified": recovery.internallyVerifiedSessions.contains(sessionID),
        ]

        if let audit = recovery.auditBySession[sessionID] {
            data["audit"] = [
                "summary_distance_m": audit.summaryDistanceMeters,
                "watch_raw_points": audit.watchRawPoints,
                "iphone_raw_points": audit.phoneRawPoints,
                "watch_filtered_points": audit.watchFilteredPoints,
                "iphone_filtered_points": audit.phoneFilteredPoints,
                "watch_geometry_m": audit.watchGeometryMeters,
                "iphone_geometry_m": audit.phoneGeometryMeters,
                "watch_raw_distance_m": audit.watchRawDistanceMeters.map { $0 as Any } ?? NSNull(),
                "iphone_raw_distance_m": audit.phoneRawDistanceMeters.map { $0 as Any } ?? NSNull(),
                "distance_reference": audit.distanceReferenceSource.map { $0 as Any } ?? NSNull(),
                "chosen_source": audit.chosenSource.map { $0 as Any } ?? NSNull(),
                "chosen_points": audit.chosenPoints,
                "selected_geometry_m": audit.selectedGeometryMeters,
                "active_gaps_over_3s": audit.activeGapsOver3Seconds,
                "max_active_gap_s": audit.maxActiveGapSeconds,
                "generated_workouts": audit.generatedWorkoutCount,
                "normal_workouts": audit.normalWorkoutCount,
                "distance_conflict": audit.distanceConflict,
                "route_geometry_conflict": audit.routeGeometryConflict,
                "route_continuity_conflict": audit.routeContinuityConflict,
                "severe_route_counter_conflict": audit.severeRouteCounterConflict,
                "generated_workout_activity_type_raw": audit.generatedWorkoutActivityTypeRawValue.map { $0 as Any } ?? NSNull(),
                "generated_target_activity": audit.generatedTargetActivity.map { $0 as Any } ?? NSNull(),
                "generated_workout_brand_name": audit.generatedWorkoutBrandName.map { $0 as Any } ?? NSNull(),
                "generated_effort_score": audit.generatedEffortScore.map { $0 as Any } ?? NSNull(),
                "generated_effort_sample_count": audit.generatedEffortSampleCount,
                "saved_perceived_effort": audit.savedPerceivedEffort.map { $0 as Any } ?? NSNull(),
                "can_reconstruct": audit.canReconstruct,
            ]
        }
        return data
    }

    private func recentTelemetry(limit: Int, kind: String?) -> [[String: Any]] {
        guard let directory = telemetryDirectoryURL(),
              let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        let ordered = files
            .filter { $0.pathExtension == "jsonl" }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                    ?? .distantPast
                return left > right
            }

        var records: [[String: Any]] = []
        for file in ordered {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for rawLine in text.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
                guard let data = String(rawLine).data(using: .utf8),
                      let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }
                if let kind, record["kind"] as? String != kind { continue }
                records.append(record)
                if records.count >= limit { return records }
            }
        }
        return records
    }

    private func telemetryDirectoryURL() -> URL? {
        guard let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        return root.appendingPathComponent("WatchSensorLabTelemetry", isDirectory: true)
    }

    private func envelope(
        ok: Bool,
        command: String?,
        data: Any? = nil,
        error: String? = nil
    ) -> [String: Any] {
        var response: [String: Any] = [
            "protocol": Self.protocolName,
            "ok": ok,
            "build_sha": BuildInfo.gitSHA,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "read_only": true,
        ]
        if let command { response["command"] = command }
        if let data { response["data"] = data }
        if let error { response["error"] = error }
        return response
    }

    private func sendError(_ error: String, command: String?, on connection: NWConnection) {
        send(envelope(ok: false, command: command, error: error), on: connection)
    }

    private func send(_ response: [String: Any], on connection: NWConnection) {
        guard JSONSerialization.isValidJSONObject(response),
              var data = try? JSONSerialization.data(
                withJSONObject: response,
                options: [.sortedKeys]
              ) else {
            connection.cancel()
            return
        }
        data.append(0x0A)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
