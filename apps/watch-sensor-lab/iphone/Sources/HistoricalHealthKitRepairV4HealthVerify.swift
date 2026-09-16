import CoreLocation
import Foundation
import HealthKit

extension HistoricalHealthKitRepairV4Coordinator {
    // MARK: - Durable verification

    func verifyDurably(
        payload: TrackerHealthRestorePayload,
        summary: TrackerSummary,
        activity: ActivityKind,
        route: CleanRoute,
        routeSegments: [[RawPoint]],
        workoutUUID: UUID,
        routeUUIDs: Set<UUID>,
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
                routeSegments: routeSegments,
                workoutUUID: workoutUUID,
                routeUUIDs: routeUUIDs,
                attemptID: attemptID,
                perceivedEffort: perceivedEffort
            )
        }
    }

    func verifyOnce(
        payload: TrackerHealthRestorePayload,
        summary: TrackerSummary,
        activity: ActivityKind,
        route: CleanRoute,
        routeSegments: [[RawPoint]],
        workoutUUID: UUID,
        routeUUIDs: Set<UUID>,
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

        if let expectedBundle = Bundle.main.bundleIdentifier {
            guard workout.sourceRevision.source.bundleIdentifier == expectedBundle else {
                throw V4Error.operation(
                    "source HealthKit inattendue: \(workout.sourceRevision.source.bundleIdentifier)"
                )
            }
        }

        let durationTolerance = max(20, payload.activeDuration * 0.04)
        guard abs(workout.duration - payload.activeDuration) <= durationTolerance else {
            throw V4Error.operation("durée active v4 incohérente")
        }
        try HistoricalHealthKitFullFidelity.verifyWorkoutMetadata(
            workout: workout,
            summary: summary
        )

        try verifyWorkoutStatistics(workout, payload: payload, activity: activity)

        let generatedSamples = try await generatedQuantitySamples(
            sessionID: payload.sessionID,
            summary: summary,
            attemptID: attemptID
        )
        try verifyQuantitySamples(
            generatedSamples,
            payload: payload,
            activity: activity,
            routedPoints: routeSegments.flatMap { $0 }
        )

        let savedRoutes = try await routes(for: workout)
        let expectedRouteCount = routeSegments.count
        guard savedRoutes.count == expectedRouteCount,
              Set(savedRoutes.map(\.uuid)) == routeUUIDs else {
            throw V4Error.operation(
                "routes v4 segmentées non relues: \(savedRoutes.count)/\(expectedRouteCount)"
            )
        }

        var totalLocations = 0
        for savedRoute in savedRoutes {
            guard (savedRoute.metadata?[generationKey] as? String) == generation,
                  (savedRoute.metadata?[attemptKey] as? String) == attemptID else {
                throw V4Error.operation("identité d’un segment route v4 non vérifiée")
            }
            totalLocations += try await loadLocations(for: savedRoute).count
        }
        let expectedLocations = routeSegments.reduce(0) { $0 + $1.count }
        guard totalLocations >= max(2, Int(Double(expectedLocations) * 0.95)) else {
            throw V4Error.operation("points GPS v4 segmentés manquants après relecture")
        }

        try await HistoricalHealthKitFullFidelity.verifyPerceivedEffort(
            healthStore: healthStore,
            workout: workout,
            perceivedEffort: perceivedEffort,
            attemptID: attemptID
        )
    }

    func verifyWorkoutStatistics(
        _ workout: HKWorkout,
        payload: TrackerHealthRestorePayload,
        activity: ActivityKind
    ) throws {
        if let identifier = distanceIdentifier(for: activity),
           let type = HKQuantityType.quantityType(forIdentifier: identifier),
           payload.distanceMeters > 0 {
            guard let meters = workout.statistics(for: type)?.sumQuantity()?.doubleValue(for: .meter()) else {
                throw V4Error.operation("distance workout HealthKit absente")
            }
            let tolerance = max(15, payload.distanceMeters * 0.04)
            guard abs(meters - payload.distanceMeters) <= tolerance else {
                throw V4Error.operation(
                    String(format: "distance workout %.0f m au lieu de %.0f m", meters, payload.distanceMeters)
                )
            }
        }
        if let energy = payload.activeEnergyKcal,
           energy > 0,
           let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            guard let kcal = workout.statistics(for: type)?.sumQuantity()?.doubleValue(for: .kilocalorie()) else {
                throw V4Error.operation("énergie workout HealthKit absente")
            }
            let tolerance = max(2, energy * 0.05)
            guard abs(kcal - energy) <= tolerance else {
                throw V4Error.operation("énergie workout HealthKit incohérente")
            }
        }
    }

    func workoutDistanceMeters(_ workout: HKWorkout, activity: ActivityKind) -> Double? {
        guard let identifier = distanceIdentifier(for: activity),
              let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return nil
        }
        return workout.statistics(for: type)?.sumQuantity()?.doubleValue(for: .meter())
    }

    func verifyQuantitySamples(
        _ samples: [HKSample],
        payload: TrackerHealthRestorePayload,
        activity: ActivityKind,
        routedPoints: [RawPoint]
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
            let expected = routedPoints.filter {
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

    func managedWorkouts(
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

    func isGenerated(_ workout: HKWorkout, sessionID: String) -> Bool {
        (workout.metadata?[rawRestoreKey] as? Bool) == true
            && (workout.metadata?[sessionKey] as? String) == sessionID
    }

    func routes(for workout: HKWorkout) async throws -> [HKWorkoutRoute] {
        let samples = try await querySamples(
            type: HKSeriesType.workoutRoute(),
            predicate: HKQuery.predicateForObjects(from: workout)
        )
        return samples as? [HKWorkoutRoute] ?? []
    }

    @available(iOS 18.0, *)
    func effortSamples(for workout: HKWorkout) async throws -> [HKSample] {
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

    func generatedQuantitySamples(
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

    func requestCleanupAuthorization() async throws {
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

    func requestRepairAuthorization(
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

    func requestAndVerifyAuthorization(
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

}
