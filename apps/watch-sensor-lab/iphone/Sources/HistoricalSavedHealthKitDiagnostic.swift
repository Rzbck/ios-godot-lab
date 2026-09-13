import CoreLocation
import Foundation
import HealthKit

/// Read-only inspection of what HealthKit actually persisted for a Tracker session.
///
/// This probe must keep working even when the iPhone never received the terminal Watch
/// authority and therefore never wrote `summary.json`. The session id embedded by the Watch
/// in HealthKit metadata is enough to locate the real workout, its pause/resume events and its
/// route. It never writes or deletes HealthKit data.
@MainActor
struct HistoricalSavedHealthKitDiagnostic {
    private struct SavedRoute {
        let route: HKWorkoutRoute
        let locations: [CLLocation]
        let segmentIndex: Int?
        let segmentCount: Int?
    }

    func inspect(sessionID: String) async throws -> [String: Any] {
        let recovery = HistoricalHealthKitRepairV4Coordinator.shared

        var localSummaryPresent = false
        var localSummaryError: String?
        do {
            _ = try recovery.loadSummary(sessionID: sessionID)
            localSummaryPresent = true
        } catch {
            localSummaryError = error.localizedDescription
        }

        // Query by the exact session metadata written by the Watch. This deliberately does
        // not depend on the local Tracker summary: a lost terminal sync is precisely the case
        // in which that summary does not exist yet.
        let sessionPredicate = HKQuery.predicateForObjects(
            withMetadataKey: recovery.sessionKey,
            allowedValues: [sessionID]
        )
        let samples = try await recovery.querySamples(
            type: HKObjectType.workoutType(),
            predicate: sessionPredicate
        )
        let workouts = samples.compactMap { $0 as? HKWorkout }
            .sorted { $0.startDate < $1.startDate }
        let generated = workouts.filter { recovery.isGenerated($0, sessionID: sessionID) }
        let normal = workouts.filter { !recovery.isGenerated($0, sessionID: sessionID) }

        var result: [String: Any] = [
            "session_id": sessionID,
            "local_summary_present": localSummaryPresent,
            "local_summary_error": nullableString(localSummaryError),
            "matching_workout_count": workouts.count,
            "generated_workout_count": generated.count,
            "normal_workout_count": normal.count,
            "matching_workouts": workouts.map {
                workoutSnapshot($0, recovery: recovery)
            },
            "app_identity": appIdentitySnapshot(),
        ]

        // Prefer the normal workout written by the Watch. A generated historical repair is
        // only a fallback and must never hide the original workout when both exist.
        guard let workout = normal.last ?? generated.last else {
            result["workout"] = NSNull()
            result["workout_events"] = []
            result["pause_intervals"] = []
            result["routes"] = []
            result["route_boundaries"] = []
            result["saved_route_count"] = 0
            result["saved_location_count"] = 0
            result["saved_geometry_m"] = 0.0
            result["largest_route_boundary"] = NSNull()
            result["largest_internal_hop"] = NSNull()
            return result
        }

        result["workout"] = workoutSnapshot(workout, recovery: recovery)
        result["workout_events"] = (workout.workoutEvents ?? []).map(workoutEventSnapshot)
        result["pause_intervals"] = pauseIntervals(for: workout)

        let routes = try await recovery.routes(for: workout)
        var savedRoutes: [SavedRoute] = []
        savedRoutes.reserveCapacity(routes.count)
        for route in routes {
            let locations = try await recovery.loadLocations(for: route)
                .sorted { $0.timestamp < $1.timestamp }
            savedRoutes.append(
                SavedRoute(
                    route: route,
                    locations: locations,
                    segmentIndex: intMetadata(
                        route.metadata?["com.rzbck.watchsensorlab.route_segment_index"]
                    ),
                    segmentCount: intMetadata(
                        route.metadata?["com.rzbck.watchsensorlab.route_segment_count"]
                    )
                )
            )
        }

        savedRoutes.sort { lhs, rhs in
            let leftIndex = lhs.segmentIndex ?? Int.max
            let rightIndex = rhs.segmentIndex ?? Int.max
            if leftIndex != rightIndex { return leftIndex < rightIndex }
            let leftDate = lhs.locations.first?.timestamp ?? lhs.route.startDate
            let rightDate = rhs.locations.first?.timestamp ?? rhs.route.startDate
            return leftDate < rightDate
        }

        result["routes"] = savedRoutes.map(routeSnapshot)
        result["route_boundaries"] = boundarySnapshots(savedRoutes)
        result["saved_route_count"] = savedRoutes.count
        result["saved_location_count"] = savedRoutes.reduce(0) { $0 + $1.locations.count }
        result["saved_geometry_m"] = savedRoutes.reduce(0.0) {
            $0 + geometry($1.locations)
        }
        result["largest_route_boundary"] = largestBoundary(savedRoutes) ?? NSNull()
        result["largest_internal_hop"] = largestInternalHop(savedRoutes) ?? NSNull()
        return result
    }

