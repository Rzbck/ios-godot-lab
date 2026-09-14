import CoreLocation
import Foundation
import HealthKit
import SwiftUI

/// Recovery path for a Tracker-managed HealthKit workout whose local Tracker session
/// files no longer exist on the iPhone (for example after a sideload reinstall).
///
/// The source workout is never deleted while creating the candidate. The user supplies
/// a scalar-distance authority from a prior forensic export; the existing HealthKit route
/// is reused only as geometry evidence. Finalization is a separate explicit action.
@MainActor
final class HistoricalHealthKitOrphanRepairCoordinator: ObservableObject {
    static let shared = HistoricalHealthKitOrphanRepairCoordinator()

    struct Inspection: Equatable {
        let sessionID: String
        let sourceUUID: UUID
        let sourceActivity: ActivityKind
        let sourceDistanceMeters: Double
        let startedAt: Date
        let endedAt: Date
        let routeCount: Int
        let routePointCount: Int
        let routeGeometryMeters: Double
        let heartRateSampleCount: Int
        let activeEnergySampleCount: Int
        let sourceEffort: Int?
        let candidateUUID: UUID?
        let candidateVerified: Bool
    }

    @Published var sessionID = ""
    @Published var authoritativeDistanceText = ""
    @Published var targetActivity: ActivityKind = .cycling
    @Published var perceivedEffort: Int?
    @Published private(set) var inspection: Inspection?
    @Published private(set) var status = ""
    @Published private(set) var busy = false

    private let base = HistoricalHealthKitRepairV4Coordinator.shared

    private let forensicKey = "com.rzbck.watchsensorlab.forensic_correction"
    private let forensicSourceUUIDKey = "com.rzbck.watchsensorlab.forensic_source_uuid"
    private let forensicDistanceKey = "com.rzbck.watchsensorlab.forensic_distance_m"
    private let forensicSourceDistanceKey = "com.rzbck.watchsensorlab.forensic_source_distance_m"
    private let forensicSourceGeometryKey = "com.rzbck.watchsensorlab.forensic_source_geometry_m"
    private let forensicEvidenceKey = "com.rzbck.watchsensorlab.forensic_evidence_source"
    private let generation = "ios_historical_orphan_v1"
    private let sourceSampleUUIDKey = "com.rzbck.watchsensorlab.source_sample_uuid"

    private init() {}

    var candidateReady: Bool {
        inspection?.candidateVerified == true
    }

    var parsedAuthorityDistance: Double? {
        let normalized = authoritativeDistanceText
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(normalized), value > 0 else { return nil }
        return value
    }

    func inspect() {
        guard !busy else { return }
        let session = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !session.isEmpty else {
            status = "Session ID requis."
            return
        }
        guard let authority = parsedAuthorityDistance else {
            status = "Distance d’autorité invalide."
            return
        }

        busy = true
        status = "Inspection HealthKit orpheline · aucune écriture…"

        Task {
            defer { busy = false }
            do {
                let result = try await inspectNow(
                    sessionID: session,
                    authorityDistance: authority,
                    targetActivity: targetActivity,
                    requestedEffort: perceivedEffort
                )
                inspection = result
                if perceivedEffort == nil, let sourceEffort = result.sourceEffort {
                    perceivedEffort = sourceEffort
                }
                status = result.candidateVerified
                    ? "Candidat orphelin relu · source originale conservée · valide physiquement dans Santé/Forme."
                    : "Source HealthKit cohérente avec la preuve externe · prête pour création du candidat · aucune écriture effectuée."
            } catch {
                inspection = nil
                status = "Inspection bloquée · \(error.localizedDescription)"
            }
        }
    }

