import CoreLocation
import Foundation
import HealthKit
import SwiftUI

/// Historical reconstruction v4.
///
/// Product rules:
/// - live workouts remain Watch-owned;
/// - historical recovery is iPhone-only;
/// - no new recovery is created while an older generated recovery exists;
/// - cleanup is explicit and only targets Tracker raw-restoration objects for
///   the exact session ID;
/// - Watch and iPhone GPS are audited independently before choosing a route;
/// - raw Tracker files are never modified or deleted here.
@MainActor
final class HistoricalHealthKitRepairV4Coordinator: ObservableObject {
    static let shared = HistoricalHealthKitRepairV4Coordinator()

    struct RouteAudit: Equatable {
        let summaryDistanceMeters: Double
        let watchPointCount: Int
        let phonePointCount: Int
        let watchSanitizedCount: Int
        let phoneSanitizedCount: Int
        let watchGeometryMeters: Double
        let phoneGeometryMeters: Double
        let watchRawDistanceMeters: Double?
        let phoneRawDistanceMeters: Double?
        let chosenSource: String?
        let chosenPointCount: Int
        let chosenGeometryMeters: Double
        let activeGapCountOver3Seconds: Int
        let maxActiveGapSeconds: Double
        let generatedWorkoutCount: Int
        let normalWorkoutCount: Int

        var canReconstruct: Bool {
            generatedWorkoutCount == 0
                && normalWorkoutCount == 0
                && chosenPointCount >= 2
        }
    }

    @Published private(set) var activeSessionID: String?
    @Published private(set) var statusBySession: [String: String] = [:]
    @Published private(set) var auditBySession: [String: RouteAudit] = [:]
    @Published private(set) var internallyVerifiedSessions: Set<String> = []

    private let healthStore = HKHealthStore()
    private let packetBuilder = TrackerHealthRestorePacketBuilder()

    private let managedKey = "com.rzbck.watchsensorlab.managed"
    private let sessionKey = "com.rzbck.watchsensorlab.session_id"
    private let rawRestoreKey = "com.rzbck.watchsensorlab.raw_restoration"
    private let rawRestoreSchemaKey = "com.rzbck.watchsensorlab.raw_restoration_schema"
    private let rawRestoreSourceKey = "com.rzbck.watchsensorlab.raw_restoration_source"
    private let correctionTargetKey = "com.rzbck.watchsensorlab.correction_target_activity"
    private let masterActivityKey = "com.rzbck.watchsensorlab.master_activity"
    private let algorithmKey = "com.rzbck.watchsensorlab.algorithm_version"
    private let buildKey = "com.rzbck.watchsensorlab.build_sha"
    private let generationKey = "com.rzbck.watchsensorlab.historical_generation"
    private let attemptKey = "com.rzbck.watchsensorlab.historical_attempt_id"

    private let generation = "ios_historical_v4_clean_route"
    private let source = "tracker_raw_ios_v4_clean_route"

    private init() {}

    func inspect(sessionID: String) {
        guard activeSessionID == nil else { return }
        activeSessionID = sessionID
        statusBySession[sessionID] = "Diagnostic raw Watch + iPhone…"

        Task {
            defer { activeSessionID = nil }
            do {
                let summary = try loadSummary(sessionID: sessionID)
                let route = try loadRouteCandidates(summary: summary)
                let workouts = try await managedWorkouts(sessionID: sessionID, summary: summary)
                let generated = workouts.filter { ($0.metadata?[rawRestoreKey] as? Bool) == true }
                let normal = workouts.filter { ($0.metadata?[rawRestoreKey] as? Bool) != true }
                let chosen = chooseRoute(from: route, activity: ActivityKind(rawValue: summary.activity) ?? .other)

                auditBySession[sessionID] = RouteAudit(
                    summaryDistanceMeters: summary.distanceMeters,
                    watchPointCount: route.watch.count,
                    phonePointCount: route.phone.count,
                    watchSanitizedCount: chosen.watch.points.count,
                    phoneSanitizedCount: chosen.phone.points.count,
                    watchGeometryMeters: chosen.watch.geometryMeters,
                    phoneGeometryMeters: chosen.phone.geometryMeters,
                    watchRawDistanceMeters: route.watchRawDistanceMeters,
                    phoneRawDistanceMeters: route.phoneRawDistanceMeters,
                    chosenSource: chosen.selected?.source,
                    chosenPointCount: chosen.selected?.points.count ?? 0,
                    chosenGeometryMeters: chosen.selected?.geometryMeters ?? 0,
                    activeGapCountOver3Seconds: chosen.selected?.activeGapCountOver3Seconds ?? 0,
                    maxActiveGapSeconds: chosen.selected?.maxActiveGapSeconds ?? 0,
                    generatedWorkoutCount: generated.count,
                    normalWorkoutCount: normal.count
                )

                if !normal.isEmpty {
                    statusBySession[sessionID] =
                        "Workout Tracker normal détecté · reconstruction historique bloquée."
                } else if !generated.isEmpty {
                    statusBySession[sessionID] =
                        "\(generated.count) restauration(s) de test détectée(s) · nettoyage requis avant tout nouvel essai."
                } else if let selected = chosen.selected {
                    statusBySession[sessionID] =
                        "Diagnostic prêt · route \(selected.source) retenue, \(selected.points.count) points filtrés, aucune écriture Santé."
                } else {
                    statusBySession[sessionID] =
                        "Diagnostic incomplet · aucune route GPS sûre."
                }
            } catch {
                statusBySession[sessionID] = "Diagnostic échoué · \(error.localizedDescription)"
            }
        }
    }

