import Foundation
import WatchConnectivity

/// Receives WatchConnectivity `transferUserInfo` packets that were queued while the iPhone was
/// unreachable. They are written to a separate per-session journal so we never race the active
/// `samples.jsonl` FileHandle. When the normal summary already exists, segment metadata is rebuilt
/// from the combined main + reliable journals.
extension TrackerModel {
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        // 1. Persistance durable pour récupération/diagnostic.
        WatchReliableRecovery.ingest(userInfo)

        // 2. Le même paquet alimente immédiatement la machine
        //    produit (correction/restauration comprise).
        receiveWC(userInfo)
    }
}

enum WatchReliableRecovery {
    private static let reliableFileName = "watch_reliable.jsonl"

    static func ingest(_ packet: [String: Any]) {
        guard packet["type"] as? String == "sensor_sample",
              packet["source"] as? String == "watch",
              let kind = packet["kind"] as? String,
              let payload = packet["payload"] as? [String: Any],
              let sessionID = payload["session_id"] as? String,
              !sessionID.isEmpty else { return }

        let packetTimestamp = packet["timestamp"] as? Double
            ?? payload["timestamp"] as? Double
            ?? Date().timeIntervalSince1970

        var record: [String: Any] = [
            "schema": NativeSessionStore.currentSchema,
            "session_id": sessionID,
            "timestamp": packetTimestamp,
            "source": "watch",
            "recovered_via": "transferUserInfo",
        ]

        if kind == "event", let event = payload["name"] as? String, !event.isEmpty {
            var eventPayload = payload
            eventPayload.removeValue(forKey: "name")
            record["record"] = "event"
            record["event"] = event
            record["payload"] = eventPayload
        } else {
            record["record"] = "sample"
            record["kind"] = kind
            record["payload"] = payload
            record["quality"] = [:]
        }

        guard JSONSerialization.isValidJSONObject(record) else { return }
        do {
            let directory = try sessionDirectory(sessionID: sessionID, create: true)
            let url = directory.appendingPathComponent(reliableFileName)
            let signature = signatureFor(record)
            if containsSignature(signature, in: url) { return }
            let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            handle.write(data)
            handle.write(Data([0x0A]))
            try handle.close()
            refreshSummaryIfNeeded(sessionID: sessionID)
        } catch {
            // Do not crash a running workout because delayed diagnostics could not be persisted.
        }
    }