    func createCandidate() {
        guard !busy else { return }
        let session = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let authority = parsedAuthorityDistance else {
            status = "Distance d’autorité invalide."
            return
        }

        busy = true
        status = "Création du candidat HealthKit · source originale conservée…"

        Task {
            defer { busy = false }
            var createdWorkout: HKWorkout?
            var createdRoutes: [HKWorkoutRoute] = []
            var createdEffort: HKQuantitySample?

            do {
                let preflight = try await sourceSnapshot(
                    sessionID: session,
                    authorityDistance: authority,
                    targetActivity: targetActivity
                )
                guard preflight.candidate == nil else {
                    throw HistoricalHealthKitRepairV4Coordinator.V4Error.operation(
                        "un candidat orphelin existe déjà ; inspecte-le avant tout nouvel essai"
                    )
                }

                try await base.requestCleanupAuthorization()

                let attemptID = UUID().uuidString
                let metadata = candidateMetadata(
                    sessionID: session,
                    source: preflight.source,
                    authorityDistance: authority,
                    sourceDistance: preflight.sourceDistance,
                    sourceGeometry: preflight.routeGeometry,
                    attemptID: attemptID,
                    targetActivity: targetActivity
                )

                let sourceSamples = try await associatedQuantitySamples(for: preflight.source)
                let clonedSamples = try cloneNonDistanceSamples(
                    sourceSamples,
                    sessionID: session,
                    attemptID: attemptID
                )
                let intervals = activeIntervals(
                    start: preflight.source.startDate,
                    end: preflight.source.endDate,
                    events: preflight.source.workoutEvents ?? []
                )
                let distanceSamples = try makeDistanceSamples(
                    totalMeters: authority,
                    activity: targetActivity,
                    intervals: intervals,
                    sessionID: session,
                    attemptID: attemptID
                )

                let configuration = HKWorkoutConfiguration()
                configuration.activityType = targetActivity.healthKitType
                configuration.locationType = preflight.routeLocations.isEmpty ? .unknown : .outdoor
                let builder = HKWorkoutBuilder(
                    healthStore: base.healthStore,
                    configuration: configuration,
                    device: preflight.source.device
                )

                try await base.begin(builder, at: preflight.source.startDate)
                try await base.addMetadata(metadata, to: builder)

                let candidateSamples = clonedSamples + distanceSamples
                if !candidateSamples.isEmpty {
                    try await base.add(candidateSamples, to: builder)
                }
                let events = preflight.source.workoutEvents ?? []
                if !events.isEmpty {
                    try await base.add(events, to: builder)
                }

                try await base.end(builder, at: preflight.source.endDate)
                guard let workout = try await base.finish(builder) else {
                    throw HistoricalHealthKitRepairV4Coordinator.V4Error.operation(
                        "HealthKit n’a pas retourné le candidat orphelin"
                    )
                }
                createdWorkout = workout

                for (index, locations) in preflight.routeLocations.enumerated() {
                    guard locations.count >= 2 else { continue }
                    let route = try await HistoricalHealthKitFullFidelity.finishIndependentRoute(
                        healthStore: base.healthStore,
                        workout: workout,
                        locations: locations,
                        metadata: [
                            base.managedKey: true,
                            base.sessionKey: session,
                            base.rawRestoreKey: true,
                            base.rawRestoreSourceKey: "healthkit_orphan_existing_route",
                            base.generationKey: generation,
                            base.attemptKey: attemptID,
                            forensicKey: true,
                            forensicSourceUUIDKey: preflight.source.uuid.uuidString,
                            "com.rzbck.watchsensorlab.route_segment_index": index,
                            "com.rzbck.watchsensorlab.route_segment_count": preflight.routeLocations.count,
                        ]
                    )
                    createdRoutes.append(route)
                }
                guard preflight.routeLocations.isEmpty || !createdRoutes.isEmpty else {
                    throw HistoricalHealthKitRepairV4Coordinator.V4Error.operation(
                        "la route source existe mais aucune route candidate n’a été sauvegardée"
                    )
                }

                createdEffort = try await HistoricalHealthKitFullFidelity.savePerceivedEffort(
                    healthStore: base.healthStore,
                    workout: workout,
                    perceivedEffort: perceivedEffort,
                    metadata: [
                        base.rawRestoreKey: true,
                        base.sessionKey: session,
                        base.generationKey: generation,
                        base.attemptKey: attemptID,
                        forensicKey: true,
                    ]
                )

                try await verifyCandidateDurably(
                    sessionID: session,
                    sourceUUID: preflight.source.uuid,
                    candidateUUID: workout.uuid,
                    authorityDistance: authority,
                    targetActivity: targetActivity,
                    sourceRouteCount: preflight.routeLocations.count,
                    sourceRoutePointCount: preflight.routePointCount,
                    sourceRouteGeometry: preflight.routeGeometry,
                    sourceHeartRateUUIDs: preflight.heartRateUUIDs,
                    sourceActiveEnergyUUIDs: preflight.activeEnergyUUIDs,
                    expectedEffort: perceivedEffort,
                    requireSource: true
                )

                inspection = try await inspectNow(
                    sessionID: session,
                    authorityDistance: authority,
                    targetActivity: targetActivity,
                    requestedEffort: perceivedEffort
                )
                status = "Candidat créé et relu · source originale conservée · vérifie maintenant le Vélo dans Santé/Forme avant finalisation."
            } catch {
                var rollback: [HKObject] = []
                if let createdEffort { rollback.append(createdEffort) }
                rollback.append(contentsOf: createdRoutes)
                if let createdWorkout {
                    rollback.append(contentsOf: (try? await associatedQuantitySamples(for: createdWorkout)) ?? [])
                    if #available(iOS 18.0, *) {
                        rollback.append(contentsOf: (try? await base.effortSamples(for: createdWorkout)) ?? [])
                    }
                    rollback.append(createdWorkout)
                }
                let unique = Array(
                    Dictionary(grouping: rollback, by: \.uuid)
                        .values
                        .compactMap(\.first)
                )
                if !unique.isEmpty { try? await base.delete(unique) }
                status = "Création annulée · source originale conservée · \(error.localizedDescription)"
            }
        }
    }

    func cleanupCandidate() {
        guard !busy else { return }
        let session = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !session.isEmpty else { return }

        busy = true
        status = "Nettoyage ciblé du candidat orphelin…"

        Task {
            defer { busy = false }
            do {
                try await base.requestCleanupAuthorization()
                let workouts = try await sessionWorkouts(sessionID: session)
                let candidates = workouts.filter(isCandidate)
                guard !candidates.isEmpty else {
                    status = "Aucun candidat orphelin à nettoyer."
                    return
                }

                var objects: [HKObject] = []
                for candidate in candidates {
                    objects.append(contentsOf: try await base.routes(for: candidate))
                    objects.append(contentsOf: try await associatedQuantitySamples(for: candidate))
                    if #available(iOS 18.0, *) {
                        objects.append(contentsOf: try await base.effortSamples(for: candidate))
                    }
                    objects.append(candidate)
                }
                let unique = Array(
                    Dictionary(grouping: objects, by: \.uuid)
                        .values
                        .compactMap(\.first)
                )
                try await base.delete(unique)

                let remaining = try await sessionWorkouts(sessionID: session)
                guard remaining.contains(where: { !isCandidate($0) }) else {
                    throw HistoricalHealthKitRepairV4Coordinator.V4Error.operation(
                        "la source originale n’est plus visible après nettoyage"
                    )
                }
                guard !remaining.contains(where: isCandidate) else {
                    throw HistoricalHealthKitRepairV4Coordinator.V4Error.operation(
                        "un candidat orphelin subsiste après nettoyage"
                    )
                }

                inspection = nil
                status = "Candidat nettoyé · source originale conservée."
            } catch {
                status = "Nettoyage bloqué · \(error.localizedDescription)"
            }
        }
    }

    func finalize() {
        guard !busy else { return }
        let session = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let authority = parsedAuthorityDistance else {
            status = "Distance d’autorité invalide."
            return
        }

        busy = true
        status = "Relecture finale du candidat avant suppression de la source…"

        Task {
            var sourceDeleted = false
            defer { busy = false }

            do {
                let snapshot = try await sourceSnapshot(
                    sessionID: session,
                    authorityDistance: authority,
                    targetActivity: targetActivity
                )
                guard let candidate = snapshot.candidate else {
                    throw HistoricalHealthKitRepairV4Coordinator.V4Error.operation(
                        "candidat orphelin absent"
                    )
                }

                try await verifyCandidateDurably(
                    sessionID: session,
                    sourceUUID: snapshot.source.uuid,
                    candidateUUID: candidate.uuid,
                    authorityDistance: authority,
                    targetActivity: targetActivity,
                    sourceRouteCount: snapshot.routeLocations.count,
                    sourceRoutePointCount: snapshot.routePointCount,
                    sourceRouteGeometry: snapshot.routeGeometry,
                    sourceHeartRateUUIDs: snapshot.heartRateUUIDs,
                    sourceActiveEnergyUUIDs: snapshot.activeEnergyUUIDs,
                    expectedEffort: perceivedEffort,
                    requireSource: true
                )

                try await base.requestCleanupAuthorization()
                let sourceRoutes = try await base.routes(for: snapshot.source)
                let sourceQuantitySamples = try await associatedQuantitySamples(for: snapshot.source)
                    .filter { sample in
                        guard let quantity = sample as? HKQuantitySample else { return false }
                        if #available(iOS 18.0, *),
                           quantity.quantityType == HKQuantityType.quantityType(forIdentifier: .workoutEffortScore) {
                            return false
                        }
                        return true
                    }
                let sourceEffortSamples: [HKSample]
                if #available(iOS 18.0, *) {
                    sourceEffortSamples = try await base.effortSamples(for: snapshot.source)
                } else {
                    sourceEffortSamples = []
                }

                try await base.delete([snapshot.source])
                sourceDeleted = true

                if !sourceRoutes.isEmpty {
                    try await base.delete(sourceRoutes)
                }
                if !sourceQuantitySamples.isEmpty {
                    try await base.delete(sourceQuantitySamples)
                }
                if !sourceEffortSamples.isEmpty {
                    try await base.delete(sourceEffortSamples)
                }

                try await verifyCandidateDurably(
                    sessionID: session,
                    sourceUUID: snapshot.source.uuid,
                    candidateUUID: candidate.uuid,
                    authorityDistance: authority,
                    targetActivity: targetActivity,
                    sourceRouteCount: snapshot.routeLocations.count,
                    sourceRoutePointCount: snapshot.routePointCount,
                    sourceRouteGeometry: snapshot.routeGeometry,
                    sourceHeartRateUUIDs: snapshot.heartRateUUIDs,
                    sourceActiveEnergyUUIDs: snapshot.activeEnergyUUIDs,
                    expectedEffort: perceivedEffort,
                    requireSource: false
                )

                inspection = try await inspectCandidateOnly(
                    sessionID: session,
                    candidateUUID: candidate.uuid,
                    authorityDistance: authority,
                    targetActivity: targetActivity
                )
                status = "Correction orpheline finalisée côté HealthKit · source normale et ses samples associés supprimés · candidat relu après suppression · vérifie une dernière fois dans Santé/Forme."
            } catch {
                status = sourceDeleted
                    ? "Finalisation incomplète après suppression de la source · \(error.localizedDescription) · aucun nettoyage supplémentaire."
                    : "Finalisation annulée · source originale conservée · \(error.localizedDescription)"
            }
        }
    }

    private struct SourceSnapshot {
        let source: HKWorkout
        let candidate: HKWorkout?
        let sourceDistance: Double
        let routeLocations: [[CLLocation]]
        let routePointCount: Int
        let routeGeometry: Double
        let heartRateUUIDs: Set<UUID>
        let activeEnergyUUIDs: Set<UUID>
        let sourceEffort: Int?
    }

    private func inspectNow(
        sessionID: String,
        authorityDistance: Double,
        targetActivity: ActivityKind,
        requestedEffort: Int?
    ) async throws -> Inspection {
        let snapshot = try await sourceSnapshot(
            sessionID: sessionID,
            authorityDistance: authorityDistance,
            targetActivity: targetActivity
        )

        var verified = false
        if let candidate = snapshot.candidate {
            let candidateEffort = requestedEffort ?? (try await effortValue(for: candidate))
            try await verifyCandidateDurably(
                sessionID: sessionID,
                sourceUUID: snapshot.source.uuid,
                candidateUUID: candidate.uuid,
                authorityDistance: authorityDistance,
                targetActivity: targetActivity,
                sourceRouteCount: snapshot.routeLocations.count,
                sourceRoutePointCount: snapshot.routePointCount,
                sourceRouteGeometry: snapshot.routeGeometry,
                sourceHeartRateUUIDs: snapshot.heartRateUUIDs,
                sourceActiveEnergyUUIDs: snapshot.activeEnergyUUIDs,
                expectedEffort: candidateEffort,
                requireSource: true
            )
            verified = true
        }

        return Inspection(
            sessionID: sessionID,
            sourceUUID: snapshot.source.uuid,
            sourceActivity: ActivityKind(healthKitType: snapshot.source.workoutActivityType) ?? .other,
            sourceDistanceMeters: snapshot.sourceDistance,
            startedAt: snapshot.source.startDate,
            endedAt: snapshot.source.endDate,
            routeCount: snapshot.routeLocations.count,
            routePointCount: snapshot.routePointCount,
            routeGeometryMeters: snapshot.routeGeometry,
            heartRateSampleCount: snapshot.heartRateUUIDs.count,
            activeEnergySampleCount: snapshot.activeEnergyUUIDs.count,
            sourceEffort: snapshot.sourceEffort,
            candidateUUID: snapshot.candidate?.uuid,
            candidateVerified: verified
        )
    }

    private func inspectCandidateOnly(
        sessionID: String,
        candidateUUID: UUID,
        authorityDistance: Double,
        targetActivity: ActivityKind
    ) async throws -> Inspection {
        let workouts = try await sessionWorkouts(sessionID: sessionID)
        guard let candidate = workouts.first(where: { $0.uuid == candidateUUID && isCandidate($0) }) else {
            throw HistoricalHealthKitRepairV4Coordinator.V4Error.operation(
                "candidat final introuvable"
            )
        }
        let candidateRoutes = try await base.routes(for: candidate)
        let locations = try await loadRouteLocations(candidateRoutes)
        let candidateEffort = try await effortValue(for: candidate)
        let sourceDistance = (candidate.metadata?[forensicSourceDistanceKey] as? NSNumber)?.doubleValue ?? 0
        let sourceUUID = UUID(
            uuidString: candidate.metadata?[forensicSourceUUIDKey] as? String ?? ""
        ) ?? candidate.uuid

        return Inspection(
            sessionID: sessionID,
            sourceUUID: sourceUUID,
            sourceActivity: .other,
            sourceDistanceMeters: sourceDistance,
            startedAt: candidate.startDate,
            endedAt: candidate.endDate,
            routeCount: locations.count,
            routePointCount: locations.reduce(0) { $0 + $1.count },
            routeGeometryMeters: locations.reduce(0) { $0 + geometry($1) },
            heartRateSampleCount: try await sampleUUIDs(
                identifier: .heartRate,
                workout: candidate
            ).count,
            activeEnergySampleCount: try await sampleUUIDs(
                identifier: .activeEnergyBurned,
                workout: candidate
            ).count,
            sourceEffort: candidateEffort,
            candidateUUID: candidate.uuid,
            candidateVerified: true
        )
    }

    private func sourceSnapshot(
        sessionID: String,
        authorityDistance: Double,
        targetActivity: ActivityKind
    ) async throws -> SourceSnapshot {
        let workouts = try await sessionWorkouts(sessionID: sessionID)
        let candidates = workouts.filter(isCandidate)
        guard candidates.count <= 1 else {
            throw HistoricalHealthKitRepairV4Coordinator.V4Error.operation(
                "plusieurs candidats orphelins détectés"
            )
        }

        let sources = workouts.filter { workout in
            !isCandidate(workout)
                && (workout.metadata?[base.rawRestoreKey] as? Bool) != true
        }
        guard sources.count == 1, let source = sources.first else {
            throw HistoricalHealthKitRepairV4Coordinator.V4Error.operation(
                "la correction exige exactement un workout Tracker source normal"
            )
        }
        guard source.workoutActivityType != targetActivity.healthKitType else {
            throw HistoricalHealthKitRepairV4Coordinator.V4Error.operation(
                "le workout source est déjà du type cible"
            )
        }

        let sourceRoutes = try await base.routes(for: source)
        let routeLocations = try await loadRouteLocations(sourceRoutes)
        let pointCount = routeLocations.reduce(0) { $0 + $1.count }
        let routeGeometry = routeLocations.reduce(0) { $0 + geometry($1) }
        guard pointCount >= 2, routeGeometry > 0 else {
            throw HistoricalHealthKitRepairV4Coordinator.V4Error.operation(
                "route HealthKit source absente ou insuffisante"
            )
        }

        let geometryTolerance = max(300, authorityDistance * 0.15)
        guard abs(routeGeometry - authorityDistance) <= geometryTolerance else {
            throw HistoricalHealthKitRepairV4Coordinator.V4Error.operation(
                String(
                    format: "géométrie source %.0f m incompatible avec la preuve %.0f m",
                    routeGeometry,
                    authorityDistance
                )
            )
        }

        return SourceSnapshot(
            source: source,
            candidate: candidates.first,
            sourceDistance: allDistanceMeters(in: source),
            routeLocations: routeLocations,
            routePointCount: pointCount,
            routeGeometry: routeGeometry,
            heartRateUUIDs: try await sampleUUIDs(identifier: .heartRate, workout: source),
            activeEnergyUUIDs: try await sampleUUIDs(identifier: .activeEnergyBurned, workout: source),
            sourceEffort: try await effortValue(for: source)
        )
    }

    private func verifyCandidateDurably(
        sessionID: String,
        sourceUUID: UUID,
        candidateUUID: UUID,
        authorityDistance: Double,
        targetActivity: ActivityKind,
        sourceRouteCount: Int,
        sourceRoutePointCount: Int,
        sourceRouteGeometry: Double,
        sourceHeartRateUUIDs: Set<UUID>,
        sourceActiveEnergyUUIDs: Set<UUID>,
        expectedEffort: Int?,
        requireSource: Bool
    ) async throws {
        for delay: UInt64 in [0, 1_000_000_000, 2_500_000_000] {
            if delay > 0 { try await Task.sleep(nanoseconds: delay) }
            try await verifyCandidateOnce(
                sessionID: sessionID,
                sourceUUID: sourceUUID,
                candidateUUID: candidateUUID,
                authorityDistance: authorityDistance,
                targetActivity: targetActivity,
                sourceRouteCount: sourceRouteCount,
                sourceRoutePointCount: sourceRoutePointCount,
                sourceRouteGeometry: sourceRouteGeometry,
                sourceHeartRateUUIDs: sourceHeartRateUUIDs,
                sourceActiveEnergyUUIDs: sourceActiveEnergyUUIDs,
                expectedEffort: expectedEffort,
                requireSource: requireSource
            )
        }
    }

    private func verifyCandidateOnce(
        sessionID: String,
        sourceUUID: UUID,
        candidateUUID: UUID,
        authorityDistance: Double,
        targetActivity: ActivityKind,
        sourceRouteCount: Int,
        sourceRoutePointCount: Int,
        sourceRouteGeometry: Double,
        sourceHeartRateUUIDs: Set<UUID>,
        sourceActiveEnergyUUIDs: Set<UUID>,
        expectedEffort: Int?,
        requireSource: Bool
    ) async throws {
        let workouts = try await sessionWorkouts(sessionID: sessionID)
        if requireSource {
            guard workouts.contains(where: { $0.uuid == sourceUUID && !isCandidate($0) }) else {
                throw HistoricalHealthKitRepairV4Coordinator.V4Error.operation(
                    "source originale absente pendant la vérification"
                )
            }
        } else {
            guard !workouts.contains(where: { $0.uuid == sourceUUID }) else {
                throw HistoricalHealthKitRepairV4Coordinator.V4Error.operation(
                    "source originale toujours présente après finalisation"
                )
            }
        }

        let candidates = workouts.filter(isCandidate)
        guard candidates.count == 1,
              let candidate = candidates.first,
              candidate.uuid == candidateUUID,
              candidate.workoutActivityType == targetActivity.healthKitType,
              (candidate.metadata?[forensicSourceUUIDKey] as? String) == sourceUUID.uuidString else {
            throw HistoricalHealthKitRepairV4Coordinator.V4Error.operation(
                "unicité/type/identité du candidat orphelin non vérifiés"
            )
        }

        let distance = targetDistanceMeters(in: candidate, activity: targetActivity)
        let tolerance = max(15, authorityDistance * 0.04)
        guard let distance, abs(distance - authorityDistance) <= tolerance else {
            throw HistoricalHealthKitRepairV4Coordinator.V4Error.operation(
                "distance du candidat incohérente"
            )
        }

        let candidateSamples = try await associatedQuantitySamples(for: candidate)
        let targetDistanceIdentifier = base.distanceIdentifier(for: targetActivity)
        for identifier: HKQuantityTypeIdentifier in [
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
        ] where identifier != targetDistanceIdentifier {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { continue }
            let count = candidateSamples.compactMap { $0 as? HKQuantitySample }
                .filter { $0.quantityType == type }
                .count
            guard count == 0 else {
                throw HistoricalHealthKitRepairV4Coordinator.V4Error.operation(
                    "ancien type de distance encore associé au candidat"
                )
            }
        }

        let candidateSourceHR = sourceUUIDs(in: candidateSamples, identifier: .heartRate)
        let candidateSourceEnergy = sourceUUIDs(in: candidateSamples, identifier: .activeEnergyBurned)
        guard sourceHeartRateUUIDs.isSubset(of: candidateSourceHR) else {
            throw HistoricalHealthKitRepairV4Coordinator.V4Error.operation(
                "échantillons de fréquence cardiaque incomplets sur le candidat"
            )
        }
        guard sourceActiveEnergyUUIDs.isSubset(of: candidateSourceEnergy) else {
            throw HistoricalHealthKitRepairV4Coordinator.V4Error.operation(
                "échantillons d’énergie incomplets sur le candidat"
            )
        }

        let candidateRoutes = try await base.routes(for: candidate)
        guard candidateRoutes.count == sourceRouteCount else {
            throw HistoricalHealthKitRepairV4Coordinator.V4Error.operation(
                "nombre de routes candidat/source différent"
            )
        }
        let routeLocations = try await loadRouteLocations(candidateRoutes)
        let pointCount = routeLocations.reduce(0) { $0 + $1.count }
        guard pointCount >= sourceRoutePointCount else {
            throw HistoricalHealthKitRepairV4Coordinator.V4Error.operation(
                "points de route incomplets sur le candidat"
            )
        }
        let candidateGeometry = routeLocations.reduce(0) { $0 + geometry($1) }
        let geometryTolerance = max(100, sourceRouteGeometry * 0.02)
        guard abs(candidateGeometry - sourceRouteGeometry) <= geometryTolerance else {
            throw HistoricalHealthKitRepairV4Coordinator.V4Error.operation(
                "géométrie de route candidate différente de la source"
            )
        }

        if let expectedEffort {
            let actual = try await effortValue(for: candidate)
            guard actual == expectedEffort else {
                throw HistoricalHealthKitRepairV4Coordinator.V4Error.operation(
                    "effort Apple du candidat non vérifié"
                )
            }
        }
    }

    private func sessionWorkouts(sessionID: String) async throws -> [HKWorkout] {
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: base.sessionKey,
            operatorType: .equalTo,
            value: sessionID
        )
        let samples = try await base.querySamples(
            type: HKObjectType.workoutType(),
            predicate: predicate
        )
        return (samples as? [HKWorkout] ?? []).filter {
            ($0.metadata?[base.managedKey] as? Bool) == true
                && ($0.metadata?[base.sessionKey] as? String) == sessionID
        }
    }

    private func isCandidate(_ workout: HKWorkout) -> Bool {
        (workout.metadata?[forensicKey] as? Bool) == true
            && (workout.metadata?[base.generationKey] as? String) == generation
    }

    private func associatedQuantitySamples(for workout: HKWorkout) async throws -> [HKSample] {
        let predicate = HKQuery.predicateForObjects(from: workout)
        var result: [HKSample] = []
        var identifiers: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .activeEnergyBurned,
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
        ]
        if #available(iOS 18.0, *) {
            identifiers.append(.workoutEffortScore)
        }
        for identifier in identifiers {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { continue }
            result.append(contentsOf: try await base.querySamples(type: type, predicate: predicate))
        }
        return Array(
            Dictionary(grouping: result, by: \.uuid)
                .values
                .compactMap(\.first)
        )
    }

    private func cloneNonDistanceSamples(
        _ samples: [HKSample],
        sessionID: String,
        attemptID: String
    ) throws -> [HKSample] {
        let distanceTypes = Set(
            [
                HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning),
                HKQuantityType.quantityType(forIdentifier: .distanceCycling),
                HKQuantityType.quantityType(forIdentifier: .distanceSwimming),
            ].compactMap { $0 }
        )
        let effortType: HKQuantityType? = {
            if #available(iOS 18.0, *) {
                return HKQuantityType.quantityType(forIdentifier: .workoutEffortScore)
            }
            return nil
        }()

        return samples.compactMap { sample in
            guard let quantity = sample as? HKQuantitySample else { return nil }
            if distanceTypes.contains(quantity.quantityType) { return nil }
            if let effortType, quantity.quantityType == effortType { return nil }
            return HKQuantitySample(
                type: quantity.quantityType,
                quantity: quantity.quantity,
                start: quantity.startDate,
                end: quantity.endDate,
                metadata: [
                    base.rawRestoreKey: true,
                    base.sessionKey: sessionID,
                    base.generationKey: generation,
                    base.attemptKey: attemptID,
                    forensicKey: true,
                    sourceSampleUUIDKey: quantity.uuid.uuidString,
                ]
            )
        }
    }

    private func makeDistanceSamples(
        totalMeters: Double,
        activity: ActivityKind,
        intervals: [DateInterval],
        sessionID: String,
        attemptID: String
    ) throws -> [HKQuantitySample] {
        guard let identifier = base.distanceIdentifier(for: activity),
              let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            throw HistoricalHealthKitRepairV4Coordinator.V4Error.operation(
                "type de distance cible indisponible"
            )
        }
        guard !intervals.isEmpty else {
            throw HistoricalHealthKitRepairV4Coordinator.V4Error.operation(
                "aucun intervalle actif pour la distance"
            )
        }

        let totalDuration = intervals.reduce(0.0) { $0 + $1.duration }
        guard totalDuration > 0 else {
            throw HistoricalHealthKitRepairV4Coordinator.V4Error.operation(
                "durée active nulle"
            )
        }

        var allocated = 0.0
        return intervals.enumerated().map { index, interval in
            let meters: Double
            if index == intervals.count - 1 {
                meters = max(0, totalMeters - allocated)
            } else {
                meters = totalMeters * (interval.duration / totalDuration)
                allocated += meters
            }
            return HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: .meter(), doubleValue: meters),
                start: interval.start,
                end: interval.end,
                metadata: [
                    base.rawRestoreKey: true,
                    base.sessionKey: sessionID,
                    base.generationKey: generation,
                    base.attemptKey: attemptID,
                    forensicKey: true,
                ]
            )
        }
    }

    private func activeIntervals(
        start: Date,
        end: Date,
        events: [HKWorkoutEvent]
    ) -> [DateInterval] {
        let ordered = events.sorted { $0.dateInterval.start < $1.dateInterval.start }
        var result: [DateInterval] = []
        var cursor = start
        var paused = false

        for event in ordered {
            let date = min(max(event.dateInterval.start, start), end)
            switch event.type {
            case .pause:
                if !paused {
                    if date > cursor {
                        result.append(DateInterval(start: cursor, end: date))
                    }
                    paused = true
                }
            case .resume:
                if paused {
                    cursor = max(cursor, date)
                    paused = false
                }
            default:
                continue
            }
        }

        if !paused, end > cursor {
            result.append(DateInterval(start: cursor, end: end))
        }
        return result.filter { $0.duration > 0.001 }
    }

    private func candidateMetadata(
        sessionID: String,
        source: HKWorkout,
        authorityDistance: Double,
        sourceDistance: Double,
        sourceGeometry: Double,
        attemptID: String,
        targetActivity: ActivityKind
    ) -> [String: Any] {
        var metadata: [String: Any] = [
            base.managedKey: true,
            base.sessionKey: sessionID,
            base.rawRestoreKey: true,
            base.rawRestoreSchemaKey: TrackerHealthRestorePayload.currentSchema,
            base.rawRestoreSourceKey: "healthkit_orphan_existing_route",
            base.correctionTargetKey: targetActivity.rawValue,
            base.masterActivityKey: targetActivity.rawValue,
            base.algorithmKey: "healthkit-orphan-v1",
            base.buildKey: BuildInfo.gitSHA,
            base.generationKey: generation,
            base.attemptKey: attemptID,
            forensicKey: true,
            forensicSourceUUIDKey: source.uuid.uuidString,
            forensicDistanceKey: authorityDistance,
            forensicSourceDistanceKey: sourceDistance,
            forensicSourceGeometryKey: sourceGeometry,
            forensicEvidenceKey: "external_recovery_audit",
            HKMetadataKeyIndoorWorkout: false,
        ]
        if let brand = source.metadata?[HKMetadataKeyWorkoutBrandName] {
            metadata[HKMetadataKeyWorkoutBrandName] = brand
        } else {
            metadata[HKMetadataKeyWorkoutBrandName] = "Watch Tracker"
        }
        return metadata
    }

    private func loadRouteLocations(_ routes: [HKWorkoutRoute]) async throws -> [[CLLocation]] {
        var result: [[CLLocation]] = []
        for route in routes {
            let locations = try await base.loadLocations(for: route)
                .sorted { $0.timestamp < $1.timestamp }
            if !locations.isEmpty { result.append(locations) }
        }
        return result
    }

    private func geometry(_ locations: [CLLocation]) -> Double {
        guard locations.count >= 2 else { return 0 }
        var total = 0.0
        for index in 1..<locations.count {
            total += locations[index - 1].distance(from: locations[index])
        }
        return total
    }

    private func allDistanceMeters(in workout: HKWorkout) -> Double {
        [
            HKQuantityTypeIdentifier.distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
        ].reduce(0.0) { partial, identifier in
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier),
                  let quantity = workout.statistics(for: type)?.sumQuantity() else {
                return partial
            }
            return partial + quantity.doubleValue(for: .meter())
        }
    }

    private func targetDistanceMeters(
        in workout: HKWorkout,
        activity: ActivityKind
    ) -> Double? {
        guard let identifier = base.distanceIdentifier(for: activity),
              let type = HKQuantityType.quantityType(forIdentifier: identifier),
              let quantity = workout.statistics(for: type)?.sumQuantity() else {
            return nil
        }
        return quantity.doubleValue(for: .meter())
    }

    private func sampleUUIDs(
        identifier: HKQuantityTypeIdentifier,
        workout: HKWorkout
    ) async throws -> Set<UUID> {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return []
        }
        let predicate = HKQuery.predicateForObjects(from: workout)
        let samples = try await base.querySamples(type: type, predicate: predicate)
        return Set(samples.map(\.uuid))
    }

    private func sourceUUIDs(
        in samples: [HKSample],
        identifier: HKQuantityTypeIdentifier
    ) -> Set<UUID> {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return []
        }
        return Set(
            samples.compactMap { sample -> UUID? in
                guard let quantity = sample as? HKQuantitySample,
                      quantity.quantityType == type,
                      let value = quantity.metadata?[sourceSampleUUIDKey] as? String else {
                    return nil
                }
                return UUID(uuidString: value)
            }
        )
    }

    private func effortValue(for workout: HKWorkout) async throws -> Int? {
        guard #available(iOS 18.0, *) else { return nil }
        let samples = try await base.effortSamples(for: workout)
            .compactMap { $0 as? HKQuantitySample }
        guard let sample = samples.first else { return nil }
        let value = Int(
            sample.quantity.doubleValue(for: .appleEffortScore()).rounded()
        )
        return (1...10).contains(value) ? value : nil
    }
}

