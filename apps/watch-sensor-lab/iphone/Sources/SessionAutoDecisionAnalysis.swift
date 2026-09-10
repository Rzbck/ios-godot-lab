import Foundation
import SwiftUI

struct SessionAutoDecisionEntry: Identifiable, Equatable {
    enum Kind: String {
        case evidence = "Preuve"
        case candidate = "Candidat"
        case change = "Changement"
        case triathlonCandidate = "Candidat triathlon"
        case triathlonTransition = "Transition triathlon"
    }

    let id: String
    let timestamp: Date
    let kind: Kind
    let activity: String
    let fromActivity: String?
    let confidence: String?
    let provenance: String?
    let detail: String?
}

struct SessionAutoDecisionAnalyzer {
    func load(sessionID: String) -> [SessionAutoDecisionEntry] {
        guard let directory = sessionDirectory(sessionID: sessionID) else { return [] }
        let urls = [
            directory.appendingPathComponent("samples.jsonl"),
            directory.appendingPathComponent("watch_reliable.jsonl"),
        ]

        var entries: [SessionAutoDecisionEntry] = []
        var signatures = Set<String>()

        for url in urls {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard let data = String(line).data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      object["record"] as? String == "event",
                      let event = object["event"] as? String,
                      let timestamp = object["timestamp"] as? Double else { continue }
                let payload = object["payload"] as? [String: Any] ?? [:]
                let signature = "\(event)|\(payload["authority_revision"] ?? "")|\(payload["timestamp"] ?? timestamp)"
                guard signatures.insert(signature).inserted else { continue }

                let kind: SessionAutoDecisionEntry.Kind
                let activity: String
                var fromActivity: String?
                var detail: String?

                switch event {
                case "auto_evidence":
                    kind = .evidence
                    activity = payload["activity"] as? String ?? "unknown"
                case "auto_candidate":
                    kind = .candidate
                    activity = payload["activity"] as? String ?? "unknown"
                    if let dwell = payload["dwell_s"] as? Double {
                        detail = "validation après \(Int(dwell.rounded())) s stables"
                    }
                case "auto_activity_changed":
                    kind = .change
                    activity = payload["to"] as? String ?? "unknown"
                    fromActivity = payload["from"] as? String
                    if payload["healthkit_semantic_mismatch"] as? Bool == true {
                        detail = "transition détectée · conteneur HealthKit à contrôler"
                    }
                case "triathlon_auto_candidate":
                    kind = .triathlonCandidate
                    activity = payload["candidate"] as? String ?? "unknown"
                    detail = payload["phase"] as? String
                case "triathlon_auto_transition":
                    kind = .triathlonTransition
                    activity = payload["candidate"] as? String ?? "unknown"
                    detail = payload["action"] as? String
                default:
                    continue
                }

                entries.append(
                    SessionAutoDecisionEntry(
                        id: "\(sessionID)-auto-\(entries.count)-\(timestamp)",
                        timestamp: Date(timeIntervalSince1970: timestamp),
                        kind: kind,
                        activity: activity,
                        fromActivity: fromActivity,
                        confidence: payload["confidence"] as? String,
                        provenance: payload["provenance"] as? String,
                        detail: detail
                    )
                )
            }
        }
        return entries.sorted { $0.timestamp < $1.timestamp }
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

struct SessionAutoDecisionView: View {
    let summary: TrackerSummary
    @State private var entries: [SessionAutoDecisionEntry] = []

    private var meaningfulEntries: [SessionAutoDecisionEntry] {
        let changes = entries.filter { $0.kind == .change || $0.kind == .triathlonTransition }
        if !changes.isEmpty {
            let supporting = entries.filter { $0.kind == .candidate || $0.kind == .triathlonCandidate }
            return Array((supporting + changes).sorted { $0.timestamp < $1.timestamp }.suffix(12))
        }
        return Array(entries.filter { $0.kind == .candidate || $0.kind == .evidence }.suffix(5))
    }

    var body: some View {
        if !meaningfulEntries.isEmpty {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Label("DÉCISIONS AUTO", systemImage: "wand.and.stars")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if entries.contains(where: { $0.provenance?.contains("Inférence Watch Tracker") == true }) {
                        Text("INFÉRENCE APP")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(.orange)
                    }
                }

                ForEach(meaningfulEntries) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: symbol(for: entry.kind))
                            .frame(width: 20)
                            .foregroundStyle(entry.kind == .change || entry.kind == .triathlonTransition ? Color.mint : Color.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Text(entry.kind.rawValue).font(.caption.weight(.bold))
                                if let from = entry.fromActivity {
                                    Text("\(label(from)) → \(label(entry.activity))")
                                        .font(.caption.weight(.semibold))
                                } else {
                                    Text(label(entry.activity)).font(.caption.weight(.semibold))
                                }
                            }
                            HStack(spacing: 5) {
                                Text(entry.timestamp, format: .dateTime.hour().minute().second())
                                if let confidence = entry.confidence { Text("· confiance \(confidence)") }
                            }
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            if let provenance = entry.provenance {
                                Text(provenance)
                                    .font(.caption2)
                                    .foregroundStyle(provenance.contains("Inférence Watch Tracker") ? .orange : .tertiary)
                            }
                            if let detail = entry.detail {
                                Text(detail).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                Text("Core Motion = classification Apple. “Inférence Watch Tracker” = décision de notre classifieur, par exemple Randonnée probable avec marche + terrain/dénivelé.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .task(id: summary.sessionID) {
                entries = SessionAutoDecisionAnalyzer().load(sessionID: summary.sessionID)
            }
        } else {
            Color.clear
                .frame(height: 0)
                .task(id: summary.sessionID) {
                    entries = SessionAutoDecisionAnalyzer().load(sessionID: summary.sessionID)
                }
        }
    }

    private func label(_ raw: String) -> String {
        ActivityKind(rawValue: raw)?.label ?? (raw == "transition" ? "Transition" : raw)
    }

    private func symbol(for kind: SessionAutoDecisionEntry.Kind) -> String {
        switch kind {
        case .evidence: return "waveform.path.ecg"
        case .candidate, .triathlonCandidate: return "hourglass"
        case .change: return "arrow.triangle.swap"
        case .triathlonTransition: return "arrow.triangle.2.circlepath"
        }
    }
}
