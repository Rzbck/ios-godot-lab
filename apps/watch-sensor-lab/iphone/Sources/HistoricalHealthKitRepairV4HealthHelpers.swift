import CoreLocation
import Foundation
import HealthKit

extension HistoricalHealthKitRepairV4Coordinator {
    // MARK: - Shared helpers

    func loadSummary(sessionID: String) throws -> TrackerSummary {
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

    func sessionDirectory(sessionID: String) throws -> URL {
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

    func loadJSONL(_ url: URL) throws -> [[String: Any]] {
        try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { line in
                guard let data = String(line).data(using: .utf8) else { return nil }
                return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            }
    }

    func makePayload(
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

    func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? Double { return value }
        return nil
    }

    func generatedMetadata(
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

    func routeMetadata(
        sessionID: String,
        schema: Int,
        attemptID: String,
        sourceName: String,
        segmentIndex: Int,
        segmentCount: Int
    ) -> [String: Any] {
        [
            rawRestoreKey: true,
            sessionKey: sessionID,
            rawRestoreSchemaKey: schema,
            rawRestoreSourceKey: source,
            generationKey: generation,
            attemptKey: attemptID,
            "com.rzbck.watchsensorlab.route_source": sourceName,
            "com.rzbck.watchsensorlab.route_segment_index": segmentIndex,
            "com.rzbck.watchsensorlab.route_segment_count": segmentCount,
            HKMetadataKeyExternalUUID:
                "watchtracker-v4-route-\(sessionID)-\(attemptID)-seg-\(segmentIndex)",
        ]
    }

    func distanceIdentifier(
        for activity: ActivityKind
    ) -> HKQuantityTypeIdentifier? {
        switch activity {
        case .cycling, .handCycling: return .distanceCycling
        case .swimming, .waterFitness, .waterPolo: return .distanceSwimming
        case .walking, .running, .hiking, .trackAndField: return .distanceWalkingRunning
        default: return nil
        }
    }

    func speedIdentifier(
        for activity: ActivityKind
    ) -> HKQuantityTypeIdentifier? {
        switch activity {
        case .cycling, .handCycling: return .cyclingSpeed
        case .running, .trackAndField: return .runningSpeed
        default: return nil
        }
    }

    func deduplicate(_ points: [RawPoint]) -> [RawPoint] {
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

    func isPaused(_ timestamp: TimeInterval, pauses: [TrackerHealthRestorePause]) -> Bool {
        pauses.contains { timestamp >= $0.startedAt && timestamp <= $0.endedAt }
    }

    func intervalOverlapsPause(
        _ start: TimeInterval,
        _ end: TimeInterval,
        pauses: [TrackerHealthRestorePause]
    ) -> Bool {
        pauses.contains { start <= $0.endedAt && end >= $0.startedAt }
    }

    func impliedSpeed(_ a: RawPoint, _ b: RawPoint) -> Double {
        let delta = b.timestamp - a.timestamp
        guard delta > 0 else { return .infinity }
        return distance(a, b) / delta
    }

    func distance(_ a: RawPoint, _ b: RawPoint) -> Double {
        let radius = 6_371_000.0
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * radius * asin(min(1, sqrt(h)))
    }

    func perpendicularDeviation(
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

    func makePauses(
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

    func querySamples(
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

    func loadLocations(for route: HKWorkoutRoute) async throws -> [CLLocation] {
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

    func begin(_ builder: HKWorkoutBuilder, at date: Date) async throws {
        try await checked {
            completion in builder.beginCollection(withStart: date, completion: completion)
        }
    }

    func end(_ builder: HKWorkoutBuilder, at date: Date) async throws {
        try await checked {
            completion in builder.endCollection(withEnd: date, completion: completion)
        }
    }

    func addMetadata(
        _ metadata: [String: Any],
        to builder: HKWorkoutBuilder
    ) async throws {
        try await checked {
            completion in builder.addMetadata(metadata, completion: completion)
        }
    }

    func add(
        _ samples: [HKSample],
        to builder: HKWorkoutBuilder
    ) async throws {
        try await checked {
            completion in builder.add(samples, completion: completion)
        }
    }

    func add(
        _ events: [HKWorkoutEvent],
        to builder: HKWorkoutBuilder
    ) async throws {
        try await checked {
            completion in builder.addWorkoutEvents(events, completion: completion)
        }
    }

    func finish(_ builder: HKWorkoutBuilder) async throws -> HKWorkout? {
        try await withCheckedThrowingContinuation { continuation in
            builder.finishWorkout { workout, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: workout) }
            }
        }
    }

    func save(_ object: HKObject) async throws {
        try await checked {
            completion in healthStore.save(object, withCompletion: completion)
        }
    }

    func delete(_ objects: [HKObject]) async throws {
        guard !objects.isEmpty else { return }
        try await checked {
            completion in healthStore.delete(objects, withCompletion: completion)
        }
    }

    func checked(
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

    enum V4Error: LocalizedError {
        case operation(String)

        var errorDescription: String? {
            switch self {
            case .operation(let value): return value
            }
        }
    }
}
