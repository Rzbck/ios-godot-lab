import CoreLocation
import Foundation
import HealthKit
import SwiftUI

/// Historical reconstruction v4 — final segmented-route candidate.
///
/// Live workouts remain Watch-owned. Historical recovery is iPhone-only.
/// The recovery path never edits Tracker raw files and never overwrites a normal workout.
///
/// Route policy:
/// - Tracker summary distance is compared independently with Watch/iPhone raw counters;
/// - the matching Watch counter remains the scalar distance authority for this incident;
/// - route selection deliberately returns to the richer pre-reacquisition-filter path;
/// - local noise filtering may remove only small accuracy-scale wobble;
/// - secondary GPS may fill only holes that were already absent in the raw primary stream;
/// - no coordinate is fabricated or interpolated;
/// - one physically impossible connector is represented as a HealthKit route boundary,
///   not as a straight line and not by deleting the rest of a valid segment;
/// - distance/energy totals are written only across ACTIVE intervals so HealthKit does
///   not prorate a wall-time sample across long pause intervals;
/// - perceived effort is related at workout level (`activity: nil`) for a single-sport workout;
/// - every generated object is reread before internal verification, which is still not
///   a substitute for physical validation in Apple Health/Fitness.
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

    let healthStore = HKHealthStore()
    let packetBuilder = TrackerHealthRestorePacketBuilder()

    let managedKey = "com.rzbck.watchsensorlab.managed"
    let sessionKey = "com.rzbck.watchsensorlab.session_id"
    let rawRestoreKey = "com.rzbck.watchsensorlab.raw_restoration"
    let rawRestoreSchemaKey = "com.rzbck.watchsensorlab.raw_restoration_schema"
    let rawRestoreSourceKey = "com.rzbck.watchsensorlab.raw_restoration_source"
    let correctionTargetKey = "com.rzbck.watchsensorlab.correction_target_activity"
    let masterActivityKey = "com.rzbck.watchsensorlab.master_activity"
    let algorithmKey = "com.rzbck.watchsensorlab.algorithm_version"
    let buildKey = "com.rzbck.watchsensorlab.build_sha"
    let generationKey = "com.rzbck.watchsensorlab.historical_generation"
    let attemptKey = "com.rzbck.watchsensorlab.historical_attempt_id"

    let generation = "ios_historical_v4_segmented_route"
    let source = "tracker_raw_ios_v4_segmented_route"

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
                let choice = chooseRoute(
                    raw: raw,
                    summaryDistanceMeters: summary.distanceMeters,
                    activity: .other
                )
                let selectedSegments = choice.selected.map {
                    segmentRouteForHealthKit(route: $0, pauses: raw.pauses, activity: .other)
                } ?? []
                let selectedGeometry = segmentedGeometry(selectedSegments)

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
                    renderedGeometryMeters: selectedGeometry
                )
                let continuityConflict = hasRouteContinuityConflict(choice.selected)
                let severeCounterConflict = hasSevereRouteCounterConflict(
                    summaryMeters: summary.distanceMeters,
                    renderedGeometryMeters: selectedGeometry
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
                    selectedGeometryMeters: selectedGeometry,
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
                    let sourceBundle = generatedWorkout?.sourceRevision.source.bundleIdentifier ?? "source inconnue"
                    let renderedDistance = generatedWorkout.flatMap {
                        workoutDistanceMeters($0, activity: ActivityKind(healthKitType: $0.workoutActivityType) ?? .other)
                    }
                    let renderedText = renderedDistance.map { String(format: "%.2f km", $0 / 1000) } ?? "distance HK inconnue"
                    statusBySession[sessionID] =
                        "\(generated.count) restauration(s) de test détectée(s) · \(renderedText) · source \(sourceBundle) · nettoyage requis avant tout nouvel essai."
                } else if conflict {
                    statusBySession[sessionID] =
                        "Aucun compteur raw fiable ne confirme la distance du résumé · aucune écriture Santé."
                } else if severeCounterConflict {
                    statusBySession[sessionID] =
                        "Route segmentée contient encore une géométrie incompatible avec le compteur Tracker · écriture bloquée."
                } else if choice.selected == nil || selectedSegments.isEmpty {
                    statusBySession[sessionID] = "Aucune route GPS sûre après analyse Watch + iPhone."
                } else if let selected = choice.selected {
                    let warning = (geometryConflict || continuityConflict)
                        ? " · avertissement qualité route conservé (diagnostic non bloquant, aucun point inventé)"
                        : ""
                    statusBySession[sessionID] =
                        "Diagnostic prêt · route \(selected.source), \(selected.points.count) points, \(selectedSegments.count) segment(s) HK\(warning) · aucune écriture Santé."
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
        statusBySession[sessionID] = "Préflight v4 segmenté Watch + iPhone…"

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
                let routeSegments = segmentRouteForHealthKit(
                    route: selectedRoute,
                    pauses: raw.pauses,
                    activity: targetActivity
                )
                guard !routeSegments.isEmpty else {
                    throw V4Error.operation("aucun segment GPS HealthKit sûr")
                }
                guard !hasSevereRouteCounterConflict(
                    summaryMeters: summary.distanceMeters,
                    renderedGeometryMeters: segmentedGeometry(routeSegments)
                ) else {
                    throw V4Error.operation(
                        "route GPS segmentée contient encore un détour incompatible avec le compteur Tracker"
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
                    routeSegments: routeSegments,
                    attemptID: attemptID,
                    perceivedEffort: perceivedEffort
                )

                statusBySession[sessionID] = "Relectures HealthKit v4 segmentées…"
                try await verifyDurably(
                    payload: payload,
                    summary: summary,
                    activity: targetActivity,
                    route: selectedRoute,
                    routeSegments: routeSegments,
                    workoutUUID: created.workout.uuid,
                    routeUUIDs: Set(created.routes.map(\.uuid)),
                    attemptID: attemptID,
                    perceivedEffort: perceivedEffort
                )

                internallyVerifiedSessions.insert(sessionID)
                auditBySession.removeValue(forKey: sessionID)
                statusBySession[sessionID] =
                    "HealthKit v4 segmenté écrit et relu · une seule restauration · PAS encore validé dans Santé/Forme."
            } catch {
                statusBySession[sessionID] = "Reconstruction v4 échouée · \(error.localizedDescription)"
            }
        }
    }

}
