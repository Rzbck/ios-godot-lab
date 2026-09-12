import CoreLocation
import Foundation
import HealthKit

/// Supplemental historical reconstruction helpers.
///
/// This file intentionally works only from Tracker-owned raw/session data. It
/// never reads another app's workout to invent missing values. Data that wasn't
/// captured (for example real cycling power) stays absent rather than being
/// fabricated.
enum HistoricalHealthKitFullFidelity {
    private static let rawRestoreKey = "com.rzbck.watchsensorlab.raw_restoration"
    private static let sessionKey = "com.rzbck.watchsensorlab.session_id"
    private static let rawRestoreSourceKey = "com.rzbck.watchsensorlab.raw_restoration_source"
    private static let generationKey = "com.rzbck.watchsensorlab.historical_generation"
    private static let attemptKey = "com.rzbck.watchsensorlab.historical_attempt_id"

    static let generation = "ios_historical_v3_full"
    static let source = "tracker_raw_ios_v3_full"

    static func loadSummary(sessionID: String) throws -> TrackerSummary {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        let url = documents
            .appendingPathComponent("Sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
            .appendingPathComponent("summary.json")

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TrackerSummary.self, from: Data(contentsOf: url))
    }

    static func savedPerceivedEffort(sessionID: String) -> Int? {
        let value = UserDefaults.standard.integer(
            forKey: "tracker.perceivedEffort.\(sessionID)"
        )
        return (1...10).contains(value) ? value : nil
    }

    static func requiredQuantityIdentifiers(
        payload: TrackerHealthRestorePayload,
        activity: ActivityKind,
        perceivedEffort: Int?
    ) -> [HKQuantityTypeIdentifier] {
        var values: [HKQuantityTypeIdentifier] = []

        if expectedSpeedSampleCount(payload: payload, activity: activity) > 0,
           let speed = speedIdentifier(for: activity) {
            values.append(speed)
        }

        if perceivedEffort != nil {
            if #available(iOS 18.0, *) {
                values.append(.workoutEffortScore)
            }
        }