struct HistoricalHealthKitOrphanRepairCard: View {
    @ObservedObject private var coordinator = HistoricalHealthKitOrphanRepairCoordinator.shared
    @State private var confirmCreate = false
    @State private var confirmCleanup = false
    @State private var confirmFinalize = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Récupération orpheline HealthKit", systemImage: "cross.case.fill")
                .font(.headline.weight(.bold))
            Text(
                "À utiliser seulement quand la séance Tracker locale a disparu mais que le workout et sa route existent encore dans Santé. La distance saisie doit provenir d’un export forensic sauvegardé."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            TextField("Session ID", text: $coordinator.sessionID)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            TextField("Distance d’autorité (m)", text: $coordinator.authoritativeDistanceText)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.decimalPad)

            Picker("Sport cible", selection: $coordinator.targetActivity) {
                ForEach(ActivityKind.allCases.filter { !$0.isAutomatic }) { activity in
                    Text(activity.label).tag(activity)
                }
            }
            .pickerStyle(.menu)

            Picker("Effort Apple", selection: $coordinator.perceivedEffort) {
                Text("Non renseigné").tag(Optional<Int>.none)
                ForEach(1...10, id: \.self) { value in
                    Text("\(value) / 10").tag(Optional(value))
                }
            }
            .pickerStyle(.menu)

