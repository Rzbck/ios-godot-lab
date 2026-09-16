import CoreLocation
import Foundation
import HealthKit

extension HistoricalHealthKitRepairV4Coordinator {
    // MARK: - HealthKit creation

    struct CreatedWorkout {
        let workout: HKWorkout
        let routes: [HKWorkoutRoute]
    }

    func createHistoricalWorkout(
        payload: TrackerHealthRestorePayload,
        summary: TrackerSummary,
        activity: ActivityKind,
        route: CleanRoute,
        routeSegments: [[RawPoint]],
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
        let routedPoints = routeSegments.flatMap { $0 }
        let renderedGeometry = segmentedGeometry(routeSegments)

        var createdWorkout: HKWorkout?
        var createdRoutes: [HKWorkoutRoute] = []
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
                "com.rzbck.watchsensorlab.route_filtered_point_count": routedPoints.count,
                "com.rzbck.watchsensorlab.route_segment_count": routeSegments.count,
                "com.rzbck.watchsensorlab.route_geometry_m": renderedGeometry,
                "com.rzbck.watchsensorlab.route_selected_raw_geometry_m": route.geometryMeters,
                "com.rzbck.watchsensorlab.route_filter_strategy":
                    "trusted_counter_local_noise_hard_discontinuity_segment_split_true_raw_gap_fill_no_interpolation",
                "com.rzbck.watchsensorlab.scalar_sample_strategy":
                    "active_interval_duration_weighted_totals",
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

            let samples = try makeSamples(
                payload: payload,
                activity: activity,
                routedPoints: routedPoints,
                metadata: sampleMetadata
            )
            try await add(samples, to: builder)
            let events = makeEvents(payload: payload, attemptID: attemptID)
            if !events.isEmpty { try await add(events, to: builder) }

            try assertBuilderTotals(builder, payload: payload, activity: activity)
            try await end(builder, at: endDate)
            guard let workout = try await finish(builder) else {
                throw V4Error.operation("HealthKit n’a pas retourné le workout v4")
            }
            createdWorkout = workout

            for (index, segment) in routeSegments.enumerated() {
                let locations = makeLocations(segment)
                guard locations.count >= 2 else { continue }
                let savedRoute = try await finishIndependentRoute(
                    workout: workout,
                    locations: locations,
                    metadata: routeMetadata(
                        sessionID: payload.sessionID,
                        schema: payload.schema,
                        attemptID: attemptID,
                        sourceName: route.source,
                        segmentIndex: index,
                        segmentCount: routeSegments.count
                    )
                )
                createdRoutes.append(savedRoute)
            }
            guard !createdRoutes.isEmpty else {
                throw V4Error.operation("aucune route HealthKit segmentée créée")
            }

            createdEffort = try await HistoricalHealthKitFullFidelity.savePerceivedEffort(
                healthStore: healthStore,
                workout: workout,
                perceivedEffort: perceivedEffort,
                metadata: sampleMetadata
            )
            return CreatedWorkout(workout: workout, routes: createdRoutes)
        } catch {
            var rollback: [HKObject] = []
            if let createdEffort { rollback.append(createdEffort) }
            rollback.append(contentsOf: createdRoutes)
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

    /// Critical incident fix: scalar totals must not span the complete 40-minute wall
    /// interval when the workout contains long pause events. HealthKit interpolates
    /// samples that extend outside an activity's active timeframe. Splitting the known
    /// total across active intervals preserves the exact total instead of the observed
    /// ~0.99 km proration of a 2.80 km ride.
    func makeSamples(
        payload: TrackerHealthRestorePayload,
        activity: ActivityKind,
        routedPoints: [RawPoint],
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

        let intervals = activeIntervals(payload: payload)
        guard !intervals.isEmpty else {
            throw V4Error.operation("aucun intervalle actif pour les totaux Santé")
        }

        if let energy = payload.activeEnergyKcal,
           energy > 0,
           let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            samples.append(contentsOf: makeDistributedQuantitySamples(
                total: energy,
                type: type,
                unit: .kilocalorie(),
                intervals: intervals,
                metadata: metadata
            ))
        }
        if let identifier = distanceIdentifier(for: activity),
           payload.distanceMeters > 0,
           let type = HKQuantityType.quantityType(forIdentifier: identifier) {
            samples.append(contentsOf: makeDistributedQuantitySamples(
                total: payload.distanceMeters,
                type: type,
                unit: .meter(),
                intervals: intervals,
                metadata: metadata
            ))
        }
        if let identifier = speedIdentifier(for: activity),
           let type = HKQuantityType.quantityType(forIdentifier: identifier) {
            let unit = HKUnit.meter().unitDivided(by: .second())
            for point in routedPoints {
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

    func activeIntervals(payload: TrackerHealthRestorePayload) -> [ActiveInterval] {
        let start = payload.startedAt
        let end = payload.endedAt
        let pauses = payload.pauses
            .map { (max(start, $0.startedAt), min(end, $0.endedAt)) }
            .filter { $0.1 > $0.0 }
            .sorted { $0.0 < $1.0 }

        var intervals: [ActiveInterval] = []
        var cursor = start
        for pause in pauses {
            if pause.0 > cursor + 0.001 {
                intervals.append(ActiveInterval(start: cursor, end: pause.0))
            }
            cursor = max(cursor, pause.1)
        }
        if end > cursor + 0.001 {
            intervals.append(ActiveInterval(start: cursor, end: end))
        }
        return intervals.filter { $0.duration > 0.001 }
    }

    func makeDistributedQuantitySamples(
        total: Double,
        type: HKQuantityType,
        unit: HKUnit,
        intervals: [ActiveInterval],
        metadata: [String: Any]
    ) -> [HKQuantitySample] {
        guard total > 0 else { return [] }
        let totalDuration = intervals.reduce(0.0) { $0 + $1.duration }
        guard totalDuration > 0 else { return [] }

        var allocated = 0.0
        return intervals.enumerated().map { index, interval in
            let value: Double
            if index == intervals.count - 1 {
                value = max(0, total - allocated)
            } else {
                value = total * (interval.duration / totalDuration)
                allocated += value
            }
            return HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: unit, doubleValue: value),
                start: Date(timeIntervalSince1970: interval.start),
                end: Date(timeIntervalSince1970: interval.end),
                metadata: metadata
            )
        }
    }

    func assertBuilderTotals(
        _ builder: HKWorkoutBuilder,
        payload: TrackerHealthRestorePayload,
        activity: ActivityKind
    ) throws {
        if let identifier = distanceIdentifier(for: activity),
           let type = HKQuantityType.quantityType(forIdentifier: identifier),
           payload.distanceMeters > 0 {
            guard let meters = builder.statistics(for: type)?.sumQuantity()?.doubleValue(for: .meter()) else {
                throw V4Error.operation("distance builder HealthKit absente")
            }
            let tolerance = max(15, payload.distanceMeters * 0.04)
            guard abs(meters - payload.distanceMeters) <= tolerance else {
                throw V4Error.operation(
                    String(format: "distance builder %.0f m au lieu de %.0f m", meters, payload.distanceMeters)
                )
            }
        }
        if let energy = payload.activeEnergyKcal,
           energy > 0,
           let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            guard let kcal = builder.statistics(for: type)?.sumQuantity()?.doubleValue(for: .kilocalorie()) else {
                throw V4Error.operation("énergie builder HealthKit absente")
            }
            let tolerance = max(2, energy * 0.05)
            guard abs(kcal - energy) <= tolerance else {
                throw V4Error.operation("énergie builder incomplète")
            }
        }
    }

    func makeEvents(
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

    func makeLocations(_ points: [RawPoint]) -> [CLLocation] {
        points.map { point in
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
    }

    func finishIndependentRoute(
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

}
