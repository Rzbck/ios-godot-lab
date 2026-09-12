import CoreLocation
import Foundation
import HealthKit
import SwiftUI

/// Historical reconstruction v4.
///
/// Live workouts remain Watch-owned. Historical recovery is iPhone-only.
/// V4 refuses to create a new recovery while any older raw-restoration workout
/// for the same Tracker session still exists. Cleanup is explicit and strictly
/// scoped to objects tagged raw_restoration=true + the exact session ID.
///
/// Route policy:
/// - Tracker summary distance is compared independently with Watch/iPhone raw counters;
/// - one incomplete secondary counter never invalidates a matching primary counter;
/// - the source whose counter agrees with the summary is primary;
/// - trusted cumulative distance rejects isolated stale-coordinate excursions, even across long gaps;
/// - the secondary GPS source may only fill ACTIVE gaps that already exist in the raw primary stream;
/// - a secondary gap fill must also fit the authoritative primary counter distance budget;
/// - counter-guided local denoising must not create >3s gaps;
/// - real capture holes are preserved: no coordinate is fabricated or interpolated;
/// - ordinary geometry/continuity warnings stay diagnostic, but a gross route-distance excess
///   blocks HealthKit writes so an obvious out-and-back detour cannot be promoted to Fitness.
@MainActor
final class HistoricalHealthKitRepairV4Coordinator: ObservableObject {
    static let shared = HistoricalHealthKitRepairV4Coordinator()

    struct Audit: Equatable {
        let summaryDistanceMeters: Double
        let watchRawPoints: Int
        let phoneRawPoints: Int
        let watchFilteredPoints: Int
        let phoneFilteredPoints: Int
        let watchGeometryMeters: Double
        let phoneGeometryMeters: Double
        let watchRawDistanceMeters: Double?
        let phoneRawDistanceMeters: Double?
        let distanceReferenceSource: String?
        let chosenSource: String?
        let chosenPoints: Int
        let selectedGeometryMeters: Double
        let activeGapsOver3Seconds: Int
        let maxActiveGapSeconds: Double
        let generatedWorkoutCount: Int
        let normalWorkoutCount: Int
        let distanceConflict: Bool
        let routeGeometryConflict: Bool
        let routeContinuityConflict: Bool
        let severeRouteCounterConflict: Bool
        let generatedWorkoutActivityTypeRawValue: Int?
        let generatedTargetActivity: String?
        let generatedWorkoutBrandName: String?
        let generatedEffortScore: Double?
        let generatedEffortSampleCount: Int
        let savedPerceivedEffort: Int?

        var canReconstruct: Bool {
            generatedWorkoutCount == 0
                && normalWorkoutCount == 0
                && chosenPoints >= 2
                && !distanceConflict
                && !severeRouteCounterConflict
        }
    }

    @Published private(set) var activeSessionID: String?
    @Published private(set) var statusBySession: [String: String] = [:]
    @Published private(set) var auditBySession: [String: Audit] = [:]
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

    private let generation = "ios_historical_v4_fused_route"
    private let source = "tracker_raw_ios_v4_fused_route"

    private init() {}

    // MARK: - Product actions