            Button {
                coordinator.inspect()
            } label: {
                Label("Inspecter sans écrire", systemImage: "waveform.path.ecg.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(coordinator.busy)

            if let inspection = coordinator.inspection {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Source : \(inspection.sourceActivity.label) · \(inspection.sourceUUID.uuidString)")
                    Text(
                        String(
                            format: "Distance source %.2f km · preuve %.2f km",
                            inspection.sourceDistanceMeters / 1000,
                            (coordinator.parsedAuthorityDistance ?? 0) / 1000
                        )
                    )
                    Text(
                        String(
                            format: "Route %d · %d points · %.2f km",
                            inspection.routeCount,
                            inspection.routePointCount,
                            inspection.routeGeometryMeters / 1000
                        )
                    )
                    Text(
                        "FC \(inspection.heartRateSampleCount) samples · énergie \(inspection.activeEnergySampleCount) sample(s)"
                    )
                    if let effort = inspection.sourceEffort {
                        Text("Effort source relu : \(effort) / 10")
                    }
                    if let candidate = inspection.candidateUUID {
                        Text("Candidat : \(candidate.uuidString)")
                        Text(
                            inspection.candidateVerified
                                ? "Candidat relu : OUI · source conservée"
                                : "Candidat relu : NON"
                        )
                        .foregroundStyle(inspection.candidateVerified ? .green : .red)
                    }
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

                if inspection.candidateUUID == nil {
                    Button {
                        confirmCreate = true
                    } label: {
                        Label("Créer le candidat sans supprimer la source", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(coordinator.busy)
                } else {
                    Button(role: .destructive) {
                        confirmCleanup = true
                    } label: {
                        Label("Nettoyer seulement le candidat", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(coordinator.busy)

                    if coordinator.candidateReady {
                        Button(role: .destructive) {
                            confirmFinalize = true
                        } label: {
                            Label(
                                "Finaliser après validation Santé/Forme",
                                systemImage: "checkmark.shield.fill"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(coordinator.busy)

                        Text(
                            "Ne finalise qu’après avoir ouvert le candidat dans Santé/Forme et vérifié sport, distance, route, fréquence cardiaque, calories et effort."
                        )
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    }
                }
            }

            if !coordinator.status.isEmpty {
                Text(coordinator.status)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(
                        coordinator.status.contains("bloquée")
                            || coordinator.status.contains("incomplète")
                            || coordinator.status.contains("annulée")
                            ? .red
                            : .secondary
                    )
            }
        }
        .padding(14)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
        .confirmationDialog(
            "Créer un candidat corrigé en conservant la source originale ?",
            isPresented: $confirmCreate,
            titleVisibility: .visible
        ) {
            Button("Créer le candidat") {
                coordinator.createCandidate()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(
                "La source HealthKit normale reste intacte. Le candidat réutilise la route existante et la distance d’autorité saisie."
            )
        }
        .confirmationDialog(
            "Supprimer seulement le candidat de test ?",
            isPresented: $confirmCleanup,
            titleVisibility: .visible
        ) {
            Button("Nettoyer le candidat", role: .destructive) {
                coordinator.cleanupCandidate()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Le workout source normal et sa route restent intacts.")
        }
        .confirmationDialog(
            "Tu as vérifié physiquement le candidat dans Santé/Forme ?",
            isPresented: $confirmFinalize,
            titleVisibility: .visible
        ) {
            Button("Finaliser et supprimer la source normale", role: .destructive) {
                coordinator.finalize()
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(
                "Le candidat est relu à nouveau avant suppression. La source normale est ensuite supprimée de façon ciblée, puis le candidat est relu après suppression."
            )
        }
    }
}
