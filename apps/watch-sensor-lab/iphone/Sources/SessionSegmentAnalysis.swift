import Foundation
import SwiftUI

struct SessionSegmentMetrics: Identifiable, Equatable {
    let id: String
    let activity: String
    let startedAt: Date
    let endedAt: Date
    let activeDuration: TimeInterval
    let pausedDuration: TimeInterval
    let distanceMeters: Double?
    let activeEnergyKcal: Double?
    let elevationGainMeters: Double?
    let elevationLossMeters: Double?
    let averageHeartRateBPM: Double?
    let maxHeartRateBPM: Double?
    let maxSpeedMps: Double?
    let averageCadenceSPM: Double?
    let authoritativeSampleCount: Int

    var wallDuration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }
}

struct SessionSegmentAnalyzer {
    private struct MetricPoint {
        let timestamp: Date
        let distanceMeters: Double?
        let activeEnergyKcal: Double?
        let elevationGainMeters: Double?
        let elevationLossMeters: Double?
        let heartRateBPM: Double?
        let speedMps: Double?
        let cadenceSPM: Double?
    }

    func analyze(summary: TrackerSummary) -> [SessionSegmentMetrics] {
        guard let segments = summary.segments, !segments.isEmpty else { return [] }
        let points = loadMetricPoints(sessionID: summary.sessionID)
        let pauseReport = SessionPauseAnalyzer().analyze(summary: summary)

        return segments.compactMap { segment in
            guard let rawEnd = segment.endedAt else { return nil }
            let start = max(summary.startedAt, segment.startedAt)
            let end = min(summary.endedAt, max(start, rawEnd))
            guard end > start else { return nil }

            let segmentPoints = points.filter { $0.timestamp >= start && $0.timestamp <= end }
            let pausedDuration = pauseOverlap(
                start: start,
                end: end,
                pauseReport: pauseReport,
                isOnlySegment: segments.count == 1
            )
            let activeDuration = max(0, end.timeIntervalSince(start) - pausedDuration)

            let startPoint = latestPoint(atOrBefore: start, in: points)
            let endPoint = latestPoint(atOrBefore: end, in: points)

            let distance = segment.distanceMeters
                ?? cumulativeDelta(
                    start: startPoint?.distanceMeters,
                    end: endPoint?.distanceMeters,
                    allowZeroStart: start.timeIntervalSince(summary.startedAt) < 5
                )
            let energy = cumulativeDelta(
                start: startPoint?.activeEnergyKcal,
                end: endPoint?.activeEnergyKcal,
                allowZeroStart: start.timeIntervalSince(summary.startedAt) < 5
            )
            let gain = cumulativeDelta(
                start: startPoint?.elevationGainMeters,
                end: endPoint?.elevationGainMeters,
                allowZeroStart: start.timeIntervalSince(summary.startedAt) < 5
            )
            let loss = cumulativeDelta(
                start: startPoint?.elevationLossMeters,
                end: endPoint?.elevationLossMeters,
                allowZeroStart: start.timeIntervalSince(summary.startedAt) < 5
            )

            let heartRates = segmentPoints.compactMap(\.heartRateBPM).filter { $0 > 0 }
            let speeds = segmentPoints.compactMap(\.speedMps).filter { $0 >= 0 }
            let cadences = segmentPoints.compactMap(\.cadenceSPM).filter { $0 > 0 }

            return SessionSegmentMetrics(
                id: segment.id,
                activity: segment.activity,
                startedAt: start,
                endedAt: end,
                activeDuration: activeDuration,
                pausedDuration: pausedDuration,
                distanceMeters: distance,
                activeEnergyKcal: energy,
                elevationGainMeters: gain,
                elevationLossMeters: loss,
                averageHeartRateBPM: average(heartRates),
                maxHeartRateBPM: heartRates.max(),
                maxSpeedMps: speeds.max(),
                averageCadenceSPM: average(cadences),
                authoritativeSampleCount: segmentPoints.count
            )
        }
    }