    func inspect(sessionID: String) {
        guard activeSessionID == nil else { return }
        activeSessionID = sessionID
        statusBySession[sessionID] = "Diagnostic raw Watch + iPhone…"

        Task {
            defer { activeSessionID = nil }
            do {
                let summary = try loadSummary(sessionID: sessionID)
                let raw = try loadRawRoutes(summary: summary)
                // Inspection stays permissive: the legacy stored activity may itself
                // be wrong, so use generic cycling-scale plausibility here.
                let choice = chooseRoute(
                    raw: raw,
                    summaryDistanceMeters: summary.distanceMeters,
                    activity: .other
                )
                let workouts = try await managedWorkouts(sessionID: sessionID, summary: summary)
                let generated = workouts.filter { isGenerated($0, sessionID: sessionID) }
                let normal = workouts.filter { !isGenerated($0, sessionID: sessionID) }
                let conflict = hasDistanceConflict(
                    summaryMeters: summary.distanceMeters,
                    watchRawMeters: raw.watchRawDistanceMeters,
                    phoneRawMeters: raw.phoneRawDistanceMeters
                )
                let geometryConflict = hasRouteGeometryConflict(
                    summaryMeters: summary.distanceMeters,
                    route: choice.selected
                )
                let continuityConflict = hasRouteContinuityConflict(choice.selected)
                let severeCounterConflict = hasSevereRouteCounterConflict(
                    summaryMeters: summary.distanceMeters,
                    route: choice.selected
                )
                let distanceReference = distanceReferenceSource(
                    summaryMeters: summary.distanceMeters,
                    watchRawMeters: raw.watchRawDistanceMeters,
                    phoneRawMeters: raw.phoneRawDistanceMeters
                )

                let generatedWorkout = generated.first
                var generatedEffortScore: Double?
                var generatedEffortSampleCount = 0
                if #available(iOS 18.0, *), let generatedWorkout {
                    let samples = try await effortSamples(for: generatedWorkout)
                        .compactMap { $0 as? HKQuantitySample }
                    generatedEffortSampleCount = samples.count
                    let attemptID = generatedWorkout.metadata?[attemptKey] as? String
                    let matching = samples.first {
                        attemptID == nil || ($0.metadata?[attemptKey] as? String) == attemptID
                    }
                    generatedEffortScore = matching?.quantity.doubleValue(for: .appleEffortScore())
                }

                auditBySession[sessionID] = Audit(
                    summaryDistanceMeters: summary.distanceMeters,
                    watchRawPoints: raw.watch.count,
                    phoneRawPoints: raw.phone.count,
                    watchFilteredPoints: choice.watch.points.count,
                    phoneFilteredPoints: choice.phone.points.count,
                    watchGeometryMeters: choice.watch.geometryMeters,
                    phoneGeometryMeters: choice.phone.geometryMeters,
                    watchRawDistanceMeters: raw.watchRawDistanceMeters,
                    phoneRawDistanceMeters: raw.phoneRawDistanceMeters,
                    distanceReferenceSource: distanceReference,
                    chosenSource: choice.selected?.source,
                    chosenPoints: choice.selected?.points.count ?? 0,
                    selectedGeometryMeters: choice.selected?.geometryMeters ?? 0,
                    activeGapsOver3Seconds: choice.selected?.activeGapsOver3Seconds ?? 0,
                    maxActiveGapSeconds: choice.selected?.maxActiveGapSeconds ?? 0,
                    generatedWorkoutCount: generated.count,
                    normalWorkoutCount: normal.count,
                    distanceConflict: conflict,
                    routeGeometryConflict: geometryConflict,
                    routeContinuityConflict: continuityConflict,
                    severeRouteCounterConflict: severeCounterConflict,
                    generatedWorkoutActivityTypeRawValue: generatedWorkout.map {
                        Int($0.workoutActivityType.rawValue)
                    },
                    generatedTargetActivity: generatedWorkout?.metadata?[correctionTargetKey] as? String,
                    generatedWorkoutBrandName: generatedWorkout?.metadata?[HKMetadataKeyWorkoutBrandName] as? String,
                    generatedEffortScore: generatedEffortScore,
                    generatedEffortSampleCount: generatedEffortSampleCount,
                    savedPerceivedEffort: HistoricalHealthKitFullFidelity.savedPerceivedEffort(
                        sessionID: sessionID
                    )
                )

                if !normal.isEmpty {
                    statusBySession[sessionID] =
                        "Workout Tracker normal détecté · reconstruction historique bloquée."
                } else if !generated.isEmpty {
                    statusBySession[sessionID] =
                        "\(generated.count) restauration(s) de test détectée(s) · nettoyage requis avant tout nouvel essai."
                } else if conflict {
                    statusBySession[sessionID] =
                        "Aucun compteur raw fiable ne confirme la distance du résumé · aucune écriture Santé."
                } else if severeCounterConflict {
                    statusBySession[sessionID] =
                        "Route GPS contient encore un détour incompatible avec le compteur Tracker · écriture bloquée."
                } else if choice.selected == nil {
                    statusBySession[sessionID] = "Aucune route GPS sûre après analyse Watch + iPhone."
                } else if let selected = choice.selected {
                    let warning = (geometryConflict || continuityConflict)
                        ? " · avertissement qualité route conservé (non bloquant, aucun point inventé)"
                        : ""
                    statusBySession[sessionID] =
                        "Diagnostic prêt · route \(selected.source), \(selected.points.count) points\(warning) · aucune écriture Santé."
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
        statusBySession[sessionID] = "Nettoyage ciblé des restaurations Tracker…"

        Task {
            defer { activeSessionID = nil }
            do {
                let summary = try loadSummary(sessionID: sessionID)
                try await requestCleanupAuthorization()
                let workouts = try await managedWorkouts(sessionID: sessionID, summary: summary)
                let generated = workouts.filter { isGenerated($0, sessionID: sessionID) }
                let normal = workouts.filter { !isGenerated($0, sessionID: sessionID) }
                guard normal.isEmpty else {
                    throw V4Error.operation("workout Tracker normal présent ; nettoyage annulé")
                }
                guard !generated.isEmpty else {
                    statusBySession[sessionID] = "Aucune restauration de test à nettoyer."
                    auditBySession.removeValue(forKey: sessionID)
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
                    summary: summary,
                    attemptID: nil
                ))
                objects.append(contentsOf: generated)

                let unique = Array(Dictionary(grouping: objects, by: \.uuid).values.compactMap(\.first))
                try await delete(unique)

                let remaining = try await managedWorkouts(sessionID: sessionID, summary: summary)
                let remainingGenerated = remaining.filter { isGenerated($0, sessionID: sessionID) }
                guard remainingGenerated.isEmpty else {
                    throw V4Error.operation(
                        "\(remainingGenerated.count) restauration(s) restent après suppression"
                    )
                }

                auditBySession.removeValue(forKey: sessionID)
                statusBySession[sessionID] =
                    "Nettoyage vérifié · zéro restauration de test restante · raw Tracker intacts."
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
                let raw = try loadRawRoutes(summary: summary)

                guard !hasDistanceConflict(
                    summaryMeters: summary.distanceMeters,
                    watchRawMeters: raw.watchRawDistanceMeters,
                    phoneRawMeters: raw.phoneRawDistanceMeters
                ) else {
                    throw V4Error.operation(
                        "aucun compteur raw fiable ne confirme la distance du résumé"
                    )
                }

                let choice = chooseRoute(
                    raw: raw,
                    summaryDistanceMeters: summary.distanceMeters,
                    activity: targetActivity
                )
                guard let selectedRoute = choice.selected, selectedRoute.points.count >= 2 else {
                    throw V4Error.operation("aucune route GPS sûre après filtrage")
                }
                guard !hasSevereRouteCounterConflict(
                    summaryMeters: summary.distanceMeters,
                    route: selectedRoute
                ) else {
                    throw V4Error.operation(
                        "route GPS contient encore un détour incompatible avec le compteur Tracker"
                    )
                }

                try await requestRepairAuthorization(
                    activity: targetActivity,
                    hasEnergy: (payload.activeEnergyKcal ?? 0) > 0,
                    hasSpeed: speedIdentifier(for: targetActivity) != nil,
                    perceivedEffort: perceivedEffort
                )

                let existing = try await managedWorkouts(sessionID: sessionID, summary: summary)
                let generated = existing.filter { isGenerated($0, sessionID: sessionID) }
                let normal = existing.filter { !isGenerated($0, sessionID: sessionID) }
                guard normal.isEmpty else {
                    throw V4Error.operation("workout Tracker normal présent ; aucune écriture effectuée")
                }
                guard generated.isEmpty else {
                    throw V4Error.operation(
                        "\(generated.count) restauration(s) existent encore ; nettoyage requis"
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
                    routeUUID: created.route.uuid,
                    attemptID: attemptID,
                    perceivedEffort: perceivedEffort
                )

                internallyVerifiedSessions.insert(sessionID)
                auditBySession.removeValue(forKey: sessionID)
                statusBySession[sessionID] =
                    "HealthKit v4 écrit et relu · une seule restauration · PAS encore validé dans Santé/Forme."
            } catch {
                statusBySession[sessionID] = "Reconstruction v4 échouée · \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Raw data / route selection

    private struct RawPoint: Equatable {
        let timestamp: TimeInterval
        let latitude: Double
        let longitude: Double
        let altitude: Double
        let horizontalAccuracy: Double
        let verticalAccuracy: Double
        let nativeSpeed: Double?
        let cumulativeDistanceMeters: Double?
        let source: String
    }

    private struct RawRoutes {
        let watch: [RawPoint]
        let phone: [RawPoint]
        let pauses: [TrackerHealthRestorePause]
        let watchRawDistanceMeters: Double?
        let phoneRawDistanceMeters: Double?
    }

    private struct CleanRoute {
        let source: String
        let points: [RawPoint]
        let geometryMeters: Double
        let activeGapsOver3Seconds: Int
        let maxActiveGapSeconds: Double
        let p90AccuracyMeters: Double
    }

    private struct RouteChoice {
        let watch: CleanRoute
        let phone: CleanRoute
        let selected: CleanRoute?
    }

    private func loadRawRoutes(summary: TrackerSummary) throws -> RawRoutes {
        let directory = try sessionDirectory(sessionID: summary.sessionID)
        var rows = try loadJSONL(directory.appendingPathComponent("samples.jsonl"))
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
            let payload = row["payload"] as? [String: Any] ?? [:]
            let quality = row["quality"] as? [String: Any] ?? [:]

            if record == "sample" {
                switch row["kind"] as? String ?? "" {
                case "watch_location":
                    if let point = rawPoint(
                        timestamp: timestamp,
                        source: "WATCH",
                        payload: payload,
                        quality: payload
                    ) {
                        watch.append(point)
                    }
                    if let distance = number(payload["distance_m"]), distance >= 0 {
                        watchDistances.append((timestamp, distance))
                    }
                case "location":
                    if let point = rawPoint(
                        timestamp: timestamp,
                        source: "IPHONE",
                        payload: payload,
                        quality: quality
                    ) {
                        phone.append(point)
                    }
                    if let distance = number(payload["distance_m"]), distance >= 0 {
                        phoneDistances.append((timestamp, distance))
                    }
                default:
                    break
                }
                continue
            }

            guard record == "event", row["source"] as? String == "watch" else { continue }
            switch row["event"] as? String ?? "" {
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

        return RawRoutes(
            watch: deduplicate(watch),
            phone: deduplicate(phone),
            pauses: makePauses(explicit: explicitMarks, fallback: phaseMarks, start: start, end: end),
            watchRawDistanceMeters: watchDistances.sorted(by: { $0.0 < $1.0 }).last?.1,
            phoneRawDistanceMeters: phoneDistances.sorted(by: { $0.0 < $1.0 }).last?.1
        )
    }

    private func rawPoint(
        timestamp: TimeInterval,
        source: String,
        payload: [String: Any],
        quality: [String: Any]
    ) -> RawPoint? {
        guard let latitude = number(payload["latitude"]),
              let longitude = number(payload["longitude"]),
              (-90...90).contains(latitude),
              (-180...180).contains(longitude),
              let horizontal = number(quality["horizontal_accuracy_m"]),
              horizontal >= 0,
              horizontal <= 50 else {
            return nil
        }
        return RawPoint(
            timestamp: timestamp,
            latitude: latitude,
            longitude: longitude,
            altitude: number(payload["altitude_m"]) ?? 0,
            horizontalAccuracy: horizontal,
            verticalAccuracy: number(quality["vertical_accuracy_m"]) ?? -1,
            nativeSpeed: number(quality["native_speed_mps"]) ?? number(payload["speed_mps"]),
            cumulativeDistanceMeters: number(payload["distance_m"]),
            source: source
        )
    }

    private func chooseRoute(
        raw: RawRoutes,
        summaryDistanceMeters: Double,
        activity: ActivityKind
    ) -> RouteChoice {
        let watchTrusted = counterAgrees(
            summaryMeters: summaryDistanceMeters,
            rawMeters: raw.watchRawDistanceMeters
        )
        let phoneTrusted = counterAgrees(
            summaryMeters: summaryDistanceMeters,
            rawMeters: raw.phoneRawDistanceMeters
        )

        let watch = sanitize(
            source: "WATCH",
            points: raw.watch,
            pauses: raw.pauses,
            activity: activity,
            targetDistanceMeters: watchTrusted ? summaryDistanceMeters : nil
        )
        let phone = sanitize(
            source: "IPHONE",
            points: raw.phone,
            pauses: raw.pauses,
            activity: activity,
            targetDistanceMeters: phoneTrusted ? summaryDistanceMeters : nil
        )

        let primary: CleanRoute
        let secondary: CleanRoute
        let primaryRawPoints: [RawPoint]
        if watchTrusted && !phoneTrusted {
            primary = watch
            secondary = phone
            primaryRawPoints = raw.watch
        } else if phoneTrusted && !watchTrusted {
            primary = phone
            secondary = watch
            primaryRawPoints = raw.phone
        } else if routeScore(watch, summaryMeters: summaryDistanceMeters)
                    <= routeScore(phone, summaryMeters: summaryDistanceMeters) {
            primary = watch
            secondary = phone
            primaryRawPoints = raw.watch
        } else {
            primary = phone
            secondary = watch
            primaryRawPoints = raw.phone
        }

        guard primary.points.count >= 2 else {
            let fallback = secondary.points.count >= 2 ? secondary : nil
            return RouteChoice(watch: watch, phone: phone, selected: fallback)
        }

        let merged = mergeActiveGaps(
            primary: primary,
            secondary: secondary,
            primaryRawPoints: primaryRawPoints,
            pauses: raw.pauses,
            activity: activity
        )
        let finalRoute = denoiseForDistance(
            route: merged,
            targetDistanceMeters: summaryDistanceMeters,
            pauses: raw.pauses,
            activity: activity
        )

        return RouteChoice(
            watch: watch,
            phone: phone,
            selected: finalRoute.points.count >= 2 ? finalRoute : nil
        )
    }

    private func sanitize(
        source: String,
        points: [RawPoint],
        pauses: [TrackerHealthRestorePause],
        activity: ActivityKind,
        targetDistanceMeters: Double?
    ) -> CleanRoute {
        let speedLimit = maximumPlausibleSpeed(activity)
        var values = deduplicate(points).filter { !isPaused($0.timestamp, pauses: pauses) }

        if targetDistanceMeters != nil {
            values = counterIsolatedOutlierFilter(values, pauses: pauses)
        }

        // Remove isolated impossible spikes. Only raw points are discarded; no
        // interpolated coordinate is ever fabricated.
        var didChange = true
        while didChange, values.count >= 3 {
            didChange = false
            var nextValues: [RawPoint] = [values[0]]
            for index in 1..<(values.count - 1) {
                let previous = nextValues.last ?? values[index - 1]
                let current = values[index]
                let next = values[index + 1]
                if impliedSpeed(previous, current) > speedLimit,
                   impliedSpeed(current, next) > speedLimit,
                   impliedSpeed(previous, next) <= speedLimit {
                    didChange = true
                    continue
                }
                nextValues.append(current)
            }
            if let last = values.last { nextValues.append(last) }
            values = nextValues
        }

        // Reject remaining impossible jumps sequentially.
        var accepted: [RawPoint] = []
        for point in values {
            guard let last = accepted.last else {
                accepted.append(point)
                continue
            }
            if intervalOverlapsPause(last.timestamp, point.timestamp, pauses: pauses)
                || impliedSpeed(last, point) <= speedLimit {
                accepted.append(point)
            }
        }

        if targetDistanceMeters != nil {
            accepted = counterAwareFilter(accepted)
        }

        var route = makeCleanRoute(source: source, points: accepted, pauses: pauses)
        if let targetDistanceMeters {
            route = denoiseForDistance(
                route: route,
                targetDistanceMeters: targetDistanceMeters,
                pauses: pauses,
                activity: activity
            )
        }
        return route
    }

    /// Remove an isolated stale coordinate when the trusted cumulative distance proves
    /// both legs through that point impossible while the direct neighbour bridge fits.
    /// This is allowed across a long time gap because the counter, not elapsed time,
    /// is the evidence. No replacement coordinate is fabricated.
    private func counterIsolatedOutlierFilter(
        _ points: [RawPoint],
        pauses: [TrackerHealthRestorePause]
    ) -> [RawPoint] {
        var values = deduplicate(points)
        guard values.count >= 3 else { return values }

        var didChange = true
        while didChange, values.count >= 3 {
            didChange = false
            var nextValues: [RawPoint] = [values[0]]
            for index in 1..<(values.count - 1) {
                let previous = nextValues.last ?? values[index - 1]
                let current = values[index]
                let next = values[index + 1]

                if !intervalOverlapsPause(previous.timestamp, next.timestamp, pauses: pauses),
                   !counterLegIsConsistent(previous, current),
                   !counterLegIsConsistent(current, next),
                   counterLegIsConsistent(previous, next) {
                    didChange = true
                    continue
                }
                nextValues.append(current)
            }
            if let last = values.last { nextValues.append(last) }
            values = deduplicate(nextValues)
        }
        return values
    }

    /// A straight-line displacement cannot legitimately exceed the cumulative sport
    /// distance over the same interval by a large margin. Accuracy allowance covers
    /// normal GPS noise and minor timestamp skew without legitimising stale excursions.
    private func counterLegIsConsistent(_ start: RawPoint, _ end: RawPoint) -> Bool {
        guard let startDistance = start.cumulativeDistanceMeters,
              let endDistance = end.cumulativeDistanceMeters,
              endDistance >= startDistance else {
            return true
        }
        let counterAdvance = endDistance - startDistance
        let accuracyBudget = min(
            80,
            max(12, start.horizontalAccuracy + end.horizontalAccuracy)
        )
        let allowedGeometry = counterAdvance * 1.20 + accuracyBudget
        return distance(start, end) <= allowedGeometry
    }

    /// Uses the cumulative raw distance only as a local noise discriminator. It never
    /// rewrites distance or coordinates, and it never skips a point when that would
    /// create a filter-induced gap longer than three seconds. Comparisons are made
    /// against immediate raw neighbours, not the last accepted point, so removals do
    /// not cascade into artificial holes.
    private func counterAwareFilter(_ points: [RawPoint]) -> [RawPoint] {
        let ordered = deduplicate(points)
        guard ordered.count >= 3 else { return ordered }
        var accepted: [RawPoint] = [ordered[0]]

        for index in 1..<(ordered.count - 1) {
            let previousRaw = ordered[index - 1]
            let current = ordered[index]
            let nextRaw = ordered[index + 1]
            guard let lastAccepted = accepted.last else {
                accepted.append(current)
                continue
            }

            // Never let this local noise filter manufacture a >3s hole.
            if nextRaw.timestamp - lastAccepted.timestamp > 3.0 {
                accepted.append(current)
                continue
            }

            guard let previousDistance = previousRaw.cumulativeDistanceMeters,
                  let currentDistance = current.cumulativeDistanceMeters,
                  let nextDistance = nextRaw.cumulativeDistanceMeters,
                  currentDistance >= previousDistance,
                  nextDistance >= currentDistance else {
                accepted.append(current)
                continue
            }

            let counterAdvance = nextDistance - previousDistance
            let before = distance(previousRaw, current) + distance(current, nextRaw)
            let bridge = distance(previousRaw, nextRaw)
            let detour = before - bridge
            let deviation = perpendicularDeviation(current, from: previousRaw, to: nextRaw)
            let noiseEnvelope = min(
                30,
                max(6, current.horizontalAccuracy * 1.5)
            )

            // Only remove a local accuracy-scale wobble while the authoritative
            // counter barely advances across the same immediate triplet.
            if nextRaw.timestamp - previousRaw.timestamp <= 3.0,
               counterAdvance < 1.5,
               detour > 0.25,
               deviation <= noiseEnvelope {
                continue
            }

            accepted.append(current)
        }

        if let last = ordered.last,
           accepted.last?.timestamp != last.timestamp {
            accepted.append(last)
        }
        return deduplicate(accepted)
    }

    /// Fill only ACTIVE holes that already exist in the raw primary stream. A gap
    /// created by filtering is deliberately left to the primary route instead of
    /// being backfilled from the secondary device. A secondary point is accepted only
    /// when the chain remains kinematically plausible at both ends and its total
    /// geometry fits the trusted primary cumulative-distance budget for that gap.
    private func mergeActiveGaps(
        primary: CleanRoute,
        secondary: CleanRoute,
        primaryRawPoints: [RawPoint],
        pauses: [TrackerHealthRestorePause],
        activity: ActivityKind
    ) -> CleanRoute {
        guard primary.points.count >= 2, secondary.points.count >= 2 else { return primary }
        let speedLimit = maximumPlausibleSpeed(activity) * 1.15
        let primaryPoints = primary.points.sorted { $0.timestamp < $1.timestamp }
        let rawPrimary = deduplicate(primaryRawPoints)
        let secondaryPoints = secondary.points.sorted { $0.timestamp < $1.timestamp }
        var merged: [RawPoint] = []
        var inserted = 0

        for index in 0..<(primaryPoints.count - 1) {
            let start = primaryPoints[index]
            let end = primaryPoints[index + 1]
            if merged.last?.timestamp != start.timestamp {
                merged.append(start)
            }

            let gap = end.timestamp - start.timestamp
            guard gap > 3,
                  !intervalOverlapsPause(start.timestamp, end.timestamp, pauses: pauses) else {
                continue
            }

            // Only fill a hole that was already absent from the raw primary stream.
            // If raw primary points exist inside this interval, the hole was created
            // by our filtering and must not be replaced with a second sensor source.
            guard !rawPrimary.contains(where: {
                $0.timestamp > start.timestamp && $0.timestamp < end.timestamp
            }) else {
                continue
            }

            let candidates = secondaryPoints.filter {
                $0.timestamp > start.timestamp
                    && $0.timestamp < end.timestamp
                    && $0.horizontalAccuracy <= 35
                    && !isPaused($0.timestamp, pauses: pauses)
            }
            guard !candidates.isEmpty else { continue }

            var bridge: [RawPoint] = []
            var previous = start
            for candidate in candidates {
                if impliedSpeed(previous, candidate) <= speedLimit {
                    bridge.append(candidate)
                    previous = candidate
                }
            }
            while let last = bridge.last,
                  impliedSpeed(last, end) > speedLimit {
                bridge.removeLast()
            }
            guard let last = bridge.last,
                  impliedSpeed(last, end) <= speedLimit,
                  bridgeFitsPrimaryCounter(start: start, bridge: bridge, end: end) else {
                continue
            }
            merged.append(contentsOf: bridge)
            inserted += bridge.count
        }
        if let last = primaryPoints.last { merged.append(last) }

        let sourceName = inserted > 0
            ? "\(primary.source)+\(secondary.source)"
            : primary.source
        return makeCleanRoute(
            source: sourceName,
            points: deduplicate(merged),
            pauses: pauses
        )
    }

    private func bridgeFitsPrimaryCounter(
        start: RawPoint,
        bridge: [RawPoint],
        end: RawPoint
    ) -> Bool {
        guard let startDistance = start.cumulativeDistanceMeters,
              let endDistance = end.cumulativeDistanceMeters,
              endDistance >= startDistance else {
            return true
        }

        let counterAdvance = endDistance - startDistance
        let chain = [start] + bridge + [end]
        let geometry = zip(chain, chain.dropFirst()).reduce(0.0) {
            $0 + distance($1.0, $1.1)
        }
        let maxAccuracy = chain.map(\.horizontalAccuracy).max() ?? 0
        let accuracyBudget = min(
            120,
            max(25, start.horizontalAccuracy + end.horizontalAccuracy + maxAccuracy)
        )
        return geometry <= counterAdvance * 1.25 + accuracyBudget
    }

    /// Reduce only accuracy-scale zigzags. A point is removable only if bridging
    /// its neighbours stays within three seconds and plausible sport speed, so this
    /// simplifier cannot create a new >3s active gap. Reaching the Tracker distance
    /// is a best-effort quality goal, not a reason to invent or over-delete GPS data.
    private func denoiseForDistance(
        route: CleanRoute,
        targetDistanceMeters: Double,
        pauses: [TrackerHealthRestorePause],
        activity: ActivityKind
    ) -> CleanRoute {
        guard targetDistanceMeters > 100, route.points.count >= 3 else { return route }
        let upperTarget = targetDistanceMeters + max(120, targetDistanceMeters * 0.10)
        guard route.geometryMeters > upperTarget else { return route }

        let speedLimit = maximumPlausibleSpeed(activity) * 1.15
        var points = route.points
        var current = route

        while current.geometryMeters > upperTarget, points.count >= 3 {
            var bestIndex: Int?
            var bestReduction = 0.0

            for index in 1..<(points.count - 1) {
                let previous = points[index - 1]
                let point = points[index]
                let next = points[index + 1]

                guard next.timestamp - previous.timestamp <= 3.0,
                      !intervalOverlapsPause(previous.timestamp, next.timestamp, pauses: pauses),
                      impliedSpeed(previous, next) <= speedLimit else {
                    continue
                }

                let before = distance(previous, point) + distance(point, next)
                let after = distance(previous, next)
                let reduction = before - after
                guard reduction > 0.25 else { continue }

                let deviation = perpendicularDeviation(point, from: previous, to: next)
                let noiseEnvelope = min(
                    30,
                    max(6, point.horizontalAccuracy * 1.5)
                )
                guard deviation <= noiseEnvelope else { continue }

                if reduction > bestReduction {
                    bestReduction = reduction
                    bestIndex = index
                }
            }

            guard let bestIndex else { break }
            points.remove(at: bestIndex)
            current = makeCleanRoute(source: route.source, points: points, pauses: pauses)
        }

        return current
    }

    private func makeCleanRoute(
        source: String,
        points: [RawPoint],
        pauses: [TrackerHealthRestorePause]
    ) -> CleanRoute {
        let ordered = deduplicate(points)
        let pairs = Array(zip(ordered, ordered.dropFirst()))
        let activePairs = pairs.filter {
            !intervalOverlapsPause($0.0.timestamp, $0.1.timestamp, pauses: pauses)
        }
        let geometry = activePairs.reduce(0.0) {
            $0 + distance($1.0, $1.1)
        }
        let activeGaps = activePairs.compactMap { pair -> Double? in
            let gap = pair.1.timestamp - pair.0.timestamp
            return gap > 0 ? gap : nil
        }
        let accuracies = ordered.map(\.horizontalAccuracy).sorted()
        let p90 = accuracies.isEmpty
            ? 999
            : accuracies[Int(Double(accuracies.count - 1) * 0.90)]

        return CleanRoute(
            source: source,
            points: ordered,
            geometryMeters: geometry,
            activeGapsOver3Seconds: activeGaps.filter { $0 > 3 }.count,
            maxActiveGapSeconds: activeGaps.max() ?? 0,
            p90AccuracyMeters: p90
        )
    }

    private func routeScore(_ route: CleanRoute, summaryMeters: Double) -> Double {
        let geometryPenalty = summaryMeters > 100
            ? min(400, abs(route.geometryMeters - summaryMeters) / 10)
            : 0
        return Double(route.activeGapsOver3Seconds) * 30
            + min(route.maxActiveGapSeconds, 60) * 3
            + route.p90AccuracyMeters
            + geometryPenalty
            + (route.points.count < 100 ? 500 : 0)
    }

    private func maximumPlausibleSpeed(_ activity: ActivityKind) -> Double {
        switch activity {
        case .walking, .hiking: return 5
        case .running, .trackAndField: return 12
        case .cycling, .handCycling: return 25
        default: return 25
        }
    }

    private func counterAgrees(summaryMeters: Double, rawMeters: Double?) -> Bool {
        guard summaryMeters > 100, let rawMeters, rawMeters > 100 else { return false }
        let tolerance = max(150, summaryMeters * 0.12)
        return abs(rawMeters - summaryMeters) <= tolerance
    }

    private func distanceReferenceSource(
        summaryMeters: Double,
        watchRawMeters: Double?,
        phoneRawMeters: Double?
    ) -> String? {
        let watch = counterAgrees(summaryMeters: summaryMeters, rawMeters: watchRawMeters)
        let phone = counterAgrees(summaryMeters: summaryMeters, rawMeters: phoneRawMeters)
        if watch && phone { return "WATCH+IPHONE" }
        if watch { return "WATCH" }
        if phone { return "IPHONE" }
        return nil
    }

    private func hasDistanceConflict(
        summaryMeters: Double,
        watchRawMeters: Double?,
        phoneRawMeters: Double?
    ) -> Bool {
        guard summaryMeters > 100 else { return false }

        // A matching authoritative counter is mandatory. A secondary counter can be
        // partial (as observed on the incident: Watch 2.80 km, iPhone 0.11 km) and
        // must not veto the matching source, but absence of any match blocks writes.
        if counterAgrees(summaryMeters: summaryMeters, rawMeters: watchRawMeters)
            || counterAgrees(summaryMeters: summaryMeters, rawMeters: phoneRawMeters) {
            return false
        }
        return true
    }

    /// Diagnostic warning. HealthKit route geometry is not the workout-distance
    /// authority; the matching raw Tracker counter is. Moderate mismatch stays visible.
    private func hasRouteGeometryConflict(
        summaryMeters: Double,
        route: CleanRoute?
    ) -> Bool {
        guard summaryMeters > 100, let route, route.geometryMeters > 0 else { return false }
        let tolerance = max(220, summaryMeters * 0.15)
        return abs(route.geometryMeters - summaryMeters) > tolerance
    }

    /// Safety gate for the failure observed in Fitness: an old/stale coordinate can
    /// create a large out-and-back detour while the total workout counter remains
    /// correct. Only a large positive excess is blocking; a short route caused by
    /// honest missing GPS remains allowed and is reported by continuity diagnostics.
    private func hasSevereRouteCounterConflict(
        summaryMeters: Double,
        route: CleanRoute?
    ) -> Bool {
        guard summaryMeters > 100, let route, route.geometryMeters > 0 else { return false }
        let toleratedExcess = max(350, summaryMeters * 0.20)
        return route.geometryMeters - summaryMeters > toleratedExcess
    }

    /// Diagnostic only. A real capture hole is preserved instead of interpolated.
    /// It remains visible in audit/telemetry but does not invalidate a route whose
    /// distance is independently confirmed by an authoritative raw counter.
    private func hasRouteContinuityConflict(_ route: CleanRoute?) -> Bool {
        guard let route else { return false }
        return route.maxActiveGapSeconds > 20
    }

    private func deduplicate(_ points: [RawPoint]) -> [RawPoint] {
        var seen = Set<String>()
        return points.sorted { $0.timestamp < $1.timestamp }.filter { point in
            let key = String(
                format: "%.3f|%.6f|%.6f",
                point.timestamp,
                point.latitude,
                point.longitude
            )
            return seen.insert(key).inserted
        }
    }

    private func isPaused(_ timestamp: TimeInterval, pauses: [TrackerHealthRestorePause]) -> Bool {
        pauses.contains { timestamp >= $0.startedAt && timestamp <= $0.endedAt }
    }

    private func intervalOverlapsPause(
        _ start: TimeInterval,
        _ end: TimeInterval,
        pauses: [TrackerHealthRestorePause]
    ) -> Bool {
        pauses.contains { start <= $0.endedAt && end >= $0.startedAt }
    }

    private func impliedSpeed(_ a: RawPoint, _ b: RawPoint) -> Double {
        let delta = b.timestamp - a.timestamp
        guard delta > 0 else { return .infinity }
        return distance(a, b) / delta
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

    private func perpendicularDeviation(
        _ point: RawPoint,
        from start: RawPoint,
        to end: RawPoint
    ) -> Double {
        let a = distance(start, point)
        let b = distance(point, end)
        let c = distance(start, end)
        guard c > 0.5 else { return min(a, b) }
        let semiperimeter = (a + b + c) / 2
        let squaredArea = max(
            0,
            semiperimeter
                * (semiperimeter - a)
                * (semiperimeter - b)
                * (semiperimeter - c)
        )
        return 2 * sqrt(squaredArea) / c
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
        var openPause: TimeInterval?
        for (rawTimestamp, pause) in marks {
            let timestamp = min(max(rawTimestamp, start), end)
            if pause {
                if openPause == nil { openPause = timestamp }
            } else if let pauseStart = openPause, timestamp > pauseStart {
                result.append(
                    TrackerHealthRestorePause(startedAt: pauseStart, endedAt: timestamp)
                )
                openPause = nil
            }
        }
        if let pauseStart = openPause, end > pauseStart {
            result.append(TrackerHealthRestorePause(startedAt: pauseStart, endedAt: end))
        }
        return result
    }

    // MARK: - HealthKit creation

    private struct CreatedWorkout {
        let workout: HKWorkout
        let route: HKWorkoutRoute
    }

    private func createHistoricalWorkout(
        payload: TrackerHealthRestorePayload,
        summary: TrackerSummary,
        activity: ActivityKind,
        route: CleanRoute,
        attemptID: String,
        perceivedEffort: Int?
    ) async throws -> CreatedWorkout {
        let startDate = Date(timeIntervalSince1970: payload.startedAt)
        let endDate = Date(timeIntervalSince1970: payload.endedAt)
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activity.healthKitType
        configuration.locationType = .outdoor
        let builder = HKWorkoutBuilder(
            healthStore: healthStore,
            configuration: configuration,
            device: nil
        )
        let sampleMetadata = generatedMetadata(
            sessionID: payload.sessionID,
            attemptID: attemptID
        )

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
                "com.rzbck.watchsensorlab.route_filter_strategy":
                    "trusted_counter_outlier_rejection_counter_bounded_true_raw_gap_fill_no_interpolation",
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
            try await add(
                makeSamples(
                    payload: payload,
                    activity: activity,
                    route: route,
                    metadata: sampleMetadata
                ),
                to: builder
            )
            let events = makeEvents(payload: payload, attemptID: attemptID)
            if !events.isEmpty { try await add(events, to: builder) }
            try await end(builder, at: endDate)
            guard let workout = try await finish(builder) else {
                throw V4Error.operation("HealthKit n’a pas retourné le workout v4")
            }
            createdWorkout = workout

            let locations = route.points.map { point in
                CLLocation(
                    coordinate: CLLocationCoordinate2D(
                        latitude: point.latitude,
                        longitude: point.longitude
                    ),
                    altitude: point.altitude,
                    horizontalAccuracy: point.horizontalAccuracy,
                    verticalAccuracy: point.verticalAccuracy,
                    course: -1,
                    speed: point.nativeSpeed.map { ($0 >= 0 && $0 < 100) ? $0 : -1 } ?? -1,
                    timestamp: Date(timeIntervalSince1970: point.timestamp)
                )
            }
            let savedRoute = try await finishIndependentRoute(
                workout: workout,
                locations: locations,
                metadata: routeMetadata(
                    sessionID: payload.sessionID,
                    schema: payload.schema,
                    attemptID: attemptID,
                    sourceName: route.source
                )
            )
            createdRoute = savedRoute
            createdEffort = try await savePerceivedEffort(
                workout: workout,
                perceivedEffort: perceivedEffort,
                metadata: sampleMetadata
            )
            return CreatedWorkout(workout: workout, route: savedRoute)
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
                try? await delete(
                    Array(Dictionary(grouping: rollback, by: \.uuid).values.compactMap(\.first))
                )
            }
            throw error
        }
    }

    private func makeSamples(
        payload: TrackerHealthRestorePayload,
        activity: ActivityKind,
        route: CleanRoute,
        metadata: [String: Any]
    ) throws -> [HKSample] {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            throw V4Error.operation("type fréquence cardiaque indisponible")
        }
        var samples: [HKSample] = payload.heartRates.compactMap { point in
            guard point.bpm > 0,
                  point.bpm < 260,
                  point.timestamp >= payload.startedAt,
                  point.timestamp <= payload.endedAt else {
                return nil
            }
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
        if let energy = payload.activeEnergyKcal,
           energy > 0,
           let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            samples.append(
                HKQuantitySample(
                    type: type,
                    quantity: HKQuantity(unit: .kilocalorie(), doubleValue: energy),
                    start: start,
                    end: end,
                    metadata: metadata
                )
            )
        }
        if let identifier = distanceIdentifier(for: activity),
           payload.distanceMeters > 0,
           let type = HKQuantityType.quantityType(forIdentifier: identifier) {
            samples.append(
                HKQuantitySample(
                    type: type,
                    quantity: HKQuantity(unit: .meter(), doubleValue: payload.distanceMeters),
                    start: start,
                    end: end,
                    metadata: metadata
                )
            )
        }
        if let identifier = speedIdentifier(for: activity),
           let type = HKQuantityType.quantityType(forIdentifier: identifier) {
            let unit = HKUnit.meter().unitDivided(by: .second())
            for point in route.points {
                guard let speed = point.nativeSpeed, speed >= 0, speed < 100 else { continue }
                let date = Date(timeIntervalSince1970: point.timestamp)
                samples.append(
                    HKQuantitySample(
                        type: type,
                        quantity: HKQuantity(unit: unit, doubleValue: speed),
                        start: date,
                        end: date,
                        metadata: metadata
                    )
                )
            }
        }
        return samples
    }

    private func makeEvents(
        payload: TrackerHealthRestorePayload,
        attemptID: String
    ) -> [HKWorkoutEvent] {
        let metadata: [String: Any] = [
            rawRestoreKey: true,
            generationKey: generation,
            attemptKey: attemptID,
        ]
        var result: [HKWorkoutEvent] = []
        for pause in payload.pauses.sorted(by: { $0.startedAt < $1.startedAt }) {
            guard pause.startedAt >= payload.startedAt,
                  pause.endedAt > pause.startedAt,
                  pause.endedAt <= payload.endedAt else { continue }
            result.append(
                HKWorkoutEvent(
                    type: .pause,
                    dateInterval: DateInterval(
                        start: Date(timeIntervalSince1970: pause.startedAt),
                        duration: 0
                    ),
                    metadata: metadata
                )
            )
            if pause.endedAt < payload.endedAt - 0.05 {
                result.append(
                    HKWorkoutEvent(
                        type: .resume,
                        dateInterval: DateInterval(
                            start: Date(timeIntervalSince1970: pause.endedAt),
                            duration: 0
                        ),
                        metadata: metadata
                    )
                )
            }
        }
        return result
    }

    private func finishIndependentRoute(
        workout: HKWorkout,
        locations: [CLLocation],
        metadata: [String: Any]
    ) async throws -> HKWorkoutRoute {
        guard locations.count >= 2 else { throw V4Error.operation("route v4 insuffisante") }
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
                if let error { continuation.resume(throwing: error) }
                else if let route { continuation.resume(returning: route) }
                else { continuation.resume(throwing: V4Error.operation("route HealthKit v4 absente")) }
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
            throw V4Error.operation("type effort HealthKit indisponible")
        }
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(
                unit: .appleEffortScore(),
                doubleValue: Double(perceivedEffort)
            ),
            start: workout.startDate,
            end: workout.endDate,
            metadata: metadata
        )
        try await save(sample)
        let related = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Bool, any Error>) in
            healthStore.relateWorkoutEffortSample(
                sample,
                with: workout,
                activity: workout.workoutActivities.first
            ) { success, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: success) }
            }
        }
        guard related else { throw V4Error.operation("association effort/workout refusée") }
        return sample
    }

    // MARK: - Durable verification

    private func verifyDurably(
        payload: TrackerHealthRestorePayload,
        summary: TrackerSummary,
        activity: ActivityKind,
        route: CleanRoute,
        workoutUUID: UUID,
        routeUUID: UUID,
        attemptID: String,
        perceivedEffort: Int?
    ) async throws {
        let delays: [UInt64] = [0, 1_200_000_000, 3_000_000_000]
        for delay in delays {
            if delay > 0 { try await Task.sleep(nanoseconds: delay) }
            try await verifyOnce(
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

    private func verifyOnce(
        payload: TrackerHealthRestorePayload,
        summary: TrackerSummary,
        activity: ActivityKind,
        route: CleanRoute,
        workoutUUID: UUID,
        routeUUID: UUID,
        attemptID: String,
        perceivedEffort: Int?
    ) async throws {
        let workouts = try await managedWorkouts(sessionID: payload.sessionID, summary: summary)
        let generated = workouts.filter { isGenerated($0, sessionID: payload.sessionID) }
        guard generated.count == 1,
              let workout = generated.first,
              workout.uuid == workoutUUID,
              workout.workoutActivityType == activity.healthKitType,
              (workout.metadata?[generationKey] as? String) == generation,
              (workout.metadata?[attemptKey] as? String) == attemptID else {
            throw V4Error.operation("unicité/identité du workout v4 non vérifiée")
        }

        let durationTolerance = max(20, payload.activeDuration * 0.04)
        guard abs(workout.duration - payload.activeDuration) <= durationTolerance else {
            throw V4Error.operation("durée active v4 incohérente")
        }
        try HistoricalHealthKitFullFidelity.verifyWorkoutMetadata(
            workout: workout,
            summary: summary
        )

        let generatedSamples = try await generatedQuantitySamples(
            sessionID: payload.sessionID,
            summary: summary,
            attemptID: attemptID
        )
        try verifyQuantitySamples(
            generatedSamples,
            payload: payload,
            activity: activity,
            route: route
        )

        let savedRoutes = try await routes(for: workout)
        guard savedRoutes.count == 1,
              let savedRoute = savedRoutes.first,
              savedRoute.uuid == routeUUID,
              (savedRoute.metadata?[generationKey] as? String) == generation,
              (savedRoute.metadata?[attemptKey] as? String) == attemptID else {
            throw V4Error.operation("route v4 non associée de façon unique")
        }
        let locations = try await loadLocations(for: savedRoute)
        guard locations.count >= max(2, Int(Double(route.points.count) * 0.95)) else {
            throw V4Error.operation("points GPS v4 manquants après relecture")
        }

        if let perceivedEffort,
           (1...10).contains(perceivedEffort),
           #available(iOS 18.0, *) {
            let samples = try await effortSamples(for: workout)
                .compactMap { $0 as? HKQuantitySample }
            let unit = HKUnit.appleEffortScore()
            guard samples.contains(where: {
                ($0.metadata?[attemptKey] as? String) == attemptID
                    && abs($0.quantity.doubleValue(for: unit) - Double(perceivedEffort)) < 0.01
            }) else {
                throw V4Error.operation("effort Apple v4 non relu comme relation du workout")
            }
        }
    }

    private func verifyQuantitySamples(
        _ samples: [HKSample],
        payload: TrackerHealthRestorePayload,
        activity: ActivityKind,
        route: CleanRoute
    ) throws {
        if let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            let count = samples.compactMap { $0 as? HKQuantitySample }
                .filter { $0.quantityType == heartRateType }
                .count
            guard count >= max(1, Int(Double(payload.heartRates.count) * 0.90)) else {
                throw V4Error.operation("fréquence cardiaque v4 incomplète après relecture")
            }
        }

        if let identifier = distanceIdentifier(for: activity),
           let distanceType = HKQuantityType.quantityType(forIdentifier: identifier),
           payload.distanceMeters > 0 {
            let meters = samples.compactMap { $0 as? HKQuantitySample }
                .filter { $0.quantityType == distanceType }
                .reduce(0.0) { $0 + $1.quantity.doubleValue(for: .meter()) }
            let tolerance = max(15, payload.distanceMeters * 0.04)
            guard abs(meters - payload.distanceMeters) <= tolerance else {
                throw V4Error.operation("distance v4 incomplète après relecture")
            }
        }

        if let energy = payload.activeEnergyKcal,
           energy > 0,
           let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            let kcal = samples.compactMap { $0 as? HKQuantitySample }
                .filter { $0.quantityType == energyType }
                .reduce(0.0) { $0 + $1.quantity.doubleValue(for: .kilocalorie()) }
            let tolerance = max(2, energy * 0.05)
            guard abs(kcal - energy) <= tolerance else {
                throw V4Error.operation("énergie v4 incomplète après relecture")
            }
        }

        if let identifier = speedIdentifier(for: activity),
           let speedType = HKQuantityType.quantityType(forIdentifier: identifier) {
            let expected = route.points.filter {
                guard let speed = $0.nativeSpeed else { return false }
                return speed >= 0 && speed < 100
            }.count
            if expected > 0 {
                let actual = samples.compactMap { $0 as? HKQuantitySample }
                    .filter { $0.quantityType == speedType }
                    .count
                guard actual >= max(1, Int(Double(expected) * 0.90)) else {
                    throw V4Error.operation("vitesse v4 incomplète après relecture")
                }
            }
        }
    }

    // MARK: - HealthKit queries / authorization / cleanup

    private func managedWorkouts(
        sessionID: String,
        summary: TrackerSummary
    ) async throws -> [HKWorkout] {
        let predicate = HKQuery.predicateForSamples(
            withStart: summary.startedAt.addingTimeInterval(-120),
            end: summary.endedAt.addingTimeInterval(120),
            options: []
        )
        let samples = try await querySamples(
            type: HKObjectType.workoutType(),
            predicate: predicate
        )
        return (samples as? [HKWorkout] ?? []).filter {
            ($0.metadata?[managedKey] as? Bool) == true
                && ($0.metadata?[sessionKey] as? String) == sessionID
        }
    }

    private func isGenerated(_ workout: HKWorkout, sessionID: String) -> Bool {
        (workout.metadata?[rawRestoreKey] as? Bool) == true
            && (workout.metadata?[sessionKey] as? String) == sessionID
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
        guard let type = HKQuantityType.quantityType(forIdentifier: .workoutEffortScore) else {
            return []
        }
        var predicates = [
            HKQuery.predicateForWorkoutEffortSamplesRelated(
                workout: workout,
                activity: nil
            )
        ]
        predicates.append(contentsOf: workout.workoutActivities.map {
            HKQuery.predicateForWorkoutEffortSamplesRelated(
                workout: workout,
                activity: $0
            )
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
        attemptID: String?
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
            result.append(contentsOf: try await querySamples(type: type, predicate: predicate).filter {
                guard ($0.metadata?[rawRestoreKey] as? Bool) == true,
                      ($0.metadata?[sessionKey] as? String) == sessionID else {
                    return false
                }
                return attemptID == nil
                    || ($0.metadata?[attemptKey] as? String) == attemptID
            })
        }
        return Array(Dictionary(grouping: result, by: \.uuid).values.compactMap(\.first))
    }

    private func requestCleanupAuthorization() async throws {
        var shareTypes: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
        ]
        for identifier: HKQuantityTypeIdentifier in [
            .heartRate,
            .activeEnergyBurned,
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
            .cyclingSpeed,
            .runningSpeed,
        ] {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                shareTypes.insert(type)
            }
        }
        if #available(iOS 18.0, *),
           let effort = HKQuantityType.quantityType(forIdentifier: .workoutEffortScore) {
            shareTypes.insert(effort)
        }
        try await requestAndVerifyAuthorization(shareTypes)
    }

    private func requestRepairAuthorization(
        activity: ActivityKind,
        hasEnergy: Bool,
        hasSpeed: Bool,
        perceivedEffort: Int?
    ) async throws {
        var shareTypes: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
        ]
        if let type = HKQuantityType.quantityType(forIdentifier: .heartRate) {
            shareTypes.insert(type)
        }
        if hasEnergy,
           let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            shareTypes.insert(type)
        }
        if let identifier = distanceIdentifier(for: activity),
           let type = HKQuantityType.quantityType(forIdentifier: identifier) {
            shareTypes.insert(type)
        }
        if hasSpeed,
           let identifier = speedIdentifier(for: activity),
           let type = HKQuantityType.quantityType(forIdentifier: identifier) {
            shareTypes.insert(type)
        }
        if perceivedEffort != nil,
           #available(iOS 18.0, *),
           let type = HKQuantityType.quantityType(forIdentifier: .workoutEffortScore) {
            shareTypes.insert(type)
        }
        try await requestAndVerifyAuthorization(shareTypes)
    }

    private func requestAndVerifyAuthorization(
        _ shareTypes: Set<HKSampleType>
    ) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw V4Error.operation("HealthKit indisponible")
        }
        let readTypes = Set<HKObjectType>(shareTypes.map { $0 as HKObjectType })
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            healthStore.requestAuthorization(
                toShare: shareTypes,
                read: readTypes
            ) { success, error in
                if let error { continuation.resume(throwing: error) }
                else if !success {
                    continuation.resume(
                        throwing: V4Error.operation("autorisation Santé incomplète")
                    )
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
        for type in shareTypes {
            guard healthStore.authorizationStatus(for: type) == .sharingAuthorized else {
                throw V4Error.operation(
                    "écriture Santé non autorisée pour \(type.identifier)"
                )
            }
        }
    }

    // MARK: - Shared helpers

    private func loadSummary(sessionID: String) throws -> TrackerSummary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            TrackerSummary.self,
            from: Data(
                contentsOf: try sessionDirectory(sessionID: sessionID)
                    .appendingPathComponent("summary.json")
            )
        )
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
            throw V4Error.operation("session Tracker locale absente")
        }
        return directory
    }

    private func loadJSONL(_ url: URL) throws -> [[String: Any]] {
        try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                guard let data = String(line).data(using: .utf8) else { return nil }
                return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
    }

    private func makePayload(
        sessionID: String,
        targetActivity: ActivityKind
    ) throws -> TrackerHealthRestorePayload {
        let url = try packetBuilder.makeTransferFile(
            sessionID: sessionID,
            targetActivity: targetActivity
        )
        defer { try? FileManager.default.removeItem(at: url) }
        return try JSONDecoder().decode(
            TrackerHealthRestorePayload.self,
            from: Data(contentsOf: url)
        )
    }

    private func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? Double { return value }
        return nil
    }

    private func generatedMetadata(
        sessionID: String,
        attemptID: String
    ) -> [String: Any] {
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

    private func distanceIdentifier(
        for activity: ActivityKind
    ) -> HKQuantityTypeIdentifier? {
        switch activity {
        case .cycling, .handCycling: return .distanceCycling
        case .swimming, .waterFitness, .waterPolo: return .distanceSwimming
        case .walking, .running, .hiking, .trackAndField: return .distanceWalkingRunning
        default: return nil
        }
    }

    private func speedIdentifier(
        for activity: ActivityKind
    ) -> HKQuantityTypeIdentifier? {
        switch activity {
        case .cycling, .handCycling: return .cyclingSpeed
        case .running, .trackAndField: return .runningSpeed
        default: return nil
        }
    }

    private func querySamples(
        type: HKSampleType,
        predicate: NSPredicate?
    ) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: samples ?? [])
                }
            }
            healthStore.execute(query)
        }
    }

    private func loadLocations(for route: HKWorkoutRoute) async throws -> [CLLocation] {
        try await withCheckedThrowingContinuation { continuation in
            var result: [CLLocation] = []
            let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                result.append(contentsOf: locations ?? [])
                if done { continuation.resume(returning: result) }
            }
            healthStore.execute(query)
        }
    }

    private func begin(_ builder: HKWorkoutBuilder, at date: Date) async throws {
        try await checked {
            completion in builder.beginCollection(withStart: date, completion: completion)
        }
    }

    private func end(_ builder: HKWorkoutBuilder, at date: Date) async throws {
        try await checked {
            completion in builder.endCollection(withEnd: date, completion: completion)
        }
    }

    private func addMetadata(
        _ metadata: [String: Any],
        to builder: HKWorkoutBuilder
    ) async throws {
        try await checked {
            completion in builder.addMetadata(metadata, completion: completion)
        }
    }

    private func add(
        _ samples: [HKSample],
        to builder: HKWorkoutBuilder
    ) async throws {
        try await checked {
            completion in builder.add(samples, completion: completion)
        }
    }

    private func add(
        _ events: [HKWorkoutEvent],
        to builder: HKWorkoutBuilder
    ) async throws {
        try await checked {
            completion in builder.addWorkoutEvents(events, completion: completion)
        }
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
        try await checked {
            completion in healthStore.save(object, withCompletion: completion)
        }
    }

    private func delete(_ objects: [HKObject]) async throws {
        guard !objects.isEmpty else { return }
        try await checked {
            completion in healthStore.delete(objects, withCompletion: completion)
        }
    }

    private func checked(
        _ operation: (@escaping (Bool, Error?) -> Void) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            operation { success, error in
                if let error { continuation.resume(throwing: error) }
                else if !success {
                    continuation.resume(
                        throwing: V4Error.operation("opération HealthKit refusée")
                    )
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private enum V4Error: LocalizedError {
        case operation(String)

        var errorDescription: String? {
            switch self {
            case .operation(let value): return value
            }
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
                    ContentUnavailableView(
                        "Aucune séance Tracker",
                        systemImage: "checkmark.circle.fill"
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 7) {
                                Label("Récupération Santé v4", systemImage: "shield.checkered")
                                    .font(.headline.weight(.bold))
                                Text(
                                    "Diagnostic Watch + iPhone d’abord. Aucun nouvel exercice n’est créé tant qu’une restauration de test existe. Le nettoyage cible seulement cette session et ne touche jamais les raw Tracker."
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(
                                .orange.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 18)
                            )

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
            .onAppear {
                summaries = store.listSummaries().sorted { $0.startedAt > $1.startedAt }
            }
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

    private var audit: HistoricalHealthKitRepairV4Coordinator.Audit? {
        coordinator.auditBySession[summary.sessionID]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ActivityKind(rawValue: summary.activity)?.label ?? summary.activity)
                        .font(.headline.weight(.bold))
                    Text(
                        summary.startedAt,
                        format: .dateTime.day().month().year().hour().minute()
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text(summary.sessionID)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if coordinator.internallyVerifiedSessions.contains(summary.sessionID) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 12) {
                metric(v4Distance(summary.distanceMeters), "Résumé")
                metric(audit.map { "\($0.watchRawPoints)" } ?? "—", "GPS Watch")
                metric(audit.map { "\($0.phoneRawPoints)" } ?? "—", "GPS iPhone")
            }

            if let audit {
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        "Route : \(audit.chosenSource ?? "aucune") · \(audit.chosenPoints) points · \(v4Distance(audit.selectedGeometryMeters)) actifs"
                    )
                    Text(
                        String(
                            format: "Géométrie W %.2f km · iPhone %.2f km",
                            audit.watchGeometryMeters / 1000,
                            audit.phoneGeometryMeters / 1000
                        )
                    )
                    if let value = audit.watchRawDistanceMeters {
                        Text(String(format: "Compteur raw Watch %.2f km", value / 1000))
                    }
                    if let value = audit.phoneRawDistanceMeters {
                        Text(String(format: "Compteur raw iPhone %.2f km", value / 1000))
                    }
                    Text("Référence distance : \(audit.distanceReferenceSource ?? "aucune")")
                    Text(
                        "Gaps actifs >3s : \(audit.activeGapsOver3Seconds) · max \(String(format: "%.1f", audit.maxActiveGapSeconds))s"
                    )
                    Text("Restaurations HealthKit : \(audit.generatedWorkoutCount)")
                    if let rawType = audit.generatedWorkoutActivityTypeRawValue {
                        Text("Type HK restauration : \(rawType) · cible \(audit.generatedTargetActivity ?? "inconnue")")
                    }
                    if let brand = audit.generatedWorkoutBrandName {
                        Text("Brand HK restauration : \(brand)")
                    }
                    if let score = audit.generatedEffortScore {
                        Text(String(format: "Effort Apple relié : %.0f / 10 (%d sample)", score, audit.generatedEffortSampleCount))
                    } else if audit.generatedWorkoutCount > 0 {
                        Text("Effort Apple relié : absent (\(audit.generatedEffortSampleCount) sample)")
                    }
                    if let saved = audit.savedPerceivedEffort {
                        Text("Effort choisi mémorisé : \(saved) / 10")
                    }
                    if audit.distanceConflict {
                        Text("DISTANCE SUMMARY/RAW NON CONFIRMÉE · écriture bloquée")
                            .foregroundStyle(.red)
                    }
                    if audit.severeRouteCounterConflict {
                        Text("ROUTE/COMPTEUR INCOHÉRENTS · détour GPS important · écriture bloquée")
                            .foregroundStyle(.red)
                    }
                    if audit.routeGeometryConflict {
                        Text("QUALITÉ ROUTE · géométrie GPS ≠ distance Tracker · diagnostic visible")
                            .foregroundStyle(.yellow)
                    }
                    if audit.routeContinuityConflict {
                        Text("QUALITÉ ROUTE · trou GPS réel conservé · aucun point inventé · diagnostic non bloquant")
                            .foregroundStyle(.yellow)
                    }
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            Button {
                coordinator.inspect(sessionID: summary.sessionID)
            } label: {
                Label(
                    "Actualiser le diagnostic",
                    systemImage: "waveform.path.ecg.rectangle"
                )
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
                ForEach(ActivityKind.allCases.filter { !$0.isAutomatic }) { activity in
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
            .onChange(of: perceivedEffort) { _, value in
                HistoricalHealthKitFullFidelity.setSavedPerceivedEffort(
                    value,
                    sessionID: summary.sessionID
                )
            }

            Button {
                confirmRepair = true
            } label: {
                Label(
                    "Reconstruire proprement dans Santé",
                    systemImage: "heart.circle.fill"
                )
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
                        status.contains("échoué")
                            || status.contains("bloquée")
                            || status.contains("aucune écriture")
                            ? .red
                            : .secondary
                    )
            }
        }
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
        .onAppear {
            if perceivedEffort == nil {
                perceivedEffort = HistoricalHealthKitFullFidelity.savedPerceivedEffort(
                    sessionID: summary.sessionID
                )
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
            Text(
                "Le filtre exige raw_restoration=true + le session ID exact. Les raw Tracker et les workouts normaux restent intacts."
            )
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
            Text(
                "La reconstruction exige une distance raw confirmée, une route sans détour majeur et zéro restauration existante. Les trous GPS réels restent visibles et ne sont jamais interpolés."
            )
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func v4Distance(_ meters: Double) -> String {
    meters >= 1000
        ? String(format: "%.2f km", meters / 1000)
        : String(format: "%.0f m", meters)
}
