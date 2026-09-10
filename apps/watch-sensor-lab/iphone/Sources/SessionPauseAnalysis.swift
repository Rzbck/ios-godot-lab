import Foundation
import SwiftUI

struct SessionPauseInterval: Identifiable, Equatable {
    enum Kind: String {
        case manual = "Manuelle"
        case automatic = "Automatique"
        case recovered = "Reconstituée"
    }

    let id: String
    let start: Date
    let end: Date
    let kind: Kind

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

struct SessionPauseReport: Equatable {
    let totalPaused: TimeInterval
    let manualPaused: TimeInterval
    let automaticPaused: TimeInterval
    let intervals: [SessionPauseInterval]
    let reconstructedFromWallClock: Bool

    var count: Int { intervals.count }

    static func empty(summary: TrackerSummary) -> SessionPauseReport {
        let wallPaused = max(0, summary.endedAt.timeIntervalSince(summary.startedAt) - summary.duration)
        return SessionPauseReport(
            totalPaused: wallPaused,
            manualPaused: 0,
            automaticPaused: 0,
            intervals: [],
            reconstructedFromWallClock: wallPaused > 1
        )
    }
}

struct SessionPauseAnalyzer {
    private struct Record {
        let timestamp: Date
        let event: String
        let payload: [String: Any]
    }

    func analyze(summary: TrackerSummary) -> SessionPauseReport {
        let records = loadEvents(sessionID: summary.sessionID)
        var intervals: [SessionPauseInterval] = []
        var openPause: (start: Date, kind: SessionPauseInterval.Kind)?
        var seen = Set<String>()

        for record in records {
            let signature = "\(record.event)|\(record.timestamp.timeIntervalSince1970)|\(record.payload["authority_revision"] ?? "")"
            guard seen.insert(signature).inserted else { continue }

            switch record.event {
            case "manual_pause":
                if openPause == nil { openPause = (record.timestamp, .manual) }
            case "auto_pause":
                if openPause == nil { openPause = (record.timestamp, .automatic) }
            case "manual_resume", "auto_resume":
                guard let open = openPause else { continue }
                let end = min(max(record.timestamp, open.start), summary.endedAt)
                intervals.append(
                    SessionPauseInterval(
                        id: "\(summary.sessionID)-pause-\(intervals.count + 1)",
                        start: open.start,
                        end: end,
                        kind: open.kind
                    )
                )
                openPause = nil
            default:
                continue
            }
        }

        if let open = openPause, open.start < summary.endedAt {
            intervals.append(
                SessionPauseInterval(
                    id: "\(summary.sessionID)-pause-\(intervals.count + 1)",
                    start: open.start,
                    end: summary.endedAt,
                    kind: open.kind
                )
            )
        }

        let eventTotal = intervals.reduce(0) { $0 + $1.duration }
        let wallTotal = max(0, summary.endedAt.timeIntervalSince(summary.startedAt) - summary.duration)
        let useWallFallback = intervals.isEmpty && wallTotal > 1
        let total = useWallFallback ? wallTotal : eventTotal
        let manual = intervals.filter { $0.kind == .manual }.reduce(0) { $0 + $1.duration }
        let automatic = intervals.filter { $0.kind == .automatic }.reduce(0) { $0 + $1.duration }

        return SessionPauseReport(
            totalPaused: total,
            manualPaused: manual,
            automaticPaused: automatic,
            intervals: intervals,
            reconstructedFromWallClock: useWallFallback
        )
    }

    private func loadEvents(sessionID: String) -> [Record] {
        guard let directory = sessionDirectory(sessionID: sessionID) else { return [] }
        let urls = [
            directory.appendingPathComponent("samples.jsonl"),
            directory.appendingPathComponent("watch_reliable.jsonl"),
        ]

        var records: [Record] = []
        for url in urls {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let data = String(line).data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      object["record"] as? String == "event",
                      let event = object["event"] as? String,
                      let timestamp = object["timestamp"] as? Double else { continue }
                records.append(
                    Record(
                        timestamp: Date(timeIntervalSince1970: timestamp),
                        event: event,
                        payload: object["payload"] as? [String: Any] ?? [:]
                    )
                )
            }
        }
        return records.sorted { $0.timestamp < $1.timestamp }
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

struct SessionPauseSummaryView: View {
    let summary: TrackerSummary
    @State private var report: SessionPauseReport?

    var body: some View {
        Group {
            if let report, report.totalPaused > 0.5 {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("PAUSES", systemImage: "pause.circle.fill")
                            .font(.caption.weight(.black))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(durationText(report.totalPaused))
                            .font(.subheadline.weight(.bold))
                            .monospacedDigit()
                    }

                    HStack(spacing: 18) {
                        pauseValue("Nombre", "\(max(report.count, report.reconstructedFromWallClock ? 1 : 0))")
                        if report.manualPaused > 0 {
                            pauseValue("Manuelles", durationText(report.manualPaused))
                        }
                        if report.automaticPaused > 0 {
                            pauseValue("Auto", durationText(report.automaticPaused))
                        }
                    }

                    if !report.intervals.isEmpty {
                        ForEach(report.intervals) { interval in
                            HStack {
                                Text(interval.kind.rawValue)
                                Spacer()
                                Text(interval.start, format: .dateTime.hour().minute().second())
                                Text("·")
                                Text(durationText(interval.duration))
                                    .monospacedDigit()
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    } else if report.reconstructedFromWallClock {
                        Text("Durée reconstruite depuis temps écoulé − temps actif ; les événements détaillés ne sont pas disponibles pour cette ancienne session.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .task(id: summary.sessionID) {
            let value = SessionPauseAnalyzer().analyze(summary: summary)
            report = value
        }
    }

    private func pauseValue(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.subheadline.weight(.bold)).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%02d:%02d", minutes, secs)
    }
}