    func cleanupGeneratedRestorations(sessionID: String) {
        guard activeSessionID == nil else {
            statusBySession[sessionID] = "Une opération Santé est déjà en cours."
            return
        }
        activeSessionID = sessionID
        internallyVerifiedSessions.remove(sessionID)
        statusBySession[sessionID] = "Inspection des restaurations de test…"

        Task {
            defer { activeSessionID = nil }
            do {
                let summary = try loadSummary(sessionID: sessionID)
                try await requestCleanupAuthorization()

                let workouts = try await managedWorkouts(sessionID: sessionID, summary: summary)
                let generated = workouts.filter {
                    ($0.metadata?[rawRestoreKey] as? Bool) == true
                        && ($0.metadata?[sessionKey] as? String) == sessionID
                }
                let normal = workouts.filter { ($0.metadata?[rawRestoreKey] as? Bool) != true }
                guard normal.isEmpty else {
                    throw RepairV4Error.operation(
                        "un workout Tracker normal existe ; nettoyage historique annulé"
                    )
                }

                guard !generated.isEmpty else {
                    statusBySession[sessionID] = "Aucune restauration de test à nettoyer."
                    inspect(sessionID: sessionID)
                    return
                }

                var objects: [HKObject] = []
                for workout in generated {
                    objects.append(contentsOf: try await routes(for: workout))
                    if #available(iOS 18.0, *) {
                        objects.append(contentsOf: try await effortSamples(for: workout))
                    }
                }
                objects.append(contentsOf: try await generatedQuantitySamples(
                    sessionID: sessionID,
                    summary: summary
                ))
                objects.append(contentsOf: generated)

                let unique = Array(
                    Dictionary(grouping: objects, by: \.uuid)
                        .values
                        .compactMap(\.first)
                )
                try await delete(unique)

                let remaining = try await managedWorkouts(sessionID: sessionID, summary: summary)
                    .filter { ($0.metadata?[rawRestoreKey] as? Bool) == true }
                guard remaining.isEmpty else {
                    throw RepairV4Error.operation(
                        "\(remaining.count) restauration(s) Tracker restent dans HealthKit après nettoyage"
                    )
                }

                statusBySession[sessionID] =
                    "Nettoyage vérifié · aucune restauration de test restante. Raw Tracker intacts."
                auditBySession.removeValue(forKey: sessionID)
                inspect(sessionID: sessionID)
            } catch {
                statusBySession[sessionID] = "Nettoyage échoué · \(error.localizedDescription)"
            }
        }
    }

    func repair(
        sessionID: String,
        targetActivity: ActivityKind,
        perceivedEffort: Int?
    ) {
        guard activeSessionID == nil else {
            statusBySession[sessionID] = "Une opération Santé est déjà en cours."
            return
        }
        guard !sessionID.isEmpty, !targetActivity.isAutomatic else {
            statusBySession[sessionID] = "Demande de reconstruction invalide."
            return
        }

        activeSessionID = sessionID
        internallyVerifiedSessions.remove(sessionID)
        statusBySession[sessionID] = "Préflight v4 Watch + iPhone…"

        Task {
            defer { activeSessionID = nil }
            do {
                let summary = try loadSummary(sessionID: sessionID)
                let payload = try makePayload(sessionID: sessionID, targetActivity: targetActivity)
                let routeCandidates = try loadRouteCandidates(summary: summary)
                let routeChoice = chooseRoute(from: routeCandidates, activity: targetActivity)
                guard let selectedRoute = routeChoice.selected,
                      selectedRoute.points.count >= 2 else {
                    throw RepairV4Error.operation("aucune route GPS sûre après filtrage")
                }

                statusBySession[sessionID] = "Autorisation d’écriture Santé v4…"
                try await requestRepairAuthorization(
                    activity: targetActivity,
                    hasEnergy: (payload.activeEnergyKcal ?? 0) > 0,
                    hasSpeed: !selectedRoute.points.isEmpty,
                    perceivedEffort: perceivedEffort
                )

                let existing = try await managedWorkouts(sessionID: sessionID, summary: summary)
                let generated = existing.filter { ($0.metadata?[rawRestoreKey] as? Bool) == true }
                let normal = existing.filter { ($0.metadata?[rawRestoreKey] as? Bool) != true }
                guard normal.isEmpty else {
                    throw RepairV4Error.operation(
                        "un workout Tracker normal existe déjà ; aucune écriture effectuée"
                    )
                }
                guard generated.isEmpty else {
                    throw RepairV4Error.operation(
                        "\(generated.count) ancienne(s) restauration(s) existent encore ; nettoie-les avant de reconstruire"
                    )
                }

                let attemptID = UUID().uuidString
                let created = try await createHistoricalWorkout(
                    payload: payload,
                    summary: summary,
                    activity: targetActivity,
                    route: selectedRoute,
                    attemptID: attemptID,
                    perceivedEffort: perceivedEffort
                )

                statusBySession[sessionID] = "Relectures HealthKit v4…"
                try await verifyDurably(
                    payload: payload,
                    summary: summary,
                    activity: targetActivity,
                    route: selectedRoute,
                    workoutUUID: created.workout.uuid,
                    routeUUID: created.route?.uuid,
                    attemptID: attemptID,
                    perceivedEffort: perceivedEffort
                )

                internallyVerifiedSessions.insert(sessionID)
                statusBySession[sessionID] =
                    "HealthKit v4 écrit et relu · UNE seule restauration présente · PAS encore validé dans Santé/Forme."
                auditBySession.removeValue(forKey: sessionID)
            } catch {
                statusBySession[sessionID] = "Reconstruction v4 échouée · \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Raw route audit

    private struct RawPoint: Equatable {
        let timestamp: TimeInterval
        let latitude: Double
        let longitude: Double
        let altitude: Double
        let horizontalAccuracy: Double
        let verticalAccuracy: Double
        let nativeSpeed: Double?
        let source: String
    }

    private struct RawRoutes {
        let watch: [RawPoint]
        let phone: [RawPoint]
        let pauses: [TrackerHealthRestorePause]
        let watchRawDistanceMeters: Double?
        let phoneRawDistanceMeters: Double?
    }

    private struct SanitizedRoute {
        let source: String
        let points: [RawPoint]
        let geometryMeters: Double
        let activeGapCountOver3Seconds: Int
        let maxActiveGapSeconds: Double
        let p90AccuracyMeters: Double
        let firstOffsetSeconds: Double
        let lastOffsetSeconds: Double
    }

    private struct RouteChoice {
        let watch: SanitizedRoute
        let phone: SanitizedRoute
        let selected: SanitizedRoute?
    }

    private func loadRouteCandidates(summary: TrackerSummary) throws -> RawRoutes {
        let directory = try sessionDirectory(sessionID: summary.sessionID)
        var rows: [[String: Any]] = []
        rows.append(contentsOf: try loadJSONL(directory.appendingPathComponent("samples.jsonl")))
        let reliable = directory.appendingPathComponent("watch_reliable.jsonl")
        if FileManager.default.fileExists(atPath: reliable.path) {
            rows.append(contentsOf: try loadJSONL(reliable))
        }

        let start = summary.startedAt.timeIntervalSince1970
        let end = summary.endedAt.timeIntervalSince1970
        var watch: [RawPoint] = []
        var phone: [RawPoint] = []
        var watchDistances: [(TimeInterval, Double)] = []
        var phoneDistances: [(TimeInterval, Double)] = []
        var explicitMarks: [(TimeInterval, Bool)] = []
        var phaseMarks: [(TimeInterval, String, String)] = []

        for row in rows {
            guard let timestamp = number(row["timestamp"]), timestamp >= start, timestamp <= end else {
                continue
            }
            let record = row["record"] as? String ?? ""
            let sourceName = row["source"] as? String ?? ""
            let payload = row["payload"] as? [String: Any] ?? [:]
            let quality = row["quality"] as? [String: Any] ?? [:]

            if record == "sample" {
                let kind = row["kind"] as? String ?? ""
                if kind == "watch_location",
                   let point = rawPoint(
                        timestamp: timestamp,
                        source: "WATCH",
                        payload: payload,
                        quality: payload,
                        horizontalKey: "horizontal_accuracy_m",
                        verticalKey: "vertical_accuracy_m",
                        nativeSpeedKey: "native_speed_mps"
                   ) {
                    watch.append(point)
                    if let distance = number(payload["distance_m"]), distance >= 0 {
                        watchDistances.append((timestamp, distance))
                    }
                    continue
                }
                if kind == "location",
                   let point = rawPoint(
                        timestamp: timestamp,
                        source: "IPHONE",
                        payload: payload,
                        quality: quality,
                        horizontalKey: "horizontal_accuracy_m",
                        verticalKey: "vertical_accuracy_m",
                        nativeSpeedKey: "native_speed_mps"
                   ) {
                    phone.append(point)
                    if let distance = number(payload["distance_m"]), distance >= 0 {
                        phoneDistances.append((timestamp, distance))
                    }
                    continue
                }
            }

            guard record == "event", sourceName == "watch" else { continue }
            let event = row["event"] as? String ?? ""
            switch event {
            case "manual_pause", "auto_pause":
                explicitMarks.append((timestamp, true))
            case "manual_resume", "auto_resume":
                explicitMarks.append((timestamp, false))
            case "phase_changed":
                if let from = payload["from"] as? String,
                   let to = payload["to"] as? String {
                    phaseMarks.append((timestamp, from, to))
                }
            default:
                break
            }
        }

        let pauses = makePauses(
            explicit: explicitMarks,
            fallback: phaseMarks,
            start: start,
            end: end
        )

        return RawRoutes(
            watch: deduplicate(points: watch),
            phone: deduplicate(points: phone),
            pauses: pauses,
            watchRawDistanceMeters: watchDistances.sorted(by: { $0.0 < $1.0 }).last?.1,
            phoneRawDistanceMeters: phoneDistances.sorted(by: { $0.0 < $1.0 }).last?.1
        )
    }

    private func rawPoint(
        timestamp: TimeInterval,
        source: String,
        payload: [String: Any],
        quality: [String: Any],
        horizontalKey: String,
        verticalKey: String,
        nativeSpeedKey: String
    ) -> RawPoint? {
        guard let latitude = number(payload["latitude"]),
              let longitude = number(payload["longitude"]),
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else {
            return nil
        }
        guard let horizontal = number(quality[horizontalKey]),
              horizontal >= 0,
              horizontal <= 50 else {
            return nil
        }
        let vertical = number(quality[verticalKey]) ?? -1
        let speed = number(quality[nativeSpeedKey]) ?? number(payload["speed_mps"])
        return RawPoint(
            timestamp: timestamp,
            latitude: latitude,
            longitude: longitude,
            altitude: number(payload["altitude_m"]) ?? 0,
            horizontalAccuracy: horizontal,
            verticalAccuracy: vertical,
            nativeSpeed: speed,
            source: source
        )
    }

    private func chooseRoute(from raw: RawRoutes, activity: ActivityKind) -> RouteChoice {
        let watch = sanitize(
            source: "WATCH",
            points: raw.watch,
            pauses: raw.pauses,
            activity: activity
        )
        let phone = sanitize(
            source: "IPHONE",
            points: raw.phone,
            pauses: raw.pauses,
            activity: activity
        )

        let usable = [watch, phone].filter { $0.points.count >= 2 }
        let selected = usable.min { lhs, rhs in
            routeScore(lhs) < routeScore(rhs)
        }
        return RouteChoice(watch: watch, phone: phone, selected: selected)
    }

    private func sanitize(
        source: String,
        points: [RawPoint],
        pauses: [TrackerHealthRestorePause],
        activity: ActivityKind
    ) -> SanitizedRoute {
        let speedLimit = maximumPlausibleSpeed(activity: activity)
        var values = deduplicate(points: points)
            .filter { !isPaused($0.timestamp, pauses: pauses) }

        // Remove isolated spikes only when both adjacent legs are implausible
        // while the direct bridge is plausible. No coordinate is invented.
        var changed = true
        while changed, values.count >= 3 {
            changed = false
            var filtered: [RawPoint] = [values[0]]
            var index = 1
            while index < values.count - 1 {
                let previous = filtered.last ?? values[index - 1]
                let current = values[index]
                let next = values[index + 1]
                let before = impliedSpeed(previous, current)
                let after = impliedSpeed(current, next)
                let bridge = impliedSpeed(previous, next)
                if before > speedLimit,
                   after > speedLimit,
                   bridge <= speedLimit {
                    changed = true
                } else {
                    filtered.append(current)
                }
                index += 1
            }
            if let last = values.last { filtered.append(last) }
            values = filtered
        }

        // Drop any remaining point that requires an impossible jump from the
        // last accepted point. Long gaps are allowed when the implied speed is
        // plausible; we never interpolate missing coordinates.
        var accepted: [RawPoint] = []
        for point in values {
            guard let last = accepted.last else {
                accepted.append(point)
                continue
            }
            let speed = impliedSpeed(last, point)
            if speed <= speedLimit || point.timestamp - last.timestamp > 120 {
                accepted.append(point)
            }
        }

        let geometry = zip(accepted, accepted.dropFirst())
            .reduce(0.0) { partial, pair in partial + distance(pair.0, pair.1) }
        let activeGaps = zip(accepted, accepted.dropFirst())
            .map { $1.timestamp - $0.timestamp }
            .filter { $0 > 0 && $0 < 120 }
        let accuracies = accepted.map(\.horizontalAccuracy).sorted()
        let p90Index = accuracies.isEmpty ? 0 : Int(Double(accuracies.count - 1) * 0.90)

        return SanitizedRoute(
            source: source,
            points: accepted,
            geometryMeters: geometry,
            activeGapCountOver3Seconds: activeGaps.filter { $0 > 3 }.count,
            maxActiveGapSeconds: activeGaps.max() ?? 0,
            p90AccuracyMeters: accuracies.isEmpty ? 999 : accuracies[p90Index],
            firstOffsetSeconds: accepted.first.map { max(0, $0.timestamp - (points.first?.timestamp ?? $0.timestamp)) } ?? 999,
            lastOffsetSeconds: accepted.last.map { max(0, (points.last?.timestamp ?? $0.timestamp) - $0.timestamp) } ?? 999
        )
    }

    private func routeScore(_ route: SanitizedRoute) -> Double {
        Double(route.activeGapCountOver3Seconds) * 25
            + route.maxActiveGapSeconds * 2
            + route.p90AccuracyMeters
            + (route.points.count < 100 ? 500 : 0)
    }

    private func maximumPlausibleSpeed(activity: ActivityKind) -> Double {
        switch activity {
        case .walking, .hiking: return 5.0
        case .running, .trackAndField: return 12.0
        case .cycling, .handCycling: return 25.0
        default: return 20.0
        }
    }

    private func impliedSpeed(_ a: RawPoint, _ b: RawPoint) -> Double {
        let dt = b.timestamp - a.timestamp
        guard dt > 0 else { return .infinity }
        return distance(a, b) / dt
    }

    private func distance(_ a: RawPoint, _ b: RawPoint) -> Double {
        let radius = 6_371_000.0
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * radius * asin(min(1, sqrt(h)))
    }

    private func isPaused(_ timestamp: TimeInterval, pauses: [TrackerHealthRestorePause]) -> Bool {
        pauses.contains { timestamp >= $0.startedAt && timestamp <= $0.endedAt }
    }

    private func deduplicate(points: [RawPoint]) -> [RawPoint] {
        var seen = Set<String>()
        return points.sorted { $0.timestamp < $1.timestamp }.filter { point in
            let key = String(format: "%.3f|%.6f|%.6f", point.timestamp, point.latitude, point.longitude)
            return seen.insert(key).inserted
        }
    }

    private func makePauses(
        explicit: [(TimeInterval, Bool)],
        fallback: [(TimeInterval, String, String)],
        start: TimeInterval,
        end: TimeInterval
    ) -> [TrackerHealthRestorePause] {
        var marks = explicit.sorted { $0.0 < $1.0 }
        if !marks.contains(where: { $0.1 }) {
            marks = fallback.sorted { $0.0 < $1.0 }.compactMap { item in
                if item.1 == "active", item.2 == "paused" { return (item.0, true) }
                if item.1 == "paused", item.2 == "active" { return (item.0, false) }
                if item.1 == "paused", item.2 == "ended" { return (min(item.0, end), false) }
                return nil
            }
        }

        var result: [TrackerHealthRestorePause] = []
        var opened: TimeInterval?
        for (rawTimestamp, pause) in marks {
            let timestamp = min(max(rawTimestamp, start), end)
            if pause {
                if opened == nil { opened = timestamp }
            } else if let opened, timestamp > opened {
                result.append(TrackerHealthRestorePause(startedAt: opened, endedAt: timestamp))
                selfOpenedReset(&opened)
            }
        }
        if let opened, end > opened {
            result.append(TrackerHealthRestorePause(startedAt: opened, endedAt: end))
        }
        return result
    }

    private func selfOpenedReset(_ value: inout TimeInterval?) {
        value = nil
    }

    // MARK: - HealthKit write path

    private struct CreatedWorkout {
        let workout: HKWorkout
        let route: HKWorkoutRoute?
        let effort: HKQuantitySample?
    }

    private func createHistoricalWorkout(
        payload: TrackerHealthRestorePayload,
        summary: TrackerSummary,
        activity: ActivityKind,
        route: SanitizedRoute,
        attemptID: String,
        perceivedEffort: Int?
    ) async throws -> CreatedWorkout {
        let startDate = Date(timeIntervalSince1970: payload.startedAt)
        let endDate = Date(timeIntervalSince1970: payload.endedAt)
        guard endDate > startDate, payload.activeDuration > 0, payload.distanceMeters > 0 else {
            throw RepairV4Error.operation("données temporelles Tracker invalides")
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activity.healthKitType
        configuration.locationType = .outdoor
        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: configuration, device: nil)

        let sampleMetadata = generatedMetadata(sessionID: payload.sessionID, attemptID: attemptID)
        let samples = try makeSamples(
            payload: payload,
            activity: activity,
            route: route,
            metadata: sampleMetadata
        )
        let events = makeEvents(payload: payload, attemptID: attemptID)

        var createdWorkout: HKWorkout?
        var createdRoute: HKWorkoutRoute?
        var createdEffort: HKQuantitySample?

        do {
            try await begin(builder, at: startDate)
            var metadata: [String: Any] = [
                managedKey: true,
                sessionKey: payload.sessionID,
                rawRestoreKey: true,
                rawRestoreSchemaKey: payload.schema,
                rawRestoreSourceKey: source,
                correctionTargetKey: activity.rawValue,
                masterActivityKey: activity.rawValue,
                algorithmKey: payload.sourceAlgorithmVersion ?? "tracker-raw-ios-v4",
                buildKey: BuildInfo.gitSHA,
                generationKey: generation,
                attemptKey: attemptID,
                "com.rzbck.watchsensorlab.route_source": route.source,
                "com.rzbck.watchsensorlab.route_filtered_point_count": route.points.count,
                "com.rzbck.watchsensorlab.route_geometry_m": route.geometryMeters,
                "com.rzbck.watchsensorlab.route_active_gaps_gt3": route.activeGapCountOver3Seconds,
            ]
            for (key, value) in HistoricalHealthKitFullFidelity.workoutMetadata(
                summary: summary,
                payload: payload,
                activity: activity,
                attemptID: attemptID
            ) {
                metadata[key] = value
            }
            metadata[HKMetadataKeyIndoorWorkout] = false
            try await addMetadata(metadata, to: builder)
            try await add(samples, to: builder)
            if !events.isEmpty { try await add(events, to: builder) }
            try await end(builder, at: endDate)
            guard let workout = try await finish(builder) else {
                throw RepairV4Error.operation("HealthKit n’a pas retourné le workout v4")
            }
            createdWorkout = workout

            let locations = route.points.map { point in
                CLLocation(
                    coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude),
                    altitude: point.altitude,
                    horizontalAccuracy: point.horizontalAccuracy,
                    verticalAccuracy: point.verticalAccuracy,
                    course: -1,
                    speed: point.nativeSpeed.map { ($0 >= 0 && $0 < 100) ? $0 : -1 } ?? -1,
                    timestamp: Date(timeIntervalSince1970: point.timestamp)
                )
            }
            createdRoute = try await finishIndependentRoute(
                workout: workout,
                locations: locations,
                metadata: routeMetadata(
                    sessionID: payload.sessionID,
                    schema: payload.schema,
                    attemptID: attemptID,
                    sourceName: route.source
                )
            )

            createdEffort = try await savePerceivedEffort(
                workout: workout,
                perceivedEffort: perceivedEffort,
                metadata: sampleMetadata
            )

            return CreatedWorkout(workout: workout, route: createdRoute, effort: createdEffort)
        } catch {
            var rollback: [HKObject] = []
            if let createdEffort { rollback.append(createdEffort) }
            if let createdRoute { rollback.append(createdRoute) }
            if let createdWorkout {
                rollback.append(contentsOf: (try? await routes(for: createdWorkout)) ?? [])
                if #available(iOS 18.0, *) {
                    rollback.append(contentsOf: (try? await effortSamples(for: createdWorkout)) ?? [])
                }
                rollback.append(createdWorkout)
            }
            rollback.append(contentsOf: (try? await generatedQuantitySamples(
                sessionID: payload.sessionID,
                summary: summary,
                attemptID: attemptID
            )) ?? [])
            if !rollback.isEmpty {
                try? await delete(Array(Dictionary(grouping: rollback, by: \.uuid).values.compactMap(\.first)))
            }
            throw error
        }
    }

    private func makeSamples(
        payload: TrackerHealthRestorePayload,
        activity: ActivityKind,
        route: SanitizedRoute,
        metadata: [String: Any]
    ) throws -> [HKSample] {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            throw RepairV4Error.operation("type HealthKit fréquence cardiaque indisponible")
        }
        var samples: [HKSample] = payload.heartRates.compactMap { point in
            guard point.bpm > 0, point.bpm < 260,
                  point.timestamp >= payload.startedAt, point.timestamp <= payload.endedAt else { return nil }
            let date = Date(timeIntervalSince1970: point.timestamp)
            return HKQuantitySample(
                type: heartRateType,
                quantity: HKQuantity(unit: HKUnit(from: "count/min"), doubleValue: point.bpm),
                start: date,
                end: date,
                metadata: metadata
            )
        }

        let start = Date(timeIntervalSince1970: payload.startedAt)
        let end = Date(timeIntervalSince1970: payload.endedAt)
        if let energy = payload.activeEnergyKcal, energy > 0,
           let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            samples.append(HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: energy),
                start: start,
                end: end,
                metadata: metadata
            ))
        }
        if let identifier = distanceIdentifier(for: activity), payload.distanceMeters > 0,
           let type = HKQuantityType.quantityType(forIdentifier: identifier) {
            samples.append(HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: .meter(), doubleValue: payload.distanceMeters),
                start: start,
                end: end,
                metadata: metadata
            ))
        }
        if let speedIdentifier = speedIdentifier(for: activity),
           let speedType = HKQuantityType.quantityType(forIdentifier: speedIdentifier) {
            let unit = HKUnit.meter().unitDivided(by: .second())
            for point in route.points {
                guard let speed = point.nativeSpeed, speed >= 0, speed < 100 else { continue }
                let date = Date(timeIntervalSince1970: point.timestamp)
                samples.append(HKQuantitySample(
                    type: speedType,
                    quantity: HKQuantity(unit: unit, doubleValue: speed),
                    start: date,
                    end: date,
                    metadata: metadata
                ))
            }
        }
        return samples
    }

    private func makeEvents(
        payload: TrackerHealthRestorePayload,
        attemptID: String
    ) -> [HKWorkoutEvent] {
        var result: [HKWorkoutEvent] = []
        let metadata: [String: Any] = [
            rawRestoreKey: true,
            generationKey: generation,
            attemptKey: attemptID,
        ]
        for pause in payload.pauses.sorted(by: { $0.startedAt < $1.startedAt }) {
            guard pause.startedAt >= payload.startedAt,
                  pause.endedAt > pause.startedAt,
                  pause.endedAt <= payload.endedAt else { continue }
            result.append(HKWorkoutEvent(
                type: .pause,
                dateInterval: DateInterval(start: Date(timeIntervalSince1970: pause.startedAt), duration: 0),
                metadata: metadata
            ))
            if pause.endedAt < payload.endedAt - 0.05 {
                result.append(HKWorkoutEvent(
                    type: .resume,
                    dateInterval: DateInterval(start: Date(timeIntervalSince1970: pause.endedAt), duration: 0),
                    metadata: metadata
                ))
            }
        }
        return result
    }

    private func finishIndependentRoute(
        workout: HKWorkout,
        locations: [CLLocation],
        metadata: [String: Any]
    ) async throws -> HKWorkoutRoute {
        guard locations.count >= 2 else {
            throw RepairV4Error.operation("parcours GPS v4 insuffisant")
        }
        let builder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
        var offset = 0
        while offset < locations.count {
            let upper = min(offset + 200, locations.count)
            try await checked { completion in
                builder.insertRouteData(Array(locations[offset..<upper]), completion: completion)
            }
            offset = upper
        }
        return try await withCheckedThrowingContinuation { continuation in
            builder.finishRoute(with: workout, metadata: metadata) { route, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let route {
                    continuation.resume(returning: route)
                } else {
                    continuation.resume(throwing: RepairV4Error.operation("HealthKit n’a pas retourné la route v4"))
                }
            }
        }
    }

    private func savePerceivedEffort(
        workout: HKWorkout,
        perceivedEffort: Int?,
        metadata: [String: Any]
    ) async throws -> HKQuantitySample? {
        guard let perceivedEffort, (1...10).contains(perceivedEffort) else { return nil }
        guard #available(iOS 18.0, *) else { return nil }
        guard let type = HKQuantityType.quantityType(forIdentifier: .workoutEffortScore) else {
            throw RepairV4Error.operation("type HealthKit effort indisponible")
        }
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: .appleEffortScore(), doubleValue: Double(perceivedEffort)),
            start: workout.startDate,
            end: workout.endDate,
            metadata: metadata
        )
        try await save(sample)
        let activity = workout.workoutActivities.first
        let related = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Bool, any Error>) in
            healthStore.relateWorkoutEffortSample(
                sample,
                with: workout,
                activity: activity
            ) { success, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: success) }
            }
        }
        guard related else {
            throw RepairV4Error.operation("HealthKit a refusé l’association effort/workout")
        }
        return sample
    }

    // MARK: - Durable verification

    private func verifyDurably(
        payload: TrackerHealthRestorePayload,
        summary: TrackerSummary,
        activity: ActivityKind,
        route: SanitizedRoute,
        workoutUUID: UUID,
        routeUUID: UUID?,
        attemptID: String,
        perceivedEffort: Int?
    ) async throws {
        for delay: UInt64 in [0, 1_200_000_000, 3_000_000_000] {
            if delay > 0 { try await Task.sleep(nanoseconds: delay) }
            try await verify(
                payload: payload,
                summary: summary,
                activity: activity,
                route: route,
                workoutUUID: workoutUUID,
                routeUUID: routeUUID,
                attemptID: attemptID,
                perceivedEffort: perceivedEffort
            )
        }
    }

    private func verify(
        payload: TrackerHealthRestorePayload,
        summary: TrackerSummary,
        activity: ActivityKind,
        route: SanitizedRoute,
        workoutUUID: UUID,
        routeUUID: UUID?,
        attemptID: String,
        perceivedEffort: Int?
    ) async throws {
        let workouts = try await managedWorkouts(sessionID: payload.sessionID, summary: summary)
        guard workouts.filter({ ($0.metadata?[rawRestoreKey] as? Bool) == true }).count == 1,
              let workout = workouts.first(where: { $0.uuid == workoutUUID }),
              workout.workoutActivityType == activity.healthKitType,
              (workout.metadata?[generationKey] as? String) == generation,
              (workout.metadata?[attemptKey] as? String) == attemptID else {
            throw RepairV4Error.operation("unicité ou identité du workout v4 non vérifiée")
        }

        let durationTolerance = max(20, payload.activeDuration * 0.04)
        guard abs(workout.duration - payload.activeDuration) <= durationTolerance else {
            throw RepairV4Error.operation("durée active v4 incohérente")
        }
        try HistoricalHealthKitFullFidelity.verifyWorkoutMetadata(workout: workout, summary: summary)

        guard let routeUUID else {
            throw RepairV4Error.operation("route v4 absente")
        }
        let routeObjects = try await routes(for: workout)
        guard routeObjects.count == 1,
              let savedRoute = routeObjects.first,
              savedRoute.uuid == routeUUID,
              (savedRoute.metadata?[generationKey] as? String) == generation,
              (savedRoute.metadata?[attemptKey] as? String) == attemptID else {
            throw RepairV4Error.operation("route v4 non associée de façon unique")
        }
        let savedLocations = try await loadLocations(for: savedRoute)
        guard savedLocations.count >= max(2, Int(Double(route.points.count) * 0.95)) else {
            throw RepairV4Error.operation("points GPS v4 manquants après relecture")
        }

        if let perceivedEffort, (1...10).contains(perceivedEffort), #available(iOS 18.0, *) {
            let effort = try await effortSamples(for: workout)
            let unit = HKUnit.appleEffortScore()
            guard effort.compactMap({ $0 as? HKQuantitySample }).contains(where: {
                ($0.metadata?[attemptKey] as? String) == attemptID
                    && abs($0.quantity.doubleValue(for: unit) - Double(perceivedEffort)) < 0.01
            }) else {
                throw RepairV4Error.operation("effort Apple v4 non relu comme relation du workout")
            }
        }
    }

    // MARK: - HealthKit queries / cleanup

    private func managedWorkouts(sessionID: String, summary: TrackerSummary) async throws -> [HKWorkout] {
        let predicate = HKQuery.predicateForSamples(
            withStart: summary.startedAt.addingTimeInterval(-120),
            end: summary.endedAt.addingTimeInterval(120),
            options: []
        )
        let samples = try await querySamples(type: HKObjectType.workoutType(), predicate: predicate)
        return (samples as? [HKWorkout] ?? []).filter {
            ($0.metadata?[managedKey] as? Bool) == true
                && ($0.metadata?[sessionKey] as? String) == sessionID
        }
    }

    private func routes(for workout: HKWorkout) async throws -> [HKWorkoutRoute] {
        let samples = try await querySamples(
            type: HKSeriesType.workoutRoute(),
            predicate: HKQuery.predicateForObjects(from: workout)
        )
        return samples as? [HKWorkoutRoute] ?? []
    }

    @available(iOS 18.0, *)
    private func effortSamples(for workout: HKWorkout) async throws -> [HKSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .workoutEffortScore) else { return [] }
        var predicates: [NSPredicate] = [
            HKQuery.predicateForWorkoutEffortSamplesRelated(workout: workout, activity: nil)
        ]
        predicates.append(contentsOf: workout.workoutActivities.map {
            HKQuery.predicateForWorkoutEffortSamplesRelated(workout: workout, activity: $0)
        })
        var result: [HKSample] = []
        for predicate in predicates {
            result.append(contentsOf: try await querySamples(type: type, predicate: predicate))
        }
        return Array(Dictionary(grouping: result, by: \.uuid).values.compactMap(\.first))
    }

    private func generatedQuantitySamples(
        sessionID: String,
        summary: TrackerSummary,
        attemptID: String? = nil
    ) async throws -> [HKSample] {
        let predicate = HKQuery.predicateForSamples(
            withStart: summary.startedAt.addingTimeInterval(-2),
            end: summary.endedAt.addingTimeInterval(2),
            options: []
        )
        var identifiers: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .activeEnergyBurned,
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
            .cyclingSpeed,
            .runningSpeed,
        ]
        if #available(iOS 18.0, *) { identifiers.append(.workoutEffortScore) }
        var result: [HKSample] = []
        for identifier in identifiers {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { continue }
            let values = try await querySamples(type: type, predicate: predicate)
            result.append(contentsOf: values.filter {
                guard ($0.metadata?[rawRestoreKey] as? Bool) == true,
                      ($0.metadata?[sessionKey] as? String) == sessionID else { return false }
                if let attemptID {
                    return ($0.metadata?[attemptKey] as? String) == attemptID
                }
                return true
            })
        }
        return Array(Dictionary(grouping: result, by: \.uuid).values.compactMap(\.first))
    }

    private func requestCleanupAuthorization() async throws {
        var shareTypes: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]
        for identifier: HKQuantityTypeIdentifier in [
            .heartRate, .activeEnergyBurned, .distanceWalkingRunning, .distanceCycling,
            .distanceSwimming, .cyclingSpeed, .runningSpeed,
        ] {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) { shareTypes.insert(type) }
        }
        if #available(iOS 18.0, *),
           let effort = HKQuantityType.quantityType(forIdentifier: .workoutEffortScore) {
            shareTypes.insert(effort)
        }
        try await requestAndVerifyAuthorization(shareTypes: shareTypes)
    }

    private func requestRepairAuthorization(
        activity: ActivityKind,
        hasEnergy: Bool,
        hasSpeed: Bool,
        perceivedEffort: Int?
    ) async throws {
        var shareTypes: Set<HKSampleType> = [
            HKObjectType.workoutType(), HKSeriesType.workoutRoute()
        ]
        if let heartRate = HKQuantityType.quantityType(forIdentifier: .heartRate) { shareTypes.insert(heartRate) }
        if hasEnergy, let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) { shareTypes.insert(energy) }
        if let distance = distanceIdentifier(for: activity),
           let type = HKQuantityType.quantityType(forIdentifier: distance) { shareTypes.insert(type) }
        if hasSpeed, let speed = speedIdentifier(for: activity),
           let type = HKQuantityType.quantityType(forIdentifier: speed) { shareTypes.insert(type) }
        if perceivedEffort != nil, #available(iOS 18.0, *),
           let effort = HKQuantityType.quantityType(forIdentifier: .workoutEffortScore) { shareTypes.insert(effort) }
        try await requestAndVerifyAuthorization(shareTypes: shareTypes)
    }

    private func requestAndVerifyAuthorization(shareTypes: Set<HKSampleType>) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw RepairV4Error.operation("HealthKit indisponible")
        }
        let readTypes = Set<HKObjectType>(shareTypes.map { $0 as HKObjectType })
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { success, error in
                if let error { continuation.resume(throwing: error) }
                else if !success { continuation.resume(throwing: RepairV4Error.operation("autorisation Santé incomplète")) }
                else { continuation.resume(returning: ()) }
            }
        }
        for type in shareTypes {
            guard healthStore.authorizationStatus(for: type) == .sharingAuthorized else {
                throw RepairV4Error.operation("écriture Santé non autorisée pour \(type.identifier)")
            }
        }
    }

    // MARK: - Generic helpers

    private func loadSummary(sessionID: String) throws -> TrackerSummary {
        let url = try sessionDirectory(sessionID: sessionID).appendingPathComponent("summary.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TrackerSummary.self, from: Data(contentsOf: url))
    }

    private func sessionDirectory(sessionID: String) throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        let directory = documents
            .appendingPathComponent("Sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw RepairV4Error.operation("session Tracker locale absente")
        }
        return directory
    }

    private func loadJSONL(_ url: URL) throws -> [[String: Any]] {
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return object
        }
    }

    private func makePayload(sessionID: String, targetActivity: ActivityKind) throws -> TrackerHealthRestorePayload {
        let url = try packetBuilder.makeTransferFile(sessionID: sessionID, targetActivity: targetActivity)
        defer { try? FileManager.default.removeItem(at: url) }
        return try JSONDecoder().decode(TrackerHealthRestorePayload.self, from: Data(contentsOf: url))
    }

    private func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? Double { return value }
        return nil
    }

    private func generatedMetadata(sessionID: String, attemptID: String) -> [String: Any] {
        [
            rawRestoreKey: true,
            sessionKey: sessionID,
            rawRestoreSourceKey: source,
            generationKey: generation,
            attemptKey: attemptID,
        ]
    }

    private func routeMetadata(
        sessionID: String,
        schema: Int,
        attemptID: String,
        sourceName: String
    ) -> [String: Any] {
        [
            rawRestoreKey: true,
            sessionKey: sessionID,
            rawRestoreSchemaKey: schema,
            rawRestoreSourceKey: source,
            generationKey: generation,
            attemptKey: attemptID,
            "com.rzbck.watchsensorlab.route_source": sourceName,
            HKMetadataKeyExternalUUID: "watchtracker-v4-route-\(sessionID)-\(attemptID)",
        ]
    }

    private func distanceIdentifier(for activity: ActivityKind) -> HKQuantityTypeIdentifier? {
        switch activity {
        case .cycling, .handCycling: return .distanceCycling
        case .swimming, .waterFitness, .waterPolo: return .distanceSwimming
        case .walking, .running, .hiking, .trackAndField: return .distanceWalkingRunning
        default: return nil
        }
    }

    private func speedIdentifier(for activity: ActivityKind) -> HKQuantityTypeIdentifier? {
        switch activity {
        case .cycling, .handCycling: return .cyclingSpeed
        case .running, .trackAndField: return .runningSpeed
        default: return nil
        }
    }

    private func querySamples(type: HKSampleType, predicate: NSPredicate?) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples ?? []) }
            }
            healthStore.execute(query)
        }
    }

    private func loadLocations(for route: HKWorkoutRoute) async throws -> [CLLocation] {
        try await withCheckedThrowingContinuation { continuation in
            var result: [CLLocation] = []
            let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                if let error { continuation.resume(throwing: error); return }
                result.append(contentsOf: locations ?? [])
                if done { continuation.resume(returning: result) }
            }
            healthStore.execute(query)
        }
    }

    private func begin(_ builder: HKWorkoutBuilder, at date: Date) async throws {
        try await checked { completion in builder.beginCollection(withStart: date, completion: completion) }
    }

    private func end(_ builder: HKWorkoutBuilder, at date: Date) async throws {
        try await checked { completion in builder.endCollection(withEnd: date, completion: completion) }
    }

    private func addMetadata(_ metadata: [String: Any], to builder: HKWorkoutBuilder) async throws {
        try await checked { completion in builder.addMetadata(metadata, completion: completion) }
    }

    private func add(_ samples: [HKSample], to builder: HKWorkoutBuilder) async throws {
        try await checked { completion in builder.add(samples, completion: completion) }
    }

    private func add(_ events: [HKWorkoutEvent], to builder: HKWorkoutBuilder) async throws {
        try await checked { completion in builder.addWorkoutEvents(events, completion: completion) }
    }

    private func finish(_ builder: HKWorkoutBuilder) async throws -> HKWorkout? {
        try await withCheckedThrowingContinuation { continuation in
            builder.finishWorkout { workout, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: workout) }
            }
        }
    }

    private func save(_ object: HKObject) async throws {
        try await checked { completion in healthStore.save(object, withCompletion: completion) }
    }

    private func delete(_ objects: [HKObject]) async throws {
        guard !objects.isEmpty else { return }
        try await checked { completion in healthStore.delete(objects, withCompletion: completion) }
    }

    private func checked(_ operation: (@escaping (Bool, Error?) -> Void) -> Void) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            operation { success, error in
                if let error { continuation.resume(throwing: error) }
                else if !success { continuation.resume(throwing: RepairV4Error.operation("opération HealthKit refusée")) }
                else { continuation.resume(returning: ()) }
            }
        }
    }

    private enum RepairV4Error: LocalizedError {
        case operation(String)
        var errorDescription: String? {
            switch self { case .operation(let value): return value }
        }
    }
}