    private func loadMetricPoints(sessionID: String) -> [MetricPoint] {
        guard let directory = sessionDirectory(sessionID: sessionID) else { return [] }
        let urls = [
            directory.appendingPathComponent("samples.jsonl"),
            directory.appendingPathComponent("watch_reliable.jsonl"),
        ]

        var points: [MetricPoint] = []
        var signatures = Set<String>()

        for url in urls {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let data = String(line).data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      object["record"] as? String == "sample",
                      let timestampValue = object["timestamp"] as? Double,
                      let kind = object["kind"] as? String,
                      let payload = object["payload"] as? [String: Any] else { continue }

                guard kind == "authority_metrics" || kind == "watch_location" || kind == "heart_rate" || kind == "pedometer" else {
                    continue
                }

                let roundedTimestamp = Int((timestampValue * 2).rounded())
                let signature = "\(kind)|\(roundedTimestamp)|\(payload["authority_revision"] ?? "")"
                guard signatures.insert(signature).inserted else { continue }

                var point = MetricPoint(
                    timestamp: Date(timeIntervalSince1970: timestampValue),
                    distanceMeters: nil,
                    activeEnergyKcal: nil,
                    elevationGainMeters: nil,
                    elevationLossMeters: nil,
                    heartRateBPM: nil,
                    speedMps: nil,
                    cadenceSPM: nil
                )

                switch kind {
                case "authority_metrics":
                    point = MetricPoint(
                        timestamp: point.timestamp,
                        distanceMeters: payload["distance_m"] as? Double,
                        activeEnergyKcal: payload["active_energy_kcal"] as? Double,
                        elevationGainMeters: payload["elevation_gain_m"] as? Double,
                        elevationLossMeters: payload["elevation_loss_m"] as? Double,
                        heartRateBPM: payload["heart_rate_bpm"] as? Double,
                        speedMps: payload["speed_mps"] as? Double,
                        cadenceSPM: payload["cadence_spm"] as? Double
                    )
                case "watch_location":
                    point = MetricPoint(
                        timestamp: point.timestamp,
                        distanceMeters: payload["distance_m"] as? Double,
                        activeEnergyKcal: nil,
                        elevationGainMeters: nil,
                        elevationLossMeters: nil,
                        heartRateBPM: nil,
                        speedMps: payload["speed_mps"] as? Double,
                        cadenceSPM: nil
                    )
                case "heart_rate":
                    point = MetricPoint(
                        timestamp: point.timestamp,
                        distanceMeters: nil,
                        activeEnergyKcal: nil,
                        elevationGainMeters: nil,
                        elevationLossMeters: nil,
                        heartRateBPM: payload["bpm"] as? Double,
                        speedMps: nil,
                        cadenceSPM: nil
                    )
                case "pedometer":
                    point = MetricPoint(
                        timestamp: point.timestamp,
                        distanceMeters: nil,
                        activeEnergyKcal: nil,
                        elevationGainMeters: nil,
                        elevationLossMeters: nil,
                        heartRateBPM: nil,
                        speedMps: nil,
                        cadenceSPM: payload["cadence_spm"] as? Double
                    )
                default:
                    break
                }
                points.append(point)
            }
        }
        return points.sorted { $0.timestamp < $1.timestamp }
    }

    private func latestPoint(atOrBefore date: Date, in points: [MetricPoint]) -> MetricPoint? {
        points.last { $0.timestamp <= date && (
            $0.distanceMeters != nil
                || $0.activeEnergyKcal != nil
                || $0.elevationGainMeters != nil
                || $0.elevationLossMeters != nil
        ) }
    }

    private func cumulativeDelta(start: Double?, end: Double?, allowZeroStart: Bool) -> Double? {
        guard let end else { return nil }
        if let start { return max(0, end - start) }
        return allowZeroStart ? max(0, end) : nil
    }

    private func pauseOverlap(
        start: Date,
        end: Date,
        pauseReport: SessionPauseReport,
        isOnlySegment: Bool
    ) -> TimeInterval {
        if !pauseReport.intervals.isEmpty {
            return pauseReport.intervals.reduce(0) { total, interval in
                let overlapStart = max(start, interval.start)
                let overlapEnd = min(end, interval.end)
                return total + max(0, overlapEnd.timeIntervalSince(overlapStart))
            }
        }
        if pauseReport.reconstructedFromWallClock, isOnlySegment {
            return min(end.timeIntervalSince(start), pauseReport.totalPaused)
        }
        return 0
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func sessionDirectory(sessionID: String) -> URL? {
        guard !sessionID.isEmpty,
              let documents = try? FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
              ) else { return nil }
        return documents
            .appendingPathComponent("Sessions", isDirectory: true)
            .appendingPathComponent(sessionID, isDirectory: true)
    }
}