    static func refreshSummaryIfNeeded(sessionID: String) {
        guard let directory = try? sessionDirectory(sessionID: sessionID, create: false) else { return }
        let summaryURL = directory.appendingPathComponent("summary.json")
        let reliableURL = directory.appendingPathComponent(reliableFileName)
        guard FileManager.default.fileExists(atPath: summaryURL.path),
              FileManager.default.fileExists(atPath: reliableURL.path),
              let data = try? Data(contentsOf: summaryURL) else { return }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let summary = try? decoder.decode(TrackerSummary.self, from: data),
              let segments = rebuildSegments(for: summary, directory: directory),
              segments != summary.segments else { return }

        let refreshed = TrackerSummary(
            sessionID: summary.sessionID,
            activity: summary.activity,
            startedAt: summary.startedAt,
            endedAt: summary.endedAt,
            duration: summary.duration,
            distanceMeters: summary.distanceMeters,
            elevationGainMeters: summary.elevationGainMeters,
            elevationLossMeters: summary.elevationLossMeters,
            maxSpeedMps: summary.maxSpeedMps,
            averageHeartRate: summary.averageHeartRate,
            activeEnergyKcal: summary.activeEnergyKcal,
            maxHeartRate: summary.maxHeartRate,
            averageCadenceSPM: summary.averageCadenceSPM,
            weatherSnapshots: summary.weatherSnapshots,
            segments: segments,
            buildSHA: summary.buildSHA,
            schemaVersion: summary.schemaVersion,
            algorithmVersion: summary.algorithmVersion
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let refreshedData = try? encoder.encode(refreshed) else { return }
        try? refreshedData.write(to: summaryURL, options: .atomic)
    }

    static func refreshAllAvailableSummaries() {
        guard let root = try? sessionsRoot(create: false),
              let children = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else { return }
        for directory in children {
            refreshSummaryIfNeeded(sessionID: directory.lastPathComponent)
        }
    }

    private struct OrderedRecord {
        let timestamp: Double
        let object: [String: Any]
    }

    private static func rebuildSegments(for summary: TrackerSummary, directory: URL) -> [TrackerSegmentSummary]? {
        let mainURL = directory.appendingPathComponent("samples.jsonl")
        let reliableURL = directory.appendingPathComponent(reliableFileName)
        var records = loadRecords(from: mainURL)
        records.append(contentsOf: loadRecords(from: reliableURL))
        records.sort { $0.timestamp < $1.timestamp }

        var currentActivity = summary.activity
        var currentStart = summary.startedAt
        var currentWatchDistance: Double?
        var currentPhoneDistance: Double?
        var segmentStartWatchDistance = 0.0
        var segmentStartPhoneDistance = 0.0
        var hasWatchDistanceAtSegmentStart = false
        var hasPhoneDistanceAtSegmentStart = false
        var segments: [TrackerSegmentSummary] = []
        var eventSignatures = Set<String>()

        func distanceForCurrentSegment() -> Double? {
            if hasWatchDistanceAtSegmentStart, let currentWatchDistance {
                return max(0, currentWatchDistance - segmentStartWatchDistance)
            }
            if hasPhoneDistanceAtSegmentStart, let currentPhoneDistance {
                return max(0, currentPhoneDistance - segmentStartPhoneDistance)
            }
            return nil
        }

        func closeSegment(at end: Date, nextActivity: String?) {
            let clampedEnd = max(end, currentStart)
            if clampedEnd.timeIntervalSince(currentStart) >= 0.5 {
                segments.append(
                    TrackerSegmentSummary(
                        id: "\(summary.sessionID)-segment-\(segments.count + 1)",
                        activity: currentActivity,
                        startedAt: currentStart,
                        endedAt: clampedEnd,
                        distanceMeters: distanceForCurrentSegment(),
                        activeEnergyKcal: nil
                    )
                )
            }
            guard let nextActivity else { return }
            currentActivity = nextActivity
            currentStart = clampedEnd
            if let currentWatchDistance {
                segmentStartWatchDistance = currentWatchDistance
                hasWatchDistanceAtSegmentStart = true
            }
            if let currentPhoneDistance {
                segmentStartPhoneDistance = currentPhoneDistance
                hasPhoneDistanceAtSegmentStart = true
            }
        }

        for record in records {
            let object = record.object
            if object["record"] as? String == "session_start",
               let metadata = object["metadata"] as? [String: Any],
               let effective = metadata["effective_activity"] as? String,
               !effective.isEmpty {
                currentActivity = effective
                continue
            }

            if object["record"] as? String == "sample",
               let kind = object["kind"] as? String,
               let payload = object["payload"] as? [String: Any],
               let distance = payload["distance_m"] as? Double {
                if kind == "watch_location" || kind == "authority_metrics" {
                    currentWatchDistance = distance
                    if !hasWatchDistanceAtSegmentStart {
                        segmentStartWatchDistance = distance
                        hasWatchDistanceAtSegmentStart = true
                    }
                } else if kind == "location" {
                    currentPhoneDistance = distance
                    if !hasPhoneDistanceAtSegmentStart {
                        segmentStartPhoneDistance = distance
                        hasPhoneDistanceAtSegmentStart = true
                    }
                }
            }

            guard object["record"] as? String == "event",
                  let event = object["event"] as? String else { continue }
            let payload = object["payload"] as? [String: Any] ?? [:]
            let signature = "\(event)|\(payload["authority_revision"] ?? "")|\(payload["timestamp"] ?? record.timestamp)"
            guard eventSignatures.insert(signature).inserted else { continue }

            let nextActivity: String?
            switch event {
            case "multisport_transition_started":
                nextActivity = "transition"
            case "multisport_segment_started":
                nextActivity = payload["activity"] as? String
            case "effective_activity_changed", "auto_activity_changed":
                nextActivity = payload["to"] as? String
            default:
                nextActivity = nil
            }

            if let nextActivity, !nextActivity.isEmpty, nextActivity != currentActivity {
                closeSegment(at: Date(timeIntervalSince1970: record.timestamp), nextActivity: nextActivity)
            }
        }

        closeSegment(at: summary.endedAt, nextActivity: nil)
        if segments.count == 1, segments[0].distanceMeters == nil {
            let only = segments[0]
            segments[0] = TrackerSegmentSummary(
                id: only.id,
                activity: only.activity,
                startedAt: only.startedAt,
                endedAt: only.endedAt,
                distanceMeters: summary.distanceMeters,
                activeEnergyKcal: only.activeEnergyKcal
            )
        }
        return segments.isEmpty ? nil : segments
    }

    private static func loadRecords(from url: URL) -> [OrderedRecord] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).compactMap { line in
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let timestamp = object["timestamp"] as? Double else { return nil }
            return OrderedRecord(timestamp: timestamp, object: object)
        }
    }

    private static func signatureFor(_ record: [String: Any]) -> String {
        let session = record["session_id"] as? String ?? ""
        let event = record["event"] as? String ?? (record["kind"] as? String ?? "")
        let payload = record["payload"] as? [String: Any] ?? [:]
        let revision = payload["authority_revision"].map(String.init(describing:)) ?? ""
        let timestamp = payload["timestamp"].map(String.init(describing:))
            ?? record["timestamp"].map(String.init(describing:))
            ?? ""
        return "\(session)|\(event)|\(revision)|\(timestamp)"
    }

    private static func containsSignature(_ signature: String, in url: URL) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if signatureFor(object) == signature { return true }
        }
        return false
    }

    private static func sessionDirectory(sessionID: String, create: Bool) throws -> URL {
        let root = try sessionsRoot(create: create)
        let directory = root.appendingPathComponent(sessionID, isDirectory: true)
        if create {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    private static func sessionsRoot(create: Bool) throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = documents.appendingPathComponent("Sessions", isDirectory: true)
        if create {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return root
    }
}
