import Foundation
import SwiftUI

struct TrackerEffortEstimate: Equatable {
    let score: Double
    let label: String
    let cardioContribution: Double?
    let durationContribution: Double
    let terrainContribution: Double
    let environmentContribution: Double
    let continuityFactor: Double
    let explanation: String
}

struct TrackerEffortEstimator {
    func estimate(summary: TrackerSummary) -> TrackerEffortEstimate {
        let configuredMax = UserDefaults.standard.double(forKey: "tracker.heartRate.referenceMaxBPM")
        let zoneReport = SessionHeartRateZoneAnalyzer().analyze(
            summary: summary,
            configuredMaxBPM: configuredMax >= 100 ? configuredMax : nil
        )
        let pauseReport = SessionPauseAnalyzer().analyze(summary: summary)
        let environment = SessionEffortAnalyzer().analyze(summary: summary)

        let cardio: Double?
        if let zoneReport {
            let weighted = zoneReport.zones.reduce(0.0) { partial, zone in
                partial + Double(zone.id) * zone.fraction
            }
            cardio = min(6.3, max(1.2, weighted / 5.0 * 6.3))
        } else if summary.averageHeartRate > 0, let maxHR = summary.maxHeartRate, maxHR > summary.averageHeartRate {
            cardio = min(6.0, max(1.0, summary.averageHeartRate / maxHR * 6.0))
        } else {
            cardio = nil
        }

        let duration = min(2.0, max(0.2, summary.duration / 3600.0 * 1.5))
        let terrain = min(0.9, max(0, summary.elevationGainMeters / 700.0))

        var environmentScore = 0.0
        if let apparent = environment.averageApparentTemperatureC ?? environment.averageTemperatureC {
            if apparent >= 30 { environmentScore += 0.45 }
            else if apparent <= 0 { environmentScore += 0.25 }
        }
        if let humidity = environment.averageHumidityPercent, humidity >= 80,
           (environment.averageApparentTemperatureC ?? environment.averageTemperatureC ?? 0) >= 20 {
            environmentScore += 0.20
        }
        if let headwind = environment.averageHeadwindComponentKPH, headwind >= 8 {
            environmentScore += min(0.45, headwind / 35.0)
        }
        environmentScore = min(0.9, environmentScore)

        let wallDuration = max(summary.duration, summary.endedAt.timeIntervalSince(summary.startedAt))
        let activeFraction = wallDuration > 0 ? min(1, summary.duration / wallDuration) : 1
        let continuity = 0.90 + (activeFraction * 0.10)

        var raw = (cardio ?? 2.2) + duration + terrain + environmentScore
        raw *= continuity
        let score = min(10, max(1, raw))

        let label: String
        switch score {
        case ..<3: label = "Léger"
        case ..<5: label = "Modéré"
        case ..<7: label = "Soutenu"
        case ..<9: label = "Difficile"
        default: label = "Très difficile"
        }

        var details: [String] = []
        if cardio != nil { details.append("zones cardio") }
        details.append("durée active")
        if terrain > 0.05 { details.append("dénivelé") }
        if pauseReport.totalPaused > 1 { details.append("continuité et pauses") }
        if environmentScore > 0.05 { details.append("météo") }

        return TrackerEffortEstimate(
            score: score,
            label: label,
            cardioContribution: cardio,
            durationContribution: duration,
            terrainContribution: terrain,
            environmentContribution: environmentScore,
            continuityFactor: continuity,
            explanation: "Estimation Watch Tracker basée sur \(details.joined(separator: ", ")). Elle sert de repère sportif et ne constitue pas une mesure médicale."
        )
    }
}

struct TrackerEffortInsightView: View {
    let summary: TrackerSummary

    @State private var estimate: TrackerEffortEstimate?
    @State private var perceived: Int?

    private var perceivedKey: String { "tracker.perceivedEffort.\(summary.sessionID)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("EFFORT", systemImage: "gauge.with.dots.needle.50percent")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.secondary)
                Spacer()
                if let estimate {
                    Text(String(format: "%.1f / 10", estimate.score))
                        .font(.headline.weight(.black))
                        .foregroundStyle(.orange)
                        .monospacedDigit()
                }
            }

            if let estimate {
                HStack(spacing: 12) {
                    ZStack {
                        Circle().stroke(.white.opacity(0.08), lineWidth: 8)
                        Circle()
                            .trim(from: 0, to: estimate.score / 10)
                            .stroke(.orange, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text(String(format: "%.1f", estimate.score))
                            .font(.title3.weight(.black))
                    }
                    .frame(width: 72, height: 72)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(estimate.label)
                            .font(.headline.weight(.bold))
                        Text(estimate.explanation)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("TON RESSENTI")
                    .font(.caption2.weight(.black))
                    .foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    ForEach(1...10, id: \.self) { value in
                        Button {
                            perceived = value
                            UserDefaults.standard.set(value, forKey: perceivedKey)
                        } label: {
                            Text("\(value)")
                                .font(.caption2.weight(.bold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 28)
                                .background(
                                    perceived == value ? Color.cyan : Color.white.opacity(0.07),
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                                .foregroundStyle(perceived == value ? Color.black : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("1 = très facile · 10 = effort maximal ressenti. Ton ressenti est conservé séparément de l’estimation automatique.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            LinearGradient(
                colors: [.orange.opacity(0.14), .pink.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .task(id: summary.sessionID) {
            estimate = TrackerEffortEstimator().estimate(summary: summary)
            let saved = UserDefaults.standard.integer(forKey: perceivedKey)
            perceived = saved > 0 ? saved : nil
        }
    }
}