struct SessionSegmentMetricsView: View {
    let summary: TrackerSummary
    @State private var metrics: [SessionSegmentMetrics] = []

    var body: some View {
        if metrics.count > 1 {
            VStack(alignment: .leading, spacing: 10) {
                Label("ANALYSE PAR SEGMENT", systemImage: "square.stack.3d.up.fill")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)

                ForEach(metrics) { metric in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Label(activityLabel(metric.activity), systemImage: activitySymbol(metric.activity))
                                .font(.subheadline.weight(.bold))
                            Spacer()
                            Text(durationText(metric.activeDuration))
                                .font(.caption.weight(.bold))
                                .monospacedDigit()
                        }

                        HStack(spacing: 14) {
                            if let distance = metric.distanceMeters {
                                value(distanceText(distance), label: "Distance")
                            }
                            if let energy = metric.activeEnergyKcal {
                                value(String(format: "%.0f kcal", energy), label: "Énergie")
                            }
                            if let hr = metric.averageHeartRateBPM {
                                value(String(format: "%.0f bpm", hr), label: "FC moy.")
                            }
                        }

                        HStack(spacing: 14) {
                            if let speed = metric.maxSpeedMps {
                                value(String(format: "%.1f km/h", speed * 3.6), label: "V max")
                            }
                            if let cadence = metric.averageCadenceSPM {
                                value(String(format: "%.0f/min", cadence), label: "Cadence")
                            }
                            if let gain = metric.elevationGainMeters, let loss = metric.elevationLossMeters {
                                value(String(format: "+%.0f/−%.0f m", gain, loss), label: "D+/D−")
                            }
                        }

                        if metric.pausedDuration > 0.5 {
                            Text("Pause dans ce segment : \(durationText(metric.pausedDuration))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Text("\(metric.authoritativeSampleCount) point(s) de télémétrie Watch utilisés")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(10)
                    .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Text("Les métriques par segment sont dérivées des snapshots Watch autoritaires et des événements de transition conservés. Elles ne remplacent pas les valeurs HealthKit.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .task(id: summary.sessionID) { reload() }
        } else {
            Color.clear
                .frame(height: 0)
                .task(id: summary.sessionID) { reload() }
        }
    }

    private func reload() {
        metrics = SessionSegmentAnalyzer().analyze(summary: summary)
    }

    private func value(_ value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.caption.weight(.bold)).monospacedDigit()
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }

    private func activityLabel(_ raw: String) -> String {
        ActivityKind(rawValue: raw)?.label ?? (raw == "transition" ? "Transition" : raw)
    }

    private func activitySymbol(_ raw: String) -> String {
        ActivityKind(rawValue: raw)?.symbol ?? (raw == "transition" ? "arrow.triangle.2.circlepath" : "figure.mixed.cardio")
    }

    private func distanceText(_ meters: Double) -> String {
        meters >= 1000 ? String(format: "%.2f km", meters / 1000) : String(format: "%.0f m", meters)
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%02d:%02d", minutes, secs)
    }
}
