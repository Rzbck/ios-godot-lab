import Foundation

/// Read-only forensic probe for historical GPS/counter mismatches.
///
/// This deliberately lives outside the recovery mutation path. It reads the raw session
/// files, compares each GPS source against the authoritative Watch cumulative-distance
/// counter, and reports the worst windows without deleting, rewriting or interpolating
/// any coordinate.
struct HistoricalRouteDiagnosticProbe {
    struct Window: Equatable {
        let source: String
        let startTimestamp: TimeInterval
        let endTimestamp: TimeInterval
        let durationSeconds: Double
        let pointCount: Int
        let pathGeometryMeters: Double
        let directGeometryMeters: Double
        let counterAdvanceMeters: Double
        let allowedPathGeometryMeters: Double
        let bridgeAllowedGeometryMeters: Double
        let pathExcessMeters: Double
        let detourMeters: Double
        let maxSourceGapSeconds: Double
        let maxCounterInterpolationGapSeconds: Double
        let bridgeWithinCounterBudget: Bool
        let pathExcessOverThreshold: Bool
        let detourOverThreshold: Bool
        let counterProvenDetour: Bool
        let diagnosis: String
    }

    struct Result: Equatable {
        let counterSource: String
        let watchPointCount: Int
        let phonePointCount: Int
        let watchCounterPointCount: Int
        let watchWindows: [Window]
        let phoneWindows: [Window]
    }

    private struct Point: Equatable {
        let timestamp: TimeInterval
        let latitude: Double
        let longitude: Double
        let horizontalAccuracy: Double
        let cumulativeDistanceMeters: Double?
        let source: String
    }

    private struct CounterEstimate {
        let value: Double
        let interpolationGapSeconds: Double
    }

    private struct Pause: Equatable {
        let start: TimeInterval
        let end: TimeInterval
    }

