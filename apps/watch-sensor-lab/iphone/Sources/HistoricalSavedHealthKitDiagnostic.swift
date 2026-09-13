import CoreLocation
import Foundation
import HealthKit

/// Read-only inspection of what HealthKit actually persisted for a historical restore.
///
/// Raw-route diagnostics tell us what we intended to write. This probe answers the other
/// half of the incident: which HKWorkout/HKWorkoutRoute objects exist after the write, which
/// coordinates each route contains, and which connector Fitness could plausibly render
/// between route boundaries. It never writes or deletes HealthKit data.
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
        let summary = try recovery.loadSummary(sessionID: sessionID)
        let workouts = try await recovery.managedWorkouts(sessionID: sessionID, summary: summary)
        let generated = workouts.filter { recovery.isGenerated($0, sessionID: sessionID) }
        let normal = workouts.filter { !recovery.isGenerated($0, sessionID: sessionID) }

        var result: [String: Any] = [
            "session_id": sessionID,
            "generated_workout_count": generated.count,
            "normal_workout_count": normal.count,
            "app_identity": appIdentitySnapshot(),
        ]

        guard let workout = generated.first else {
            result["workout"] = NSNull()
            result["routes"] = []
            result["route_boundaries"] = []
            return result
        }

        result["workout"] = workoutSnapshot(workout, recovery: recovery)

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

        if let largestBoundary = largestBoundary(savedRoutes) {
            result["largest_route_boundary"] = largestBoundary
        } else {
            result["largest_route_boundary"] = NSNull()
        }

        if let largestInternal = largestInternalHop(savedRoutes) {
            result["largest_internal_hop"] = largestInternal
        } else {
            result["largest_internal_hop"] = NSNull()
        }

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
            "icon_name": iconName ?? primaryName ?? NSNull(),
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
            "start_iso": iso(workout.startDate),
            "end_iso": iso(workout.endDate),
            "duration_s": workout.duration,
            "source_name": source.source.name,
            "source_bundle": source.source.bundleIdentifier,
            "source_version": source.version ?? NSNull(),
            "source_product_type": source.productType ?? NSNull(),
            "source_os": "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            "source_matches_installed_bundle": source.source.bundleIdentifier == Bundle.main.bundleIdentifier,
            "brand_name": workout.metadata?[HKMetadataKeyWorkoutBrandName] as? String ?? NSNull(),
            "generation": workout.metadata?[recovery.generationKey] as? String ?? NSNull(),
            "attempt_id": workout.metadata?[recovery.attemptKey] as? String ?? NSNull(),
            "distance_m": recovery.workoutDistanceMeters(workout, activity: activity) ?? NSNull(),
        ]

        if let device = workout.device {
            snapshot["device"] = [
                "name": device.name ?? NSNull(),
                "manufacturer": device.manufacturer ?? NSNull(),
                "model": device.model ?? NSNull(),
                "hardware_version": device.hardwareVersion ?? NSNull(),
                "firmware_version": device.firmwareVersion ?? NSNull(),
                "software_version": device.softwareVersion ?? NSNull(),
                "local_identifier": device.localIdentifier ?? NSNull(),
                "udi_device_identifier": device.udiDeviceIdentifier ?? NSNull(),
            ]
        } else {
            snapshot["device"] = NSNull()
        }
        return snapshot
    }

    private func routeSnapshot(_ saved: SavedRoute) -> [String: Any] {
        let locations = saved.locations
        var snapshot: [String: Any] = [
            "uuid": saved.route.uuid.uuidString,
            "segment_index": saved.segmentIndex ?? NSNull(),
            "segment_count": saved.segmentCount ?? NSNull(),
            "point_count": locations.count,
            "geometry_m": geometry(locations),
            "route_source": saved.route.metadata?["com.rzbck.watchsensorlab.route_source"] as? String ?? NSNull(),
            "generation": saved.route.metadata?["com.rzbck.watchsensorlab.historical_generation"] as? String ?? NSNull(),
            "attempt_id": saved.route.metadata?["com.rzbck.watchsensorlab.historical_attempt_id"] as? String ?? NSNull(),
        ]

        if let first = locations.first {
            snapshot["first"] = locationSnapshot(first)
        } else {
            snapshot["first"] = NSNull()
        }
        if let last = locations.last {
            snapshot["last"] = locationSnapshot(last)
        } else {
            snapshot["last"] = NSNull()
        }
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
                "from_segment_index": previous.segmentIndex ?? NSNull(),
                "to_segment_index": current.segmentIndex ?? NSNull(),
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
            hop["segment_index"] = saved.segmentIndex ?? NSNull()
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
                "implied_speed_mps": delta > 0 ? distance / delta : NSNull(),
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

    private func double(_ value: Any?) -> Double {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return -Double.infinity
    }

    private func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
