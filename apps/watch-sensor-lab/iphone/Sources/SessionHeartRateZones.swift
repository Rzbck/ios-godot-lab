import Foundation
import SwiftUI

struct SessionHeartRateZone: Identifiable, Equatable {
    let id: Int
    let name: String
    let rangeLabel: String
    let seconds: TimeInterval
    let fraction: Double
}

struct SessionHeartRateZoneReport: Equatable {
    let referenceMaxBPM: Double
    let usesConfiguredMax: Bool
    let coveredSeconds: TimeInterval
    let activeSeconds: TimeInterval
    let zones: [SessionHeartRateZone]

    var coverageFraction: Double {
        guard activeSeconds > 0 else { return 0 }
        return min(1, coveredSeconds / activeSeconds)
    }
}

struct SessionHeartRateZoneAnalyzer {
    private struct Sample {
        let timestamp: Date
        let bpm: Double
    }

    func analyze(summary: TrackerSummary, configuredMaxBPM: Double?) -> SessionHeartRateZoneReport? {
        let samples = loadSamples(sessionID: summary.sessionID)
        guard !samples.isEmpty else { return nil }

        let observedMax = max(samples.map(\.bpm).max() ?? 0, summary.maxHeartRate ?? 0)
        let configured = configuredMaxBPM ?? 0
        let reference = configured >= 100 ? configured : observedMax
        guard reference >= 80 else { return nil }

        var seconds = Array(repeating: 0.0, count: 5)
        var covered = 0.0

        for index in samples.indices {
            let current = samples[index]
            let nextTimestamp: Date
            if index + 1 < samples.count {
                nextTimestamp = samples[index + 1].timestamp
            } else {
                nextTimestamp = min(summary.endedAt, current.timestamp.addingTimeInterval(5))
            }

            let rawDuration = max(0, nextTimestamp.timeIntervalSince(current.timestamp))
            // Do not assume a stale heart-rate value across long connectivity gaps.
            let duration = min(rawDuration, 30)
            guard duration > 0 else { continue }

            let ratio = current.bpm / reference
            let zoneIndex: Int
            switch ratio {
            case ..<0.60: zoneIndex = 0
            case ..<0.70: zoneIndex = 1
            case ..<0.80: zoneIndex = 2
            case ..<0.90: zoneIndex = 3
            default: zoneIndex = 4
            }
            seconds[zoneIndex] += duration
            covered += duration
        }

        guard covered > 0 else { return nil }
        let boundaries = ["<60 %", "60–69 %", "70–79 %", "80–89 %", "≥90 %"]
        let zones = seconds.enumerated().map { index, value in
            SessionHeartRateZone(
                id: index + 1,
                name: "Zone \(index + 1)",
                rangeLabel: boundaries[index],
                seconds: value,
                fraction: value / covered
            )
        }

        return SessionHeartRateZoneReport(
            referenceMaxBPM: reference,
            usesConfiguredMax: configured >= 100,
            coveredSeconds: covered,
            activeSeconds: summary.duration,
            zones: zones
        )
    }

    private func loadSamples(sessionID: String) -> [Sample] {
        guard let directory = sessionDirectory(sessionID: sessionID) else { return [] }
        let urls = [
            directory.appendingPathComponent("samples.jsonl"),
            directory.appendingPathComponent("watch_reliable.jsonl"),
        ]
        var samples: [Sample] = []
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

                let bpm: Double?
                if kind == "heart_rate" {
                    bpm = payload["bpm"] as? Double
                } else if kind == "metric_snapshot" {
                    bpm = payload["heart_rate_bpm"] as? Double
                } else {
                    bpm = nil
                }
                guard let bpm, bpm >= 30, bpm <= 260 else { continue }

                let signature = "\(Int(timestampValue.rounded()))|\(Int(bpm.rounded()))"
                guard signatures.insert(signature).inserted else { continue }
                samples.append(Sample(timestamp: Date(timeIntervalSince1970: timestampValue), bpm: bpm))
            }
        }
        return samples.sorted { $0.timestamp < $1.timestamp }
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

struct SessionHeartRateZonesView: View {
    let summary: TrackerSummary

    @AppStorage("tracker.heartRate.referenceMaxBPM") private var configuredMaxBPM = 0.0
    @State private var report: SessionHeartRateZoneReport?

    var body: some View {
        if let report {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("ZONES CARDIO", systemImage: "heart.text.square.fill")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(report.referenceMaxBPM.rounded())) bpm")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                }

                ForEach(report.zones) { zone in
                    VStack(spacing: 3) {
                        HStack {
                            Text(zone.name).font(.caption.weight(.semibold))
                            Text(zone.rangeLabel).font(.caption2).foregroundStyle(.secondary)
                            Spacer()
                            Text(durationText(zone.seconds))
                                .font(.caption.monospacedDigit())
                        }
                        ProgressView(value: zone.fraction)
                    }
                }

                HStack {
                    Text("Couverture FC")
                    Spacer()
                    Text("\(Int((report.coverageFraction * 100).rounded())) % du temps actif")
                        .monospacedDigit()
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if report.usesConfiguredMax {
                    Stepper(value: configuredBinding, in: 100...240, step: 1) {
                        Text("FC max personnelle : \(Int(configuredMaxBPM.rounded())) bpm")
                            .font(.caption2)
                    }
                    Button("Revenir au pic de la séance") {
                        configuredMaxBPM = 0
                    }
                    .font(.caption2)
                } else {
                    Text("Référence relative : pic FC observé pendant cette séance. Ce n’est pas une FC max physiologique estimée.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Button("Définir une FC max personnelle") {
                        configuredMaxBPM = max(100, min(240, report.referenceMaxBPM.rounded()))
                    }
                    .font(.caption2.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .task(id: analysisID) { reload() }
        } else {
            Color.clear
                .frame(height: 0)
                .task(id: analysisID) { reload() }
        }
    }

    private var configuredBinding: Binding<Double> {
        Binding(
            get: { configuredMaxBPM },
            set: { configuredMaxBPM = $0 }
        )
    }

    private var analysisID: String {
        "\(summary.sessionID)-\(Int(configuredMaxBPM.rounded()))"
    }

    private func reload() {
        report = SessionHeartRateZoneAnalyzer().analyze(
            summary: summary,
            configuredMaxBPM: configuredMaxBPM >= 100 ? configuredMaxBPM : nil
        )
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let minutes = total / 60
        let secs = total % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
