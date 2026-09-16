import CoreLocation
import Foundation
import HealthKit

extension HistoricalHealthKitRepairV4Coordinator {
    // MARK: - Raw data / route selection

    struct RawPoint: Equatable {
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

    struct RawRoutes {
        let watch: [RawPoint]
        let phone: [RawPoint]
        let pauses: [TrackerHealthRestorePause]
        let watchRawDistanceMeters: Double?
        let phoneRawDistanceMeters: Double?
    }

    struct CleanRoute {
        let source: String
        let points: [RawPoint]
        let geometryMeters: Double
        let activeGapsOver3Seconds: Int
        let maxActiveGapSeconds: Double
        let p90AccuracyMeters: Double
    }

    struct RouteChoice {
        let watch: CleanRoute
        let phone: CleanRoute
        let selected: CleanRoute?
    }

    struct ActiveInterval {
        let start: TimeInterval
        let end: TimeInterval

        var duration: TimeInterval { max(0, end - start) }
    }

    func loadRawRoutes(summary: TrackerSummary) throws -> RawRoutes {
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

    func rawPoint(
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

    /// Intentionally returns to the richer route policy that physically looked better
    /// before the aggressive post-pause prefix deletion. We preserve those coordinates
    /// and solve impossible joins at HealthKit route boundaries instead.
    func chooseRoute(
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

    func sanitize(
        source: String,
        points: [RawPoint],
        pauses: [TrackerHealthRestorePause],
        activity: ActivityKind,
        targetDistanceMeters: Double?
    ) -> CleanRoute {
        let speedLimit = maximumPlausibleSpeed(activity)
        var values = deduplicate(points).filter { !isPaused($0.timestamp, pauses: pauses) }

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

    /// Uses the cumulative raw distance only as a local noise discriminator. It never
    /// rewrites distance or coordinates, and it never skips a point when that would
    /// create a filter-induced gap longer than three seconds.
    func counterAwareFilter(_ points: [RawPoint]) -> [RawPoint] {
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
            let noiseEnvelope = min(30, max(6, current.horizontalAccuracy * 1.5))

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

    /// Fill only ACTIVE holes already absent from the raw primary stream. A hole made
    /// by filtering is not backfilled from the secondary sensor.
}