        return values
    }

    static func workoutMetadata(
        summary: TrackerSummary,
        payload: TrackerHealthRestorePayload,
        activity: ActivityKind,
        attemptID: String
    ) -> [String: Any] {
        let speedUnit = HKUnit.meter().unitDivided(by: .second())
        var metadata: [String: Any] = [
            HKMetadataKeyWorkoutBrandName: "Watch Tracker",
            HKMetadataKeyIndoorWorkout: payload.locations.count < 2,
            HKMetadataKeyExternalUUID: "watchtracker-historical-\(payload.sessionID)-\(attemptID)",
            "com.rzbck.watchsensorlab.full_fidelity": true,
            "com.rzbck.watchsensorlab.raw_route_point_count": payload.locations.count,
            "com.rzbck.watchsensorlab.raw_heart_rate_count": payload.heartRates.count,
            "com.rzbck.watchsensorlab.raw_pause_count": payload.pauses.count,
            "com.rzbck.watchsensorlab.raw_wall_duration": max(0, payload.endedAt - payload.startedAt),
            "com.rzbck.watchsensorlab.average_heart_rate_bpm": summary.averageHeartRate,
            "com.rzbck.watchsensorlab.target_activity": activity.rawValue,
        ]

        if summary.distanceMeters > 0, summary.duration > 0 {
            metadata[HKMetadataKeyAverageSpeed] = HKQuantity(
                unit: speedUnit,
                doubleValue: summary.distanceMeters / summary.duration
            )
        }
        if summary.maxSpeedMps > 0 {
            metadata[HKMetadataKeyMaximumSpeed] = HKQuantity(
                unit: speedUnit,
                doubleValue: summary.maxSpeedMps
            )
        }
        if summary.elevationGainMeters > 0 {
            metadata[HKMetadataKeyElevationAscended] = HKQuantity(
                unit: .meter(),
                doubleValue: summary.elevationGainMeters
            )
        }
        if summary.elevationLossMeters > 0 {
            metadata[HKMetadataKeyElevationDescended] = HKQuantity(
                unit: .meter(),
                doubleValue: summary.elevationLossMeters
            )
        }
        if let cadence = summary.averageCadenceSPM, cadence > 0 {
            // Tracker's historical cadence may come from CMPedometer and isn't
            // necessarily pedal cadence. Preserve it as provenance instead of
            // falsely writing HKQuantityType.cyclingCadence.
            metadata["com.rzbck.watchsensorlab.average_cadence_spm"] = cadence
        }
        if let maxHeartRate = summary.maxHeartRate, maxHeartRate > 0 {
            metadata["com.rzbck.watchsensorlab.max_heart_rate_bpm"] = maxHeartRate
        }
        if let segments = summary.segments, !segments.isEmpty {
            metadata["com.rzbck.watchsensorlab.segment_count"] = segments.count
        }

        let estimate = TrackerEffortEstimator().estimate(summary: summary)
        metadata["com.rzbck.watchsensorlab.tracker_estimated_effort"] = estimate.score
        metadata["com.rzbck.watchsensorlab.tracker_estimated_effort_label"] = estimate.label

        addWeatherMetadata(summary: summary, to: &metadata)
        return metadata
    }

    static func routeMetadata(
        sessionID: String,
        schema: Int,
        attemptID: String
    ) -> [String: Any] {
        [
            rawRestoreKey: true,
            sessionKey: sessionID,
            rawRestoreSourceKey: source,
            generationKey: generation,
            attemptKey: attemptID,
            "com.rzbck.watchsensorlab.raw_restoration_schema": schema,
            HKMetadataKeyExternalUUID: "watchtracker-route-\(sessionID)-\(attemptID)",
        ]
    }

    static func makeSpeedSamples(
        payload: TrackerHealthRestorePayload,
        activity: ActivityKind,
        metadata: [String: Any]
    ) -> [HKQuantitySample] {
        guard let identifier = speedIdentifier(for: activity),
              let type = HKQuantityType.quantityType(forIdentifier: identifier) else {
            return []
        }

        let unit = HKUnit.meter().unitDivided(by: .second())
        return payload.locations.compactMap { point in
            guard let speed = point.speedMps,
                  speed >= 0,
                  speed < 100,
                  point.timestamp >= payload.startedAt,
                  point.timestamp <= payload.endedAt else {
                return nil
            }
            let date = Date(timeIntervalSince1970: point.timestamp)
            return HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: unit, doubleValue: speed),
                start: date,
                end: date,
                metadata: metadata
            )
        }
    }

    static func expectedSpeedSampleCount(
        payload: TrackerHealthRestorePayload,
        activity: ActivityKind
    ) -> Int {
        guard speedIdentifier(for: activity) != nil else { return 0 }
        return payload.locations.reduce(into: 0) { count, point in
            if let speed = point.speedMps,
               speed >= 0,
               speed < 100,
               point.timestamp >= payload.startedAt,
               point.timestamp <= payload.endedAt {
                count += 1
            }
        }
    }

    static func finishIndependentRoute(
        healthStore: HKHealthStore,
        workout: HKWorkout,
        locations: [CLLocation],
        metadata: [String: Any]
    ) async throws -> HKWorkoutRoute {
        guard locations.count >= 2 else {
            throw FidelityError.operation("parcours GPS insuffisant pour créer la route")
        }

        // For historical post-hoc reconstruction we intentionally use an
        // independent builder, then finishRoute(with:) after the workout has
        // already been saved. That API explicitly saves and associates the
        // route with the provided workout. The attached builder path was
        // durable in HealthKit but not rendered by Fitness on the test device.
        let builder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
        let chunkSize = 200
        var offset = 0
        while offset < locations.count {
            let upper = min(offset + chunkSize, locations.count)
            let chunk = Array(locations[offset..<upper])
            try await checked { completion in
                builder.insertRouteData(chunk, completion: completion)
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
                    continuation.resume(
                        throwing: FidelityError.operation(
                            "HealthKit n’a pas retourné la route historique"
                        )
                    )
                }
            }
        }
    }

    static func savePerceivedEffort(
        healthStore: HKHealthStore,
        workout: HKWorkout,
        perceivedEffort: Int?,
        metadata: [String: Any]
    ) async throws -> HKQuantitySample? {
        guard let perceivedEffort, (1...10).contains(perceivedEffort) else {
            return nil
        }

        if #available(iOS 18.0, *) {
            guard let type = HKQuantityType.quantityType(forIdentifier: .workoutEffortScore) else {
                throw FidelityError.operation("type HealthKit effort indisponible")
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
            try await save(sample, healthStore: healthStore)

            let related = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Bool, any Error>) in
                healthStore.relateWorkoutEffortSample(
                    sample,
                    with: workout,
                    activity: nil
                ) { success, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: success)
                    }
                }
            }
            guard related else {
                throw FidelityError.operation("HealthKit a refusé l’association de l’effort")
            }
            return sample
        }

        return nil
    }

    static func verifyPerceivedEffort(
        healthStore: HKHealthStore,
        workout: HKWorkout,
        perceivedEffort: Int?,
        attemptID: String
    ) async throws {
        guard let perceivedEffort, (1...10).contains(perceivedEffort) else { return }
        guard #available(iOS 18.0, *) else { return }
        guard let type = HKQuantityType.quantityType(forIdentifier: .workoutEffortScore) else {
            throw FidelityError.operation("type HealthKit effort indisponible à la relecture")
        }

        let predicate = HKQuery.predicateForWorkoutEffortSamplesRelated(
            workout: workout,
            activity: nil
        )
        let samples = try await querySamples(
            healthStore: healthStore,
            type: type,
            predicate: predicate
        )
        let unit = HKUnit.appleEffortScore()
        let matching = samples
            .compactMap { $0 as? HKQuantitySample }
            .first {
                ($0.metadata?[attemptKey] as? String) == attemptID
                    && abs($0.quantity.doubleValue(for: unit) - Double(perceivedEffort)) < 0.01
            }
        guard matching != nil else {
            throw FidelityError.operation("effort Apple non relu après restauration")
        }
    }

    static func verifyWorkoutMetadata(
        workout: HKWorkout,
        summary: TrackerSummary
    ) throws {
        let speedUnit = HKUnit.meter().unitDivided(by: .second())
        if summary.maxSpeedMps > 0 {
            guard let quantity = workout.metadata?[HKMetadataKeyMaximumSpeed] as? HKQuantity,
                  abs(quantity.doubleValue(for: speedUnit) - summary.maxSpeedMps)
                    <= max(0.5, summary.maxSpeedMps * 0.08) else {
                throw FidelityError.operation("vitesse maximale absente après relecture")
            }
        }
        if summary.elevationGainMeters > 0 {
            guard let quantity = workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity,
                  abs(quantity.doubleValue(for: .meter()) - summary.elevationGainMeters)
                    <= max(3, summary.elevationGainMeters * 0.08) else {
                throw FidelityError.operation("dénivelé positif absent après relecture")
            }
        }
        if summary.elevationLossMeters > 0 {
            guard let quantity = workout.metadata?[HKMetadataKeyElevationDescended] as? HKQuantity,
                  abs(quantity.doubleValue(for: .meter()) - summary.elevationLossMeters)
                    <= max(3, summary.elevationLossMeters * 0.08) else {
                throw FidelityError.operation("dénivelé négatif absent après relecture")
            }
        }
        if let snapshots = summary.weatherSnapshots, !snapshots.isEmpty,
           snapshots.contains(where: { $0.temperatureC != nil }) {
            guard workout.metadata?[HKMetadataKeyWeatherTemperature] is HKQuantity else {
                throw FidelityError.operation("météo historique absente après relecture")
            }
        }
    }

    static func speedIdentifier(for activity: ActivityKind) -> HKQuantityTypeIdentifier? {
        switch activity {
        case .cycling:
            return .cyclingSpeed
        case .running:
            return .runningSpeed
        default:
            return nil
        }
    }

    private static func addWeatherMetadata(
        summary: TrackerSummary,
        to metadata: inout [String: Any]
    ) {
        guard let snapshots = summary.weatherSnapshots, !snapshots.isEmpty else { return }

        if let temperature = mean(snapshots.compactMap(\.temperatureC)) {
            metadata[HKMetadataKeyWeatherTemperature] = HKQuantity(
                unit: .degreeCelsius(),
                doubleValue: temperature
            )
        }
        if let humidityPercent = mean(snapshots.compactMap(\.relativeHumidityPercent)) {
            metadata[HKMetadataKeyWeatherHumidity] = HKQuantity(
                unit: .percent(),
                doubleValue: min(1, max(0, humidityPercent / 100.0))
            )
        }
        if let pressureHPA = mean(snapshots.compactMap(\.pressureHPA)) {
            metadata[HKMetadataKeyBarometricPressure] = HKQuantity(
                unit: .pascal(),
                doubleValue: pressureHPA * 100.0
            )
        }
        if let condition = dominantWeatherCondition(snapshots.compactMap(\.weatherCode)) {
            metadata[HKMetadataKeyWeatherCondition] = NSNumber(value: condition.rawValue)
        }
        if let apparent = mean(snapshots.compactMap(\.apparentTemperatureC)) {
            metadata["com.rzbck.watchsensorlab.weather_apparent_temperature_c"] = apparent
        }
        if let wind = mean(snapshots.compactMap(\.windSpeedKPH)) {
            metadata["com.rzbck.watchsensorlab.weather_wind_speed_kph"] = wind
        }
        if let direction = circularMeanDegrees(snapshots.compactMap(\.windDirectionDegrees)) {
            metadata["com.rzbck.watchsensorlab.weather_wind_direction_degrees"] = direction
        }
        if let gust = snapshots.compactMap(\.windGustKPH).max() {
            metadata["com.rzbck.watchsensorlab.weather_wind_gust_kph"] = gust
        }
        metadata["com.rzbck.watchsensorlab.weather_provider"] =
            snapshots.map(\.provider).first ?? "unknown"
    }

    private static func dominantWeatherCondition(_ codes: [Int]) -> HKWeatherCondition? {
        guard !codes.isEmpty else { return nil }
        var counts: [Int: Int] = [:]
        for code in codes { counts[code, default: 0] += 1 }
        guard let code = counts.max(by: { $0.value < $1.value })?.key else { return nil }

        switch code {
        case 0: return .clear
        case 1: return .fair
        case 2: return .partlyCloudy
        case 3: return .cloudy
        case 45, 48: return .foggy
        case 51, 53, 55: return .drizzle
        case 56, 57: return .freezingDrizzle
        case 61, 63, 65, 80, 81, 82: return .showers
        case 66, 67: return .freezingRain
        case 71, 73, 75, 77, 85, 86: return .snow
        case 95, 96, 99: return .thunderstorms
        default: return .none
        }
    }

    private static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func circularMeanDegrees(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let vectors = values.map { value -> (Double, Double) in
            let radians = value * .pi / 180.0
            return (cos(radians), sin(radians))
        }
        let x = vectors.reduce(0) { $0 + $1.0 }
        let y = vectors.reduce(0) { $0 + $1.1 }
        guard abs(x) > 0.000_001 || abs(y) > 0.000_001 else { return nil }
        let degrees = atan2(y, x) * 180.0 / .pi
        return (degrees + 360.0).truncatingRemainder(dividingBy: 360.0)
    }

    private static func save(
        _ sample: HKSample,
        healthStore: HKHealthStore
    ) async throws {
        try await checked { completion in
            healthStore.save(sample, withCompletion: completion)
        }
    }

    private static func querySamples(
        healthStore: HKHealthStore,
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

    private static func checked(
        _ operation: (@escaping (Bool, Error?) -> Void) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, any Error>) in
            operation { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if !success {
                    continuation.resume(
                        throwing: FidelityError.operation(
                            "opération HealthKit full-fidelity refusée"
                        )
                    )
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private enum FidelityError: LocalizedError {
        case operation(String)

        var errorDescription: String? {
            switch self {
            case .operation(let message): return message
            }
        }
    }
}