    private func appIdentitySnapshot() -> [String: Any] {
        let bundle = Bundle.main
        let info = bundle.infoDictionary ?? [:]
        let iconName = info["CFBundleIconName"] as? String
        let iconFiles = info["CFBundleIconFiles"] as? [String]
        let icons = info["CFBundleIcons"] as? [String: Any]
        let primaryIcon = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        let primaryFiles = primaryIcon?["CFBundleIconFiles"] as? [String]
        let primaryName = primaryIcon?["CFBundleIconName"] as? String

        return [
            "bundle_identifier": bundle.bundleIdentifier ?? "unknown",
            "bundle_name": info["CFBundleName"] as? String ?? "unknown",
            "display_name": info["CFBundleDisplayName"] as? String ?? "unknown",
            "short_version": info["CFBundleShortVersionString"] as? String ?? "unknown",
            "build_version": info["CFBundleVersion"] as? String ?? "unknown",
            "icon_name": nullableString(iconName ?? primaryName),
            "icon_files": iconFiles ?? primaryFiles ?? [],
            "primary_icon_dictionary_present": primaryIcon != nil,
            "icons_dictionary_present": icons != nil,
        ]
    }

    private func workoutSnapshot(
        _ workout: HKWorkout,
        recovery: HistoricalHealthKitRepairV4Coordinator
    ) -> [String: Any] {
        let source = workout.sourceRevision
        let os = source.operatingSystemVersion
        let activity = ActivityKind(healthKitType: workout.workoutActivityType) ?? .other
        var snapshot: [String: Any] = [
            "uuid": workout.uuid.uuidString,
            "activity_raw": workout.workoutActivityType.rawValue,
            "activity": activity.rawValue,
            "start_timestamp": workout.startDate.timeIntervalSince1970,
            "end_timestamp": workout.endDate.timeIntervalSince1970,
            "start_iso": iso(workout.startDate),
            "end_iso": iso(workout.endDate),
            "wall_duration_s": workout.endDate.timeIntervalSince(workout.startDate),
            "duration_s": workout.duration,
            "source_name": source.source.name,
            "source_bundle": source.source.bundleIdentifier,
            "source_version": nullableString(source.version),
            "source_product_type": nullableString(source.productType),
            "source_os": "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            "source_matches_installed_bundle": source.source.bundleIdentifier == Bundle.main.bundleIdentifier,
            "managed": workout.metadata?[recovery.managedKey] as? Bool ?? false,
            "metadata_session_id": nullableString(workout.metadata?[recovery.sessionKey] as? String),
            "brand_name": nullableString(workout.metadata?[HKMetadataKeyWorkoutBrandName] as? String),
            "generation": nullableString(workout.metadata?[recovery.generationKey] as? String),
            "attempt_id": nullableString(workout.metadata?[recovery.attemptKey] as? String),
            "distance_m": nullableDouble(recovery.workoutDistanceMeters(workout, activity: activity)),
        ]

        if let device = workout.device {
            snapshot["device"] = [
                "name": nullableString(device.name),
                "manufacturer": nullableString(device.manufacturer),
                "model": nullableString(device.model),
                "hardware_version": nullableString(device.hardwareVersion),
                "firmware_version": nullableString(device.firmwareVersion),
                "software_version": nullableString(device.softwareVersion),
                "local_identifier": nullableString(device.localIdentifier),
                "udi_device_identifier": nullableString(device.udiDeviceIdentifier),
            ]
        } else {
            snapshot["device"] = NSNull()
        }
        return snapshot
    }

    private func workoutEventSnapshot(_ event: HKWorkoutEvent) -> [String: Any] {
        [
            "type": eventTypeName(event.type),
            "type_raw": event.type.rawValue,
            "start_timestamp": event.dateInterval.start.timeIntervalSince1970,
            "end_timestamp": event.dateInterval.end.timeIntervalSince1970,
            "start_iso": iso(event.dateInterval.start),
            "end_iso": iso(event.dateInterval.end),
            "duration_s": event.dateInterval.duration,
        ]
    }

    private func eventTypeName(_ type: HKWorkoutEventType) -> String {
        switch type {
        case .pause: return "pause"
        case .resume: return "resume"
        case .motionPaused: return "motion_paused"
        case .motionResumed: return "motion_resumed"
        case .pauseOrResumeRequest: return "pause_or_resume_request"
        case .lap: return "lap"
        case .segment: return "segment"
        case .marker: return "marker"
        @unknown default: return "unknown_\(type.rawValue)"
        }
    }

    private func pauseIntervals(for workout: HKWorkout) -> [[String: Any]] {
        let events = (workout.workoutEvents ?? []).sorted {
            $0.dateInterval.start < $1.dateInterval.start
        }
        var result: [[String: Any]] = []
        var openPause: (Date, String)?

        for event in events {
            switch event.type {
            case .pause, .motionPaused:
                if openPause == nil {
                    openPause = (event.dateInterval.start, eventTypeName(event.type))
                }
            case .resume, .motionResumed:
                guard let pause = openPause else { continue }
                let end = min(max(event.dateInterval.start, pause.0), workout.endDate)
                if end > pause.0 {
                    result.append(pauseSnapshot(start: pause.0, end: end, source: pause.1))
                }
                openPause = nil
            default:
                break
            }
        }

        if let pause = openPause, workout.endDate > pause.0 {
            result.append(
                pauseSnapshot(start: pause.0, end: workout.endDate, source: pause.1 + "_until_end")
            )
        }
        return result
    }

