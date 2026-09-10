import Foundation

struct TrackerSummary: Codable, Equatable {
    let sessionID: String
    let startedAt: Date
    let endedAt: Date
    let duration: TimeInterval
    let distanceMeters: Double
    let elevationGainMeters: Double
    let elevationLossMeters: Double
    let maxSpeedMps: Double
    let averageHeartRate: Double
}

final class NativeSessionStore {
    private var fileHandle: FileHandle?
    private var sessionDirectory: URL?
    private(set) var sessionID = ""

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    func begin(sessionID: String, metadata: [String: Any]) throws {
        close()
        self.sessionID = sessionID

        let root = try sessionsRoot(create: true)
        let directory = root.appendingPathComponent(sessionID, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let samplesURL = directory.appendingPathComponent("samples.jsonl")
        FileManager.default.createFile(atPath: samplesURL.path, contents: nil)
        fileHandle = try FileHandle(forWritingTo: samplesURL)
        sessionDirectory = directory

        append([
            "record": "session_start",
            "schema": 2,
            "session_id": sessionID,
            "timestamp": Date().timeIntervalSince1970,
            "metadata": metadata,
        ])
    }

    func appendSample(source: String, kind: String, payload: [String: Any], quality: [String: Any] = [:]) {
        guard fileHandle != nil else { return }
        append([
            "record": "sample",
            "schema": 2,
            "session_id": sessionID,
            "timestamp": Date().timeIntervalSince1970,
            "source": source,
            "kind": kind,
            "payload": payload,
            "quality": quality,
        ])
    }

    func finish(summary: TrackerSummary) {
        guard let directory = sessionDirectory else {
            close()
            return
        }

        append([
            "record": "session_end",
            "schema": 2,
            "session_id": summary.sessionID,
            "timestamp": summary.endedAt.timeIntervalSince1970,
            "summary": [
                "duration_s": summary.duration,
                "distance_m": summary.distanceMeters,
                "elevation_gain_m": summary.elevationGainMeters,
                "elevation_loss_m": summary.elevationLossMeters,
                "max_speed_mps": summary.maxSpeedMps,
                "average_heart_rate_bpm": summary.averageHeartRate,
            ],
        ])

        fileHandle?.synchronizeFile()
        closeHandleOnly()

        do {
            let data = try encoder.encode(summary)
            try data.write(to: directory.appendingPathComponent("summary.json"), options: .atomic)
        } catch {
            // samples.jsonl is the durable source of truth even if summary serialization fails.
        }

        sessionDirectory = nil
        sessionID = ""
    }

    func deleteAllSessions() throws {
        close()
        let root = try sessionsRoot(create: false)
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        try FileManager.default.removeItem(at: root)
    }

    func close() {
        closeHandleOnly()
        sessionDirectory = nil
        sessionID = ""
    }

    private func sessionsRoot(create: Bool) throws -> URL {
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

    private func append(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object), let handle = fileHandle else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        handle.write(data)
        handle.write(Data([0x0A]))
    }

    private func closeHandleOnly() {
        fileHandle?.synchronizeFile()
        fileHandle?.closeFile()
        fileHandle = nil
    }
}