struct HistoricalHealthKitRepairV4View: View {
    @ObservedObject private var coordinator = HistoricalHealthKitRepairV4Coordinator.shared
    @State private var summaries: [TrackerSummary] = []
    private let store = NativeSessionStore()

    var body: some View {
        NavigationStack {
            Group {
                if summaries.isEmpty {
                    ContentUnavailableView("Aucune séance Tracker", systemImage: "checkmark.circle.fill")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 7) {
                                Label("Récupération Santé v4", systemImage: "shield.checkered")
                                    .font(.headline.weight(.bold))
                                Text(
                                    "Diagnostic Watch + iPhone d’abord. Aucun nouvel exercice n’est créé tant qu’une restauration de test existe. Le nettoyage cible uniquement les objets Tracker de cette session ; les raw locaux restent intacts."
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))

                            ForEach(summaries) { summary in
                                HistoricalRepairV4Card(summary: summary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Récupération")
            .onAppear { summaries = store.listSummaries().sorted { $0.startedAt > $1.startedAt } }
        }
        .preferredColorScheme(.dark)
    }
}

private struct HistoricalRepairV4Card: View {
    @ObservedObject private var coordinator = HistoricalHealthKitRepairV4Coordinator.shared
    let summary: TrackerSummary

    @State private var selection: ActivityKind?
    @State private var perceivedEffort: Int?
    @State private var confirmCleanup = false
    @State private var confirmRepair = false

    private var audit: HistoricalHealthKitRepairV4Coordinator.RouteAudit? {
        coordinator.auditBySession[summary.sessionID]
    }

    private var activities: [ActivityKind] {
        ActivityKind.allCases.filter { !$0.isAutomatic }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ActivityKind(rawValue: summary.activity)?.label ?? summary.activity)
                        .font(.headline.weight(.bold))
                    Text(summary.startedAt, format: .dateTime.day().month().year().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(summary.sessionID)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if coordinator.internallyVerifiedSessions.contains(summary.sessionID) {
                    Image(systemName: "checkmark.shield.fill").foregroundStyle(.orange)
                }
            }

            HStack(spacing: 12) {
                v4Metric(value: v4Distance(summary.distanceMeters), label: "Résumé")
                v4Metric(value: audit.map { "\($0.watchPointCount)" } ?? "—", label: "GPS Watch")
                v4Metric(value: audit.map { "\($0.phonePointCount)" } ?? "—", label: "GPS iPhone")
            }

            if let audit {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Route retenue : \(audit.chosenSource ?? "aucune") · \(audit.chosenPointCount) points filtrés")
                    Text(String(format: "Géométrie Watch %.2f km · iPhone %.2f km", audit.watchGeometryMeters / 1000, audit.phoneGeometryMeters / 1000))
                    if let watchRaw = audit.watchRawDistanceMeters {
                        Text(String(format: "Distance raw Watch cumulée : %.2f km", watchRaw / 1000))
                    }
                    if let phoneRaw = audit.phoneRawDistanceMeters {
                        Text(String(format: "Distance raw iPhone cumulée : %.2f km", phoneRaw / 1000))
                    }
                    Text("Gaps actifs >3 s : \(audit.activeGapCountOver3Seconds) · max \(String(format: "%.1f", audit.maxActiveGapSeconds)) s")
                    Text("Restaurations de test HealthKit : \(audit.generatedWorkoutCount)")
                        .foregroundStyle(audit.generatedWorkoutCount == 0 ? .secondary : .orange)
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            Button {
                coordinator.inspect(sessionID: summary.sessionID)
            } label: {
                Label("Actualiser le diagnostic", systemImage: "waveform.path.ecg.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(coordinator.activeSessionID != nil)

            if let audit, audit.generatedWorkoutCount > 0 {
                Button(role: .destructive) {
                    confirmCleanup = true
                } label: {
                    Label(
                        "Nettoyer \(audit.generatedWorkoutCount) restauration(s) de test",
                        systemImage: "trash"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(coordinator.activeSessionID != nil)
            }

            Picker("Sport réel", selection: $selection) {
                Text("Choisir…").tag(Optional<ActivityKind>.none)
                ForEach(activities) { activity in
                    Text(activity.label).tag(Optional(activity))
                }
            }
            .pickerStyle(.menu)

            Picker("Effort ressenti Apple", selection: $perceivedEffort) {
                Text("Non renseigné").tag(Optional<Int>.none)
                ForEach(1...10, id: \.self) { value in
                    Text("\(value) / 10").tag(Optional(value))
                }
            }
            .pickerStyle(.menu)

            Button {
                confirmRepair = true
            } label: {
                Label("Reconstruire proprement dans Santé", systemImage: "heart.circle.fill")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(
                selection == nil
                    || coordinator.activeSessionID != nil
                    || audit?.canReconstruct != true
            )

            if let status = coordinator.statusBySession[summary.sessionID] {
                Text(status)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(
                        status.contains("échoué") || status.contains("bloquée") ? .red : .secondary
                    )
            }
        }
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
        .onAppear {
            if perceivedEffort == nil {
                perceivedEffort = HistoricalHealthKitFullFidelity.savedPerceivedEffort(sessionID: summary.sessionID)
            }
            if audit == nil { coordinator.inspect(sessionID: summary.sessionID) }
        }
        .confirmationDialog(
            "Supprimer uniquement les restaurations Tracker de test de cette session ?",
            isPresented: $confirmCleanup,
            titleVisibility: .visible
        ) {
            Button("Nettoyer les restaurations de test", role: .destructive) {
                coordinator.cleanupGeneratedRestorations(sessionID: summary.sessionID)
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Le filtre exige raw_restoration=true + le session ID exact. Les raw Tracker locaux et les workouts normaux ne sont pas supprimés.")
        }
        .confirmationDialog(
            "Créer UNE nouvelle restauration v4 ?",
            isPresented: $confirmRepair,
            titleVisibility: .visible
        ) {
            if let selection {
                Button("Reconstruire en \(selection.label)") {
                    coordinator.repair(
                        sessionID: summary.sessionID,
                        targetActivity: selection,
                        perceivedEffort: perceivedEffort
                    )
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("La reconstruction est bloquée tant qu’une restauration de test existe. La route est choisie après analyse séparée des raw Watch et iPhone.")
        }
    }

    private func v4Metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.subheadline.weight(.bold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func v4Distance(_ meters: Double) -> String {
    meters >= 1000
        ? String(format: "%.2f km", meters / 1000)
        : String(format: "%.0f m", meters)
}
