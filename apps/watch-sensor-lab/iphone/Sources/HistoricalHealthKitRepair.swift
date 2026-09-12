import CoreLocation
import Foundation
import HealthKit
import SwiftUI

/// The only active product path for historical HealthKit reconstruction.
///
/// Live workouts remain Watch-owned and use HKWorkoutSession + HKLiveWorkoutBuilder.
/// Historical reconstruction runs on iPhone with standalone HKWorkoutBuilder.
///
/// Safety rule: this path NEVER deletes an existing Tracker workout or an older
/// generated restoration. Old generated objects are intentionally left in place
/// until a human has verified the replacement in both Apple Health and Fitness.
@MainActor
final class HistoricalHealthKitRepairCoordinator: ObservableObject {
    static let shared = HistoricalHealthKitRepairCoordinator()

    @Published private(set) var activeSessionID: String?
    @Published private(set) var statusBySession: [String: String] = [:]
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
    private let generation = "ios_historical_v2"

    private init() {}

    func repair(sessionID: String, targetActivity: ActivityKind) {
        guard activeSessionID == nil else {
            statusBySession[sessionID] = "Une réparation Santé est déjà en cours."
            return
        }
        guard !sessionID.isEmpty, !targetActivity.isAutomatic else {
            statusBySession[sessionID] = "Demande de réparation invalide."
            return
        }

        activeSessionID = sessionID
        internallyVerifiedSessions.remove(sessionID)
        statusBySession[sessionID] = "Préflight des données brutes Tracker…"

        Task {
            defer { activeSessionID = nil }

            do {
                let payload = try makePayload(
                    sessionID: sessionID,
                    targetActivity: targetActivity
                )

                statusBySession[sessionID] = "Autorisation d’écriture Santé sur iPhone…"
                try await requestAndVerifyAuthorization(
                    for: payload,
                    activity: targetActivity
                )

                statusBySession[sessionID] = "Inspection HealthKit avant écriture…"
                let existing = try await managedWorkouts(
                    sessionID: sessionID,
                    around: payload
                )

                // A genuine live/normal Tracker workout is never replaced here.
                let normalSources = existing.filter {
                    ($0.metadata?[rawRestoreKey] as? Bool) != true
                }
                guard normalSources.isEmpty else {
                    throw RepairError.operation(
                        "un workout Tracker normal existe déjà ; aucune suppression ni modification effectuée"
                    )
                }

                // Idempotence only applies to a transaction that carries its own
                // attempt identifier. Older v2 attempts without this identifier
                // are deliberately not trusted after the route-finalization incident.
                if let current = existing.first(where: {
                    ($0.metadata?[generationKey] as? String) == generation
                        && $0.workoutActivityType == targetActivity.healthKitType
                        && (($0.metadata?[attemptKey] as? String)?.isEmpty == false)
                }),
                   let currentAttemptID = current.metadata?[attemptKey] as? String {
                    let currentRoute = try await generatedRoute(
                        for: current,
                        attemptID: currentAttemptID
                    )
                    statusBySession[sessionID] = "Relecture de la reconstruction iPhone existante…"
                    try await verifyDurably(
                        payload: payload,
                        activity: targetActivity,
                        workoutUUID: current.uuid,
                        routeUUID: currentRoute?.uuid,
                        attemptID: currentAttemptID
                    )
                    internallyVerifiedSessions.insert(sessionID)
                    statusBySession[sessionID] =
                        "HealthKit iPhone relu · PAS encore validé dans Santé/Forme."
                    return
                }

                if existing.contains(where: { ($0.metadata?[rawRestoreKey] as? Bool) == true }) {
                    statusBySession[sessionID] =
                        "Ancienne restauration détectée · conservée par sécurité pendant la reconstruction…"
                }

                let attemptID = UUID().uuidString
                let created = try await createHistoricalWorkout(
                    payload: payload,
                    activity: targetActivity,
                    attemptID: attemptID
                )

                statusBySession[sessionID] = "Relectures HealthKit iPhone…"
                try await verifyDurably(
                    payload: payload,
                    activity: targetActivity,
                    workoutUUID: created.workout.uuid,
                    routeUUID: created.route?.uuid,
                    attemptID: attemptID
                )

                // Deliberately no cleanup here. Internal API readback is not
                // enough evidence to delete anything after the previous incident.
                internallyVerifiedSessions.insert(sessionID)
                statusBySession[sessionID] =
                    "HealthKit écrit et relu sur iPhone · PAS encore validé dans Santé/Forme."
            } catch {
                statusBySession[sessionID] =
                    "Réparation échouée · \(error.localizedDescription)"
            }
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

    private func requestAndVerifyAuthorization(
        for payload: TrackerHealthRestorePayload,
        activity: ActivityKind
    ) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw RepairError.operation("HealthKit indisponible sur cet appareil")
        }

        var shareTypes: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
        ]
        var readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
        ]

        for identifier in requiredQuantityIdentifiers(for: payload, activity: activity) {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
                throw RepairError.operation(
                    "type HealthKit requis indisponible: \(identifier.rawValue)"
                )
            }
            shareTypes.insert(type)
            readTypes.insert(type)
        }

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            healthStore.requestAuthorization(
                toShare: shareTypes,
                read: readTypes
            ) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if !success {
                    continuation.resume(
                        throwing: RepairError.operation(
                            "autorisation Santé refusée ou incomplète"
                        )
                    )
                } else {
                    continuation.resume(returning: ())
                }
            }
        }

        // HealthKit intentionally does not reveal read authorization state.
        // Write authorization is checkable and mandatory for every type we save.
        for type in shareTypes {
            let status = healthStore.authorizationStatus(for: type)
            switch status {
            case .sharingAuthorized:
                continue
            case .notDetermined:
                throw RepairError.operation(
                    "autorisation d’écriture Santé non déterminée pour \(type.identifier)"
                )
            case .sharingDenied:
                throw RepairError.operation(
                    "écriture Santé refusée pour \(type.identifier)"
                )
            @unknown default:
                throw RepairError.operation(
                    "autorisation Santé inconnue pour \(type.identifier)"
                )
            }
        }
    }

    private func requiredQuantityIdentifiers(
        for payload: TrackerHealthRestorePayload,
        activity: ActivityKind
    ) -> [HKQuantityTypeIdentifier] {
        var values: [HKQuantityTypeIdentifier] = [.heartRate]
        if (payload.activeEnergyKcal ?? 0) > 0 {
            values.append(.activeEnergyBurned)
        }
        if payload.distanceMeters > 0,
           let distance = distanceIdentifier(for: activity) {
            values.append(distance)
        }
        return values
    }

    private struct CreatedWorkout {
        let workout: HKWorkout
        let route: HKWorkoutRoute?
    }

    private func createHistoricalWorkout(
        payload: TrackerHealthRestorePayload,
        activity: ActivityKind,
        attemptID: String
    ) async throws -> CreatedWorkout {
        let startDate = Date(timeIntervalSince1970: payload.startedAt)
        let endDate = Date(timeIntervalSince1970: payload.endedAt)
        guard endDate > startDate,
              payload.activeDuration > 0,
              payload.distanceMeters > 0 else {
            throw RepairError.operation("données temporelles Tracker invalides")
        }

        let samples = try makeSamples(
            payload: payload,
            activity: activity,
            attemptID: attemptID
        )
        let events = makeEvents(payload: payload, attemptID: attemptID)
        let locations = makeLocations(payload: payload)

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activity.healthKitType
        configuration.locationType = locations.count >= 2 ? .outdoor : .unknown

        let builder = HKWorkoutBuilder(
            healthStore: healthStore,
            configuration: configuration,
            device: nil
        )
        let routeBuilder = builder.seriesBuilder(
            for: HKSeriesType.workoutRoute()
        ) as? HKWorkoutRouteBuilder

        var createdWorkout: HKWorkout?
        var createdRoute: HKWorkoutRoute?

        do {
            try await begin(builder, at: startDate)
            try await addMetadata([
                managedKey: true,
                sessionKey: payload.sessionID,
                rawRestoreKey: true,
                rawRestoreSchemaKey: payload.schema,
                rawRestoreSourceKey: "tracker_raw_ios_v2",
                correctionTargetKey: activity.rawValue,
                masterActivityKey: activity.rawValue,
                algorithmKey: payload.sourceAlgorithmVersion ?? "tracker-raw-ios-v2",
                buildKey: BuildInfo.gitSHA,
                generationKey: generation,
                attemptKey: attemptID,
                "com.rzbck.watchsensorlab.raw_active_duration": payload.activeDuration,
                "com.rzbck.watchsensorlab.raw_distance_m": payload.distanceMeters,
                "com.rzbck.watchsensorlab.raw_pause_provenance": payload.pauseProvenance,
            ], to: builder)

            try await add(samples, to: builder)
            if !events.isEmpty {
                try await add(events, to: builder)
            }
            if let routeBuilder, locations.count >= 2 {
                // This route builder is owned by HKWorkoutBuilder. On current iOS,
                // finishWorkout finalizes the attached series builder. Calling
                // finishRoute afterwards causes the runtime error observed on device.
                try await addMetadata([
                    managedKey: true,
                    sessionKey: payload.sessionID,
                    rawRestoreKey: true,
                    rawRestoreSchemaKey: payload.schema,
                    rawRestoreSourceKey: "tracker_raw_ios_v2",
                    generationKey: generation,
                    attemptKey: attemptID,
                ], to: routeBuilder)
                try await insert(locations, into: routeBuilder)
            }

            try await end(builder, at: endDate)
            guard let workout = try await finish(builder) else {
                throw RepairError.operation(
                    "HealthKit n’a pas retourné le workout restauré"
                )
            }
            createdWorkout = workout

            if locations.count >= 2 {
                guard routeBuilder != nil else {
                    throw RepairError.operation(
                        "HealthKit n’a pas fourni de route builder associé"
                    )
                }
                createdRoute = try await waitForGeneratedRoute(
                    for: workout,
                    attemptID: attemptID
                )
                guard createdRoute != nil else {
                    throw RepairError.operation(
                        "route Santé absente après finalisation du workout"
                    )
                }
            }

            return CreatedWorkout(workout: workout, route: createdRoute)
        } catch {
            // Roll back only objects created by THIS attempt. Never touch
            // a pre-existing workout or the raw Tracker files.
            if createdRoute == nil, let createdWorkout {
                createdRoute = try? await generatedRoute(
                    for: createdWorkout,
                    attemptID: attemptID
                )
            }

            var rollback: [HKObject] = []
            if let createdRoute { rollback.append(createdRoute) }
            if let createdWorkout { rollback.append(createdWorkout) }
            let createdSamples = (try? await generatedQuantitySamples(
                payload: payload,
                attemptID: attemptID
            )) ?? []
            rollback.append(contentsOf: createdSamples)

            if !rollback.isEmpty {
                try? await delete(rollback)
            }
            throw error
        }
    }

    private func makeSamples(
        payload: TrackerHealthRestorePayload,
        activity: ActivityKind,
        attemptID: String
    ) throws -> [HKSample] {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            throw RepairError.operation("type HealthKit fréquence cardiaque indisponible")
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
                quantity: HKQuantity(
                    unit: HKUnit(from: "count/min"),
                    doubleValue: point.bpm
                ),
                start: date,
                end: date,
                metadata: generatedMetadata(
                    sessionID: payload.sessionID,
                    attemptID: attemptID
                )
            )
        }

        let startDate = Date(timeIntervalSince1970: payload.startedAt)
        let endDate = Date(timeIntervalSince1970: payload.endedAt)

        if let energy = payload.activeEnergyKcal,
           energy > 0,
           let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            samples.append(HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: energy),
                start: startDate,
                end: endDate,
                metadata: generatedMetadata(
                    sessionID: payload.sessionID,
                    attemptID: attemptID
                )
            ))
        }

        if payload.distanceMeters > 0,
           let identifier = distanceIdentifier(for: activity),
           let type = HKQuantityType.quantityType(forIdentifier: identifier) {
            samples.append(HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: .meter(), doubleValue: payload.distanceMeters),
                start: startDate,
                end: endDate,
                metadata: generatedMetadata(
                    sessionID: payload.sessionID,
                    attemptID: attemptID
                )
            ))
        }

        guard !samples.isEmpty else {
            throw RepairError.operation("aucun sample brut restaurable")
        }
        return samples
    }

    private func generatedMetadata(
        sessionID: String,
        attemptID: String
    ) -> [String: Any] {
        [
            rawRestoreKey: true,
            sessionKey: sessionID,
            rawRestoreSourceKey: "tracker_raw_ios_v2",
            generationKey: generation,
            attemptKey: attemptID,
        ]
    }

    private func makeEvents(
        payload: TrackerHealthRestorePayload,
        attemptID: String
    ) -> [HKWorkoutEvent] {
        var result: [HKWorkoutEvent] = []

        for pause in payload.pauses.sorted(by: { $0.startedAt < $1.startedAt }) {
            guard pause.startedAt >= payload.startedAt,
                  pause.startedAt < payload.endedAt,
                  pause.endedAt > pause.startedAt,
                  pause.endedAt <= payload.endedAt else {
                continue
            }

            let eventMetadata: [String: Any] = [
                rawRestoreKey: true,
                generationKey: generation,
                attemptKey: attemptID,
            ]
            result.append(HKWorkoutEvent(
                type: .pause,
                dateInterval: DateInterval(
                    start: Date(timeIntervalSince1970: pause.startedAt),
                    duration: 0
                ),
                metadata: eventMetadata
            ))

            if pause.endedAt < payload.endedAt - 0.05 {
                result.append(HKWorkoutEvent(
                    type: .resume,
                    dateInterval: DateInterval(
                        start: Date(timeIntervalSince1970: pause.endedAt),
                        duration: 0
                    ),
                    metadata: eventMetadata
                ))
            }
        }

        return result
    }

    private func makeLocations(payload: TrackerHealthRestorePayload) -> [CLLocation] {
        payload.locations
            .filter {
                $0.timestamp >= payload.startedAt
                    && $0.timestamp <= payload.endedAt
                    && $0.horizontalAccuracyMeters >= 0
                    && $0.horizontalAccuracyMeters <= 50
                    && (-90...90).contains($0.latitude)
                    && (-180...180).contains($0.longitude)
            }
            .sorted { $0.timestamp < $1.timestamp }
            .map {
                CLLocation(
                    coordinate: CLLocationCoordinate2D(
                        latitude: $0.latitude,
                        longitude: $0.longitude
                    ),
                    altitude: $0.altitudeMeters,
                    horizontalAccuracy: $0.horizontalAccuracyMeters,
                    verticalAccuracy: $0.verticalAccuracyMeters,
                    course: -1,
                    speed: $0.speedMps ?? -1,
                    timestamp: Date(timeIntervalSince1970: $0.timestamp)
                )
            }
    }

    private func distanceIdentifier(
        for activity: ActivityKind
    ) -> HKQuantityTypeIdentifier? {
        switch activity {
        case .cycling, .handCycling:
            return .distanceCycling
        case .swimming, .waterFitness, .waterPolo:
            return .distanceSwimming
        case .walking, .running, .hiking, .trackAndField:
            return .distanceWalkingRunning
        default:
            return nil
        }
    }

    private func managedWorkouts(
        sessionID: String,
        around payload: TrackerHealthRestorePayload
    ) async throws -> [HKWorkout] {
        let startDate = Date(timeIntervalSince1970: payload.startedAt)
            .addingTimeInterval(-60)
        let endDate = Date(timeIntervalSince1970: payload.endedAt)
            .addingTimeInterval(60)
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
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

    private func generatedRoute(
        for workout: HKWorkout,
        attemptID: String
    ) async throws -> HKWorkoutRoute? {
        let values = try await routes(for: workout)
        return values.first {
            ($0.metadata?[generationKey] as? String) == generation
                && ($0.metadata?[attemptKey] as? String) == attemptID
        }
    }

    private func waitForGeneratedRoute(
        for workout: HKWorkout,
        attemptID: String
    ) async throws -> HKWorkoutRoute? {
        let delays: [UInt64] = [0, 400_000_000, 1_200_000_000]
        for delay in delays {
            if delay > 0 {
                try await Task.sleep(nanoseconds: delay)
            }
            if let route = try await generatedRoute(
                for: workout,
                attemptID: attemptID
            ) {
                return route
            }
        }
        return nil
    }

    private func verifyDurably(
        payload: TrackerHealthRestorePayload,
        activity: ActivityKind,
        workoutUUID: UUID,
        routeUUID: UUID?,
        attemptID: String
    ) async throws {
        let delays: [UInt64] = [0, 1_200_000_000, 3_000_000_000]
        for delay in delays {
            if delay > 0 {
                try await Task.sleep(nanoseconds: delay)
            }
            try await verify(
                payload: payload,
                activity: activity,
                workoutUUID: workoutUUID,
                routeUUID: routeUUID,
                attemptID: attemptID
            )
        }
    }

    private func verify(
        payload: TrackerHealthRestorePayload,
        activity: ActivityKind,
        workoutUUID: UUID,
        routeUUID: UUID?,
        attemptID: String
    ) async throws {
        let workouts = try await managedWorkouts(
            sessionID: payload.sessionID,
            around: payload
        )

        guard let workout = workouts.first(where: { $0.uuid == workoutUUID }),
              workout.workoutActivityType == activity.healthKitType,
              (workout.metadata?[rawRestoreKey] as? Bool) == true,
              (workout.metadata?[generationKey] as? String) == generation,
              (workout.metadata?[attemptKey] as? String) == attemptID,
              abs(workout.startDate.timeIntervalSince1970 - payload.startedAt) <= 1,
              abs(workout.endDate.timeIntervalSince1970 - payload.endedAt) <= 1 else {
            throw RepairError.operation(
                "le workout iPhone n’a pas passé la relecture HealthKit"
            )
        }

        let durationTolerance = max(20, payload.activeDuration * 0.04)
        guard abs(workout.duration - payload.activeDuration) <= durationTolerance else {
            throw RepairError.operation(
                "la durée active restaurée ne correspond pas aux raw Tracker"
            )
        }

        let generatedSamples = try await generatedQuantitySamples(
            payload: payload,
            attemptID: attemptID
        )
        let expectedMinimum = payload.heartRates.count
            + ((payload.activeEnergyKcal ?? 0) > 0 ? 1 : 0)
            + (distanceIdentifier(for: activity) == nil ? 0 : 1)

        guard generatedSamples.count >= expectedMinimum else {
            throw RepairError.operation(
                "des samples restaurés manquent après relecture"
            )
        }

        if let distanceID = distanceIdentifier(for: activity),
           payload.distanceMeters > 1,
           let distanceType = HKQuantityType.quantityType(forIdentifier: distanceID) {
            let meters = generatedSamples
                .compactMap { $0 as? HKQuantitySample }
                .filter { $0.quantityType == distanceType }
                .reduce(0) {
                    $0 + $1.quantity.doubleValue(for: .meter())
                }
            let tolerance = max(15, payload.distanceMeters * 0.04)
            guard abs(meters - payload.distanceMeters) <= tolerance else {
                throw RepairError.operation(
                    "la distance restaurée ne correspond pas aux raw Tracker"
                )
            }
        }

        let expectedLocations = makeLocations(payload: payload).count
        if expectedLocations >= 2 {
            guard let routeUUID else {
                throw RepairError.operation("route Santé absente après restauration")
            }
            let routeValues = try await routes(for: workout)
            guard let route = routeValues.first(where: { $0.uuid == routeUUID }),
                  (route.metadata?[generationKey] as? String) == generation,
                  (route.metadata?[attemptKey] as? String) == attemptID else {
                throw RepairError.operation("route Santé non relue après restauration")
            }
            let locations = try await loadLocations(for: route)
            guard locations.count >= max(2, Int(Double(expectedLocations) * 0.90)) else {
                throw RepairError.operation(
                    "points GPS manquants après relecture Santé"
                )
            }
        }
    }

    private func generatedQuantitySamples(
        payload: TrackerHealthRestorePayload,
        attemptID: String
    ) async throws -> [HKSample] {
        let startDate = Date(timeIntervalSince1970: payload.startedAt)
            .addingTimeInterval(-1)
        let endDate = Date(timeIntervalSince1970: payload.endedAt)
            .addingTimeInterval(1)
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: []
        )

        var result: [HKSample] = []
        let identifiers: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .activeEnergyBurned,
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
        ]

        for identifier in identifiers {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
                continue
            }
            let values = try await querySamples(type: type, predicate: predicate)
            result.append(contentsOf: values.filter {
                ($0.metadata?[rawRestoreKey] as? Bool) == true
                    && ($0.metadata?[sessionKey] as? String) == payload.sessionID
                    && ($0.metadata?[generationKey] as? String) == generation
                    && ($0.metadata?[attemptKey] as? String) == attemptID
            })
        }
        return result
    }

    private func routes(for workout: HKWorkout) async throws -> [HKWorkoutRoute] {
        let predicate = HKQuery.predicateForObjects(from: workout)
        let samples = try await querySamples(
            type: HKSeriesType.workoutRoute(),
            predicate: predicate
        )
        return samples as? [HKWorkoutRoute] ?? []
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
                if done {
                    continuation.resume(returning: result)
                }
            }
            healthStore.execute(query)
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

    private func addMetadata(
        _ metadata: [String: Any],
        to builder: HKWorkoutRouteBuilder
    ) async throws {
        try await checked {
            completion in builder.addMetadata(metadata, completion: completion)
        }
    }

    private func add(_ samples: [HKSample], to builder: HKWorkoutBuilder) async throws {
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

    private func insert(
        _ locations: [CLLocation],
        into builder: HKWorkoutRouteBuilder
    ) async throws {
        let chunkSize = 200
        var offset = 0
        while offset < locations.count {
            let upper = min(offset + chunkSize, locations.count)
            let chunk = Array(locations[offset..<upper])
            try await checked {
                completion in builder.insertRouteData(chunk, completion: completion)
            }
            offset = upper
        }
    }

    private func finish(_ builder: HKWorkoutBuilder) async throws -> HKWorkout? {
        try await withCheckedThrowingContinuation { continuation in
            builder.finishWorkout { workout, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: workout)
                }
            }
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
                if let error {
                    continuation.resume(throwing: error)
                } else if !success {
                    continuation.resume(
                        throwing: RepairError.operation(
                            "opération HealthKit refusée"
                        )
                    )
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private enum RepairError: LocalizedError {
        case operation(String)

        var errorDescription: String? {
            switch self {
            case .operation(let message): return message
            }
        }
    }
}

/// Historical mutation is iPhone-only. This surface intentionally does not hide
/// a raw Tracker session just because an older generated HealthKit object can be
/// queried internally: the previous incident proved that criterion insufficient.
struct HistoricalHealthKitRepairView: View {
    @ObservedObject private var coordinator = HistoricalHealthKitRepairCoordinator.shared
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
                                Label(
                                    "Réparation Santé",
                                    systemImage: "wrench.and.screwdriver.fill"
                                )
                                .font(.headline.weight(.bold))

                                Text(
                                    "Reconstruction historique sur l’iPhone. Les données Tracker brutes restent intactes. Aucun ancien workout n’est supprimé automatiquement. La relecture API n’est pas une validation finale : vérifie ensuite Santé et Forme."
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
                                HistoricalRepairCard(summary: summary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Récupération")
            .onAppear { reload() }
        }
        .preferredColorScheme(.dark)
    }

    private func reload() {
        summaries = store.listSummaries().sorted { $0.startedAt > $1.startedAt }
    }
}

private struct HistoricalRepairCard: View {
    @ObservedObject private var coordinator = HistoricalHealthKitRepairCoordinator.shared
    let summary: TrackerSummary

    @State private var selection: ActivityKind?
    @State private var confirming = false

    private var activities: [ActivityKind] {
        ActivityKind.allCases.filter { !$0.isAutomatic }
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
                        .lineLimit(1)
                }
                Spacer()
                if coordinator.internallyVerifiedSessions.contains(summary.sessionID) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 14) {
                repairMetric(
                    value: repairDistance(summary.distanceMeters),
                    label: "Distance"
                )
                repairMetric(
                    value: repairDuration(summary.duration),
                    label: "Actif"
                )
                repairMetric(
                    value: summary.activeEnergyKcal.map {
                        String(format: "%.0f kcal", $0)
                    } ?? "—",
                    label: "Énergie"
                )
            }

            Picker("Sport réel", selection: $selection) {
                Text("Choisir…").tag(Optional<ActivityKind>.none)
                ForEach(activities) { activity in
                    Text(activity.label).tag(Optional(activity))
                }
            }
            .pickerStyle(.menu)

            Button {
                confirming = true
            } label: {
                Label(
                    "Reconstruire dans Santé",
                    systemImage: "heart.circle.fill"
                )
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(selection == nil || coordinator.activeSessionID != nil)

            if let status = coordinator.statusBySession[summary.sessionID] {
                Text(status)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(
                        status.contains("échouée") ? .red : .secondary
                    )
            }
        }
        .padding(14)
        .background(
            .white.opacity(0.06),
            in: RoundedRectangle(cornerRadius: 20)
        )
        .confirmationDialog(
            "Reconstruire cette séance dans Santé ?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            if let selection {
                Button("Reconstruire en \(selection.label)") {
                    coordinator.repair(
                        sessionID: summary.sessionID,
                        targetActivity: selection
                    )
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(
                "Les raw Tracker sont la source. Aucun ancien workout n’est supprimé automatiquement. Après la relecture interne, la présence dans Santé et Forme doit encore être vérifiée manuellement."
            )
        }
    }

    private func repairMetric(value: String, label: String) -> some View {
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

private func repairDistance(_ meters: Double) -> String {
    meters >= 1000
        ? String(format: "%.2f km", meters / 1000)
        : String(format: "%.0f m", meters)
}

private func repairDuration(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    return hours > 0
        ? String(format: "%dh%02d", hours, minutes)
        : "\(minutes) min"
}
