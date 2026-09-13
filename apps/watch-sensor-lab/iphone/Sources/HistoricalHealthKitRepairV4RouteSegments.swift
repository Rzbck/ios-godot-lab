import CoreLocation
import Foundation
import HealthKit

extension HistoricalHealthKitRepairV4Coordinator {
    func mergeActiveGaps(
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
                  impliedSpeed(last, end) <= speedLimit else {
                continue
            }
            merged.append(contentsOf: bridge)
            inserted += bridge.count
        }
        if let last = primaryPoints.last { merged.append(last) }

        let sourceName = inserted > 0
            ? "\(primary.source)+\(secondary.source)"
            : primary.source
        return makeCleanRoute(source: sourceName, points: deduplicate(merged), pauses: pauses)
    }

    /// Preserve the richer reconstruction but cut joins that would otherwise make
    /// Fitness invent a straight line across a pause or a real capture hole. Points
    /// on both sides survive; HealthKit receives separate HKWorkoutRoute objects.
    func segmentRouteForHealthKit(
        route: CleanRoute,
        pauses: [TrackerHealthRestorePause],
        activity: ActivityKind
    ) -> [[RawPoint]] {
        let ordered = deduplicate(route.points)
        guard let first = ordered.first else { return [] }
        let watchCounterPoints = ordered.filter {
            $0.source == "WATCH" && $0.cumulativeDistanceMeters != nil
        }
        var result: [[RawPoint]] = []
        var current: [RawPoint] = [first]

        for point in ordered.dropFirst() {
            let previous = current.last ?? point
            if isHardRouteDiscontinuity(
                previous,
                point,
                watchCounterPoints: watchCounterPoints,
                pauses: pauses,
                activity: activity
            ) {
                if current.count >= 2 { result.append(current) }
                current = [point]
            } else {
                current.append(point)
            }
        }
        if current.count >= 2 { result.append(current) }
        return result
    }

    func isHardRouteDiscontinuity(
        _ start: RawPoint,
        _ end: RawPoint,
        watchCounterPoints: [RawPoint],
        pauses: [TrackerHealthRestorePause],
        activity: ActivityKind
    ) -> Bool {
        // Never ask Fitness to draw a connector across an explicit pause. The two
        // valid traces remain associated with the same workout as separate routes.
        if intervalOverlapsPause(start.timestamp, end.timestamp, pauses: pauses) {
            return true
        }

        let delta = end.timestamp - start.timestamp
        guard delta > 0 else { return true }

        // A >20 s active hole is real missing GPS, not evidence for a straight path.
        // Preserve both sides and cut only the join.
        if delta > 20 {
            return true
        }

        let geometry = distance(start, end)
        let accuracyBudget = min(
            120,
            max(20, start.horizontalAccuracy + end.horizontalAccuracy)
        )

        // The Watch cumulative counter is the scalar authority for this incident.
        // Align it to every final connector timestamp, including WATCH<->IPHONE joins,
        // so a mixed-source bridge cannot bypass the counter-vs-geometry guard.
        if let startDistance = alignedWatchCounterMeters(
            at: start.timestamp,
            watchPoints: watchCounterPoints
        ),
           let endDistance = alignedWatchCounterMeters(
            at: end.timestamp,
            watchPoints: watchCounterPoints
        ),
           endDistance >= startDistance {
            let counterAdvance = endDistance - startDistance
            let counterAllowance = counterAdvance * 1.40 + accuracyBudget
            if geometry > max(150, counterAllowance) {
                return true
            }
        }

        let kinematicAllowance = maximumPlausibleSpeed(activity)
            * max(1, delta)
            * 1.20
            + accuracyBudget
        return geometry > max(180, kinematicAllowance)
    }

    /// Estimate the authoritative Watch cumulative counter at a final route timestamp.
    /// Exact Watch timestamps use the recorded value. Mixed-source timestamps may use
    /// linear interpolation only when bracketed by nearby Watch counter samples; this
    /// never fabricates a GPS coordinate or changes the recorded workout distance.
    func alignedWatchCounterMeters(
        at timestamp: TimeInterval,
        watchPoints: [RawPoint]
    ) -> Double? {
        guard !watchPoints.isEmpty else { return nil }
        var before: RawPoint?
        var after: RawPoint?

        for point in watchPoints {
            guard let _ = point.cumulativeDistanceMeters else { continue }
            if point.timestamp == timestamp {
                return point.cumulativeDistanceMeters
            }
            if point.timestamp < timestamp {
                before = point
                continue
            }
            after = point
            break
        }

        guard let before,
              let after,
              let beforeDistance = before.cumulativeDistanceMeters,
              let afterDistance = after.cumulativeDistanceMeters,
              afterDistance >= beforeDistance else {
            return nil
        }

        let span = after.timestamp - before.timestamp
        guard span > 0,
              timestamp - before.timestamp <= 8,
              after.timestamp - timestamp <= 8 else {
            return nil
        }

        let fraction = (timestamp - before.timestamp) / span
        return beforeDistance + (afterDistance - beforeDistance) * fraction
    }

    func segmentedGeometry(_ segments: [[RawPoint]]) -> Double {
        segments.reduce(0.0) { total, segment in
            total + zip(segment, segment.dropFirst()).reduce(0.0) {
                $0 + distance($1.0, $1.1)
            }
        }
    }

    func denoiseForDistance(
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
                let noiseEnvelope = min(30, max(6, point.horizontalAccuracy * 1.5))
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

    func makeCleanRoute(
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

    func routeScore(_ route: CleanRoute, summaryMeters: Double) -> Double {
        let geometryPenalty = summaryMeters > 100
            ? min(400, abs(route.geometryMeters - summaryMeters) / 10)
            : 0
        return Double(route.activeGapsOver3Seconds) * 30
            + min(route.maxActiveGapSeconds, 60) * 3
            + route.p90AccuracyMeters
            + geometryPenalty
            + (route.points.count < 100 ? 500 : 0)
    }

    func maximumPlausibleSpeed(_ activity: ActivityKind) -> Double {
        switch activity {
        case .walking, .hiking: return 5
        case .running, .trackAndField: return 12
        case .cycling, .handCycling: return 25
        default: return 25
        }
    }

    func counterAgrees(summaryMeters: Double, rawMeters: Double?) -> Bool {
        guard summaryMeters > 100, let rawMeters, rawMeters > 100 else { return false }
        let tolerance = max(150, summaryMeters * 0.12)
        return abs(rawMeters - summaryMeters) <= tolerance
    }

    func distanceReferenceSource(
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

    func hasDistanceConflict(
        summaryMeters: Double,
        watchRawMeters: Double?,
        phoneRawMeters: Double?
    ) -> Bool {
        guard summaryMeters > 100 else { return false }
        if counterAgrees(summaryMeters: summaryMeters, rawMeters: watchRawMeters)
            || counterAgrees(summaryMeters: summaryMeters, rawMeters: phoneRawMeters) {
            return false
        }
        return true
    }

    func hasRouteGeometryConflict(
        summaryMeters: Double,
        renderedGeometryMeters: Double
    ) -> Bool {
        guard summaryMeters > 100, renderedGeometryMeters > 0 else { return false }
        let tolerance = max(220, summaryMeters * 0.15)
        return abs(renderedGeometryMeters - summaryMeters) > tolerance
    }

    func hasSevereRouteCounterConflict(
        summaryMeters: Double,
        renderedGeometryMeters: Double
    ) -> Bool {
        guard summaryMeters > 100, renderedGeometryMeters > 0 else { return false }
        let toleratedExcess = max(350, summaryMeters * 0.20)
        return renderedGeometryMeters - summaryMeters > toleratedExcess
    }

    func hasRouteContinuityConflict(_ route: CleanRoute?) -> Bool {
        guard let route else { return false }
        return route.maxActiveGapSeconds > 20
    }
}