    private func pauseSnapshot(start: Date, end: Date, source: String) -> [String: Any] {
        [
            "start_timestamp": start.timeIntervalSince1970,
            "end_timestamp": end.timeIntervalSince1970,
            "start_iso": iso(start),
            "end_iso": iso(end),
            "duration_s": max(0, end.timeIntervalSince(start)),
            "source": source,
        ]
    }

    private func routeSnapshot(_ saved: SavedRoute) -> [String: Any] {
        let locations = saved.locations
        var snapshot: [String: Any] = [
            "uuid": saved.route.uuid.uuidString,
            "segment_index": nullableInt(saved.segmentIndex),
            "segment_count": nullableInt(saved.segmentCount),
            "point_count": locations.count,
            "geometry_m": geometry(locations),
            "route_source": nullableString(
                saved.route.metadata?["com.rzbck.watchsensorlab.route_source"] as? String
            ),
            "generation": nullableString(
                saved.route.metadata?["com.rzbck.watchsensorlab.historical_generation"] as? String
            ),
            "attempt_id": nullableString(
                saved.route.metadata?["com.rzbck.watchsensorlab.historical_attempt_id"] as? String
            ),
        ]

        snapshot["first"] = locations.first.map(locationSnapshot) ?? NSNull()
        snapshot["last"] = locations.last.map(locationSnapshot) ?? NSNull()
        snapshot["largest_internal_hop"] = maxHop(locations) ?? NSNull()
        return snapshot
    }

    private func boundarySnapshots(_ routes: [SavedRoute]) -> [[String: Any]] {
        guard routes.count >= 2 else { return [] }
        var result: [[String: Any]] = []
        for index in 1..<routes.count {
            let previous = routes[index - 1]
            let current = routes[index]
            guard let from = previous.locations.last,
                  let to = current.locations.first else {
                continue
            }
            result.append([
                "from_route_uuid": previous.route.uuid.uuidString,
                "to_route_uuid": current.route.uuid.uuidString,
                "from_segment_index": nullableInt(previous.segmentIndex),
                "to_segment_index": nullableInt(current.segmentIndex),
                "distance_m": to.distance(from: from),
                "time_gap_s": to.timestamp.timeIntervalSince(from.timestamp),
                "from": locationSnapshot(from),
                "to": locationSnapshot(to),
            ])
        }
        return result
    }

    private func largestBoundary(_ routes: [SavedRoute]) -> [String: Any]? {
        boundarySnapshots(routes).max {
            double($0["distance_m"]) < double($1["distance_m"])
        }
    }

    private func largestInternalHop(_ routes: [SavedRoute]) -> [String: Any]? {
        routes.compactMap { saved -> [String: Any]? in
            guard var hop = maxHop(saved.locations) else { return nil }
            hop["route_uuid"] = saved.route.uuid.uuidString
            hop["segment_index"] = nullableInt(saved.segmentIndex)
            return hop
        }.max {
            double($0["distance_m"]) < double($1["distance_m"])
        }
    }

    private func maxHop(_ locations: [CLLocation]) -> [String: Any]? {
        guard locations.count >= 2 else { return nil }
        var best: [String: Any]?
        var bestDistance = -Double.infinity
        for (from, to) in zip(locations, locations.dropFirst()) {
            let distance = to.distance(from: from)
            guard distance > bestDistance else { continue }
            bestDistance = distance
            let delta = to.timestamp.timeIntervalSince(from.timestamp)
            best = [
                "distance_m": distance,
                "time_gap_s": delta,
                "implied_speed_mps": nullableDouble(delta > 0 ? distance / delta : nil),
                "from": locationSnapshot(from),
                "to": locationSnapshot(to),
            ]
        }
        return best
    }

    private func geometry(_ locations: [CLLocation]) -> Double {
        zip(locations, locations.dropFirst()).reduce(0.0) {
            $0 + $1.1.distance(from: $1.0)
        }
    }

    private func locationSnapshot(_ location: CLLocation) -> [String: Any] {
        [
            "timestamp": location.timestamp.timeIntervalSince1970,
            "iso": iso(location.timestamp),
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "horizontal_accuracy_m": location.horizontalAccuracy,
            "speed_mps": location.speed,
        ]
    }

    private func intMetadata(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private func nullableString(_ value: String?) -> Any {
        guard let value else { return NSNull() }
        return value
    }

    private func nullableInt(_ value: Int?) -> Any {
        guard let value else { return NSNull() }
        return value
    }

    private func nullableDouble(_ value: Double?) -> Any {
        guard let value else { return NSNull() }
        return value
    }

    private func double(_ value: Any?) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return -Double.infinity
    }

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