    func inspect(sessionID: String) throws -> Result {
        let directory = try sessionDirectory(sessionID: sessionID)
        var rows = try loadJSONL(directory.appendingPathComponent("samples.jsonl"))
        let reliable = directory.appendingPathComponent("watch_reliable.jsonl")
        if FileManager.default.fileExists(atPath: reliable.path) {
            rows.append(contentsOf: try loadJSONL(reliable))
        }

        var watch: [Point] = []
        var phone: [Point] = []
        var explicitMarks: [(TimeInterval, Bool)] = []
        var phaseMarks: [(TimeInterval, String, String)] = []

        for row in rows {
            guard let timestamp = number(row["timestamp"]) else { continue }
            let record = row["record"] as? String ?? ""
            let payload = row["payload"] as? [String: Any] ?? [:]
            let quality = row["quality"] as? [String: Any] ?? [:]

            if record == "sample" {
                switch row["kind"] as? String ?? "" {
                case "watch_location":
                    if let point = point(
                        timestamp: timestamp,
                        source: "WATCH",
                        payload: payload,
                        quality: payload,
                        includeCounter: true
                    ) {
                        watch.append(point)
                    }
                case "location":
                    if let point = point(
                        timestamp: timestamp,
                        source: "IPHONE",
                        payload: payload,
                        quality: quality,
                        includeCounter: false
                    ) {
                        phone.append(point)
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

        let cleanWatch = deduplicate(watch)
        let cleanPhone = deduplicate(phone)
        let allTimestamps = (cleanWatch + cleanPhone).map(\.timestamp)
        let start = allTimestamps.min() ?? 0
        let end = allTimestamps.max() ?? start
        let pauses = makePauses(
            explicit: explicitMarks,
            fallback: phaseMarks,
            start: start,
            end: end
        )
        let watchCounter = cleanWatch.filter { $0.cumulativeDistanceMeters != nil }

        return Result(
            counterSource: "WATCH",
            watchPointCount: cleanWatch.count,
            phonePointCount: cleanPhone.count,
            watchCounterPointCount: watchCounter.count,
            watchWindows: worstWindows(
                sourcePoints: cleanWatch,
                watchCounterPoints: watchCounter,
                pauses: pauses,
                limit: 8
            ),
            phoneWindows: worstWindows(
                sourcePoints: cleanPhone,
                watchCounterPoints: watchCounter,
                pauses: pauses,
                limit: 8
            )
        )
    }

    private func worstWindows(
        sourcePoints: [Point],
        watchCounterPoints: [Point],
        pauses: [Pause],
        limit: Int
    ) -> [Window] {
        let values = deduplicate(sourcePoints)
        let counters = deduplicate(watchCounterPoints)
        guard values.count >= 3, counters.count >= 2 else { return [] }

        var candidates: [Window] = []
        candidates.reserveCapacity(256)

        for startIndex in 0..<(values.count - 2) {
            let start = values[startIndex]
            guard let startCounter = counterEstimate(at: start.timestamp, points: counters) else {
                continue
            }

            let maxEndIndex = min(values.count - 1, startIndex + 180)
            var pathGeometry = 0.0
            var maxGap = 0.0
            var maxAccuracy = start.horizontalAccuracy

            for endIndex in (startIndex + 1)...maxEndIndex {
                let previous = values[endIndex - 1]
                let end = values[endIndex]
                let gap = max(0, end.timestamp - previous.timestamp)
                maxGap = max(maxGap, gap)
                maxAccuracy = max(maxAccuracy, end.horizontalAccuracy)
                pathGeometry += distance(previous, end)

                guard endIndex >= startIndex + 2 else { continue }
                if intervalOverlapsPause(start.timestamp, end.timestamp, pauses: pauses) {
                    break
                }
                guard let endCounter = counterEstimate(at: end.timestamp, points: counters),
                      endCounter.value >= startCounter.value else {
                    continue
                }

                let counterAdvance = endCounter.value - startCounter.value
                let directGeometry = distance(start, end)
                let accuracyBudget = min(
                    140,
                    max(25, start.horizontalAccuracy + end.horizontalAccuracy + maxAccuracy)
                )
                let allowedPath = counterAdvance * 1.35 + accuracyBudget
                let bridgeAllowed = counterAdvance * 1.20 + accuracyBudget
                let pathExcess = pathGeometry - allowedPath
                let detour = pathGeometry - directGeometry
                let minimumExcess = max(70, counterAdvance * 0.20)
                let minimumDetour = max(60, counterAdvance * 0.15)
                let pathExcessOverThreshold = pathExcess > minimumExcess
                let detourOverThreshold = detour > minimumDetour
                let bridgeWithin = directGeometry <= bridgeAllowed
                let counterProven = pathExcessOverThreshold
                    && detourOverThreshold
                    && bridgeWithin

                // Keep only windows with a meaningful counter mismatch. We still retain
                // cases that fail one removal condition so the API explains why the
                // production filter did not remove them.
                guard pathExcess > 20 || detour > 60 else { continue }

                let diagnosis: String
                if counterProven {
                    diagnosis = "counter_proven_detour"
                } else if !pathExcessOverThreshold {
                    diagnosis = "path_excess_below_filter_threshold"
                } else if !detourOverThreshold {
                    diagnosis = "path_excess_without_return_detour"
                } else if !bridgeWithin {
                    diagnosis = "bridge_outside_counter_budget"
                } else {
                    diagnosis = "not_filterable"
                }

                candidates.append(
                    Window(
                        source: start.source,
                        startTimestamp: start.timestamp,
                        endTimestamp: end.timestamp,
                        durationSeconds: max(0, end.timestamp - start.timestamp),
                        pointCount: endIndex - startIndex + 1,
                        pathGeometryMeters: pathGeometry,
                        directGeometryMeters: directGeometry,
                        counterAdvanceMeters: counterAdvance,
                        allowedPathGeometryMeters: allowedPath,
                        bridgeAllowedGeometryMeters: bridgeAllowed,
                        pathExcessMeters: pathExcess,
                        detourMeters: detour,
                        maxSourceGapSeconds: maxGap,
                        maxCounterInterpolationGapSeconds: max(
                            startCounter.interpolationGapSeconds,
                            endCounter.interpolationGapSeconds
                        ),
                        bridgeWithinCounterBudget: bridgeWithin,
                        pathExcessOverThreshold: pathExcessOverThreshold,
                        detourOverThreshold: detourOverThreshold,
                        counterProvenDetour: counterProven,
                        diagnosis: diagnosis
                    )
                )
            }
        }

        let sorted = candidates.sorted { lhs, rhs in
            if lhs.pathExcessMeters != rhs.pathExcessMeters {
                return lhs.pathExcessMeters > rhs.pathExcessMeters
            }
            return lhs.detourMeters > rhs.detourMeters
        }

        var selected: [Window] = []
        for candidate in sorted {
            let tooSimilar = selected.contains { existing in
                overlapRatio(candidate, existing) > 0.80
            }
            if tooSimilar { continue }
            selected.append(candidate)
            if selected.count >= limit { break }
        }
        return selected
    }

    private func overlapRatio(_ lhs: Window, _ rhs: Window) -> Double {
        let overlapStart = max(lhs.startTimestamp, rhs.startTimestamp)
        let overlapEnd = min(lhs.endTimestamp, rhs.endTimestamp)
        let overlap = max(0, overlapEnd - overlapStart)
        let shortest = max(0.001, min(lhs.durationSeconds, rhs.durationSeconds))
        return overlap / shortest
    }

    private func counterEstimate(at timestamp: TimeInterval, points: [Point]) -> CounterEstimate? {
        guard let first = points.first,
              let last = points.last,
              timestamp >= first.timestamp,
              timestamp <= last.timestamp else {
            return nil
        }

        var low = 0
        var high = points.count - 1
        while low <= high {
            let mid = (low + high) / 2
            let point = points[mid]
            if abs(point.timestamp - timestamp) < 0.0005,
               let value = point.cumulativeDistanceMeters {
                return CounterEstimate(value: value, interpolationGapSeconds: 0)
            }
            if point.timestamp < timestamp {
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        let upperIndex = low
        let lowerIndex = upperIndex - 1
        guard lowerIndex >= 0,
              upperIndex < points.count,
              let lowerValue = points[lowerIndex].cumulativeDistanceMeters,
              let upperValue = points[upperIndex].cumulativeDistanceMeters,
              upperValue >= lowerValue else {
            return nil
        }

        let lower = points[lowerIndex]
        let upper = points[upperIndex]
        let span = upper.timestamp - lower.timestamp
        guard span > 0, span <= 8 else { return nil }
        let fraction = min(1, max(0, (timestamp - lower.timestamp) / span))
        return CounterEstimate(
            value: lowerValue + (upperValue - lowerValue) * fraction,
            interpolationGapSeconds: span
        )
    }

    private func point(
        timestamp: TimeInterval,
        source: String,
        payload: [String: Any],
        quality: [String: Any],
        includeCounter: Bool
    ) -> Point? {
        guard let latitude = number(payload["latitude"]),
              let longitude = number(payload["longitude"]),
              (-90...90).contains(latitude),
              (-180...180).contains(longitude),
              let horizontal = number(quality["horizontal_accuracy_m"]),
              horizontal >= 0,
              horizontal <= 50 else {
            return nil
        }
        return Point(
            timestamp: timestamp,
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracy: horizontal,
            cumulativeDistanceMeters: includeCounter ? number(payload["distance_m"]) : nil,
            source: source
        )
    }

    private func deduplicate(_ points: [Point]) -> [Point] {
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

    private func makePauses(
        explicit: [(TimeInterval, Bool)],
        fallback: [(TimeInterval, String, String)],
        start: TimeInterval,
        end: TimeInterval
    ) -> [Pause] {
        var marks = explicit.sorted { $0.0 < $1.0 }
        if !marks.contains(where: { $0.1 }) {
            marks = fallback.sorted { $0.0 < $1.0 }.compactMap { item in
                if item.1 == "active", item.2 == "paused" { return (item.0, true) }
                if item.1 == "paused", item.2 == "active" { return (item.0, false) }
                if item.1 == "paused", item.2 == "ended" { return (min(item.0, end), false) }
                return nil
            }
        }

        var result: [Pause] = []
        var openPause: TimeInterval?
        for (rawTimestamp, pause) in marks {
            let timestamp = min(max(rawTimestamp, start), end)
            if pause {
                if openPause == nil { openPause = timestamp }
            } else if let pauseStart = openPause, timestamp > pauseStart {
                result.append(Pause(start: pauseStart, end: timestamp))
                openPause = nil
            }
        }
        if let pauseStart = openPause, end > pauseStart {
            result.append(Pause(start: pauseStart, end: end))
        }
        return result
    }

    private func intervalOverlapsPause(
        _ start: TimeInterval,
        _ end: TimeInterval,
        pauses: [Pause]
    ) -> Bool {
        pauses.contains { start <= $0.end && end >= $0.start }
    }

    private func distance(_ a: Point, _ b: Point) -> Double {
        let radius = 6_371_000.0
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * radius * asin(min(1, sqrt(h)))
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
            throw ProbeError.operation("session Tracker locale absente")
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

    private func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? Double { return value }
        return nil
    }

    private enum ProbeError: LocalizedError {
        case operation(String)

        var errorDescription: String? {
            switch self {
            case .operation(let value): return value
            }
        }
    }
}
