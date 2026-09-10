import CoreLocation
import Foundation

struct SessionWeatherSnapshot: Codable, Equatable, Identifiable {
    let timestamp: Date
    let provider: String
    let latitude: Double
    let longitude: Double
    let temperatureC: Double?
    let apparentTemperatureC: Double?
    let relativeHumidityPercent: Double?
    let pressureHPA: Double?
    let windSpeedKPH: Double?
    let windDirectionDegrees: Double?
    let windGustKPH: Double?
    let weatherCode: Int?

    var id: String { "\(provider)-\(timestamp.timeIntervalSince1970)" }
}

struct TrackerSegmentSummary: Codable, Equatable, Identifiable {
    let id: String
    let activity: String
    let startedAt: Date
    let endedAt: Date?
    let distanceMeters: Double?
    let activeEnergyKcal: Double?
}

struct TrackerSummary: Codable, Equatable, Identifiable {
    let sessionID: String
    let activity: String
    let startedAt: Date
    let endedAt: Date
    let duration: TimeInterval
    let distanceMeters: Double
    let elevationGainMeters: Double
    let elevationLossMeters: Double
    let maxSpeedMps: Double
    let averageHeartRate: Double

    // v0.4 fields are optional so v0.3.x summaries remain readable without migration.
    let activeEnergyKcal: Double?
    let maxHeartRate: Double?
    let averageCadenceSPM: Double?
    let weatherSnapshots: [SessionWeatherSnapshot]?
    let segments: [TrackerSegmentSummary]?
    let buildSHA: String?
    let schemaVersion: Int?
    let algorithmVersion: String?

    var id: String { sessionID }

    init(
        sessionID: String,
        activity: String,
        startedAt: Date,
        endedAt: Date,
        duration: TimeInterval,
        distanceMeters: Double,
        elevationGainMeters: Double,
        elevationLossMeters: Double,
        maxSpeedMps: Double,
        averageHeartRate: Double,
        activeEnergyKcal: Double? = nil,
        maxHeartRate: Double? = nil,
        averageCadenceSPM: Double? = nil,
        weatherSnapshots: [SessionWeatherSnapshot]? = nil,
        segments: [TrackerSegmentSummary]? = nil,
        buildSHA: String? = nil,
        schemaVersion: Int? = nil,
        algorithmVersion: String? = nil
    ) {
        self.sessionID = sessionID
        self.activity = activity
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
        self.distanceMeters = distanceMeters
        self.elevationGainMeters = elevationGainMeters
        self.elevationLossMeters = elevationLossMeters
        self.maxSpeedMps = maxSpeedMps
        self.averageHeartRate = averageHeartRate
        self.activeEnergyKcal = activeEnergyKcal
        self.maxHeartRate = maxHeartRate
        self.averageCadenceSPM = averageCadenceSPM
        self.weatherSnapshots = weatherSnapshots
        self.segments = segments
        self.buildSHA = buildSHA
        self.schemaVersion = schemaVersion
        self.algorithmVersion = algorithmVersion
    }
}

final class NativeSessionStore {
    static let currentSchema = 3
    static let currentAlgorithmVersion = "tracker-v4-20260910"

    private var fileHandle: FileHandle?
    private var sessionDirectory: URL?
    private(set) var sessionID = ""

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func begin(sessionID: String, metadata: [String: Any]) throws {
        close()
        self.sessionID = sessionID

        let root = try sessionsRoot(create: true)
        let directory = root.appendingPathComponent(sessionID, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let samplesURL = directory.appendingPathComponent("samples.jsonl")
        if !FileManager.default.fileExists(atPath: samplesURL.path) {
            FileManager.default.createFile(atPath: samplesURL.path, contents: nil)
        }
        fileHandle = try FileHandle(forWritingTo: samplesURL)
        try fileHandle?.seekToEnd()
        sessionDirectory = directory

        var enriched = metadata
        enriched["schema"] = Self.currentSchema
        enriched["algorithm_version"] = Self.currentAlgorithmVersion

        append([
            "record": "session_start",
            "schema": Self.currentSchema,
            "session_id": sessionID,
            "timestamp": Date().timeIntervalSince1970,
            "metadata": enriched,
        ])
    }

    func appendSample(source: String, kind: String, payload: [String: Any], quality: [String: Any] = [:]) {
        guard fileHandle != nil else { return }
        append([
            "record": "sample",
            "schema": Self.currentSchema,
            "session_id": sessionID,
            "timestamp": Date().timeIntervalSince1970,
            "source": source,
            "kind": kind,
            "payload": payload,
            "quality": quality,
        ])
    }

    func appendEvent(_ name: String, source: String, payload: [String: Any] = [:]) {
        guard fileHandle != nil else { return }
        append([
            "record": "event",
            "schema": Self.currentSchema,
            "session_id": sessionID,
            "timestamp": Date().timeIntervalSince1970,
            "source": source,
            "event": name,
            "payload": payload,
        ])
    }

    func finish(summary: TrackerSummary) {
        guard let directory = sessionDirectory else {
            close()
            return
        }

        var summaryPayload: [String: Any] = [
            "activity": summary.activity,
            "duration_s": summary.duration,
            "distance_m": summary.distanceMeters,
            "elevation_gain_m": summary.elevationGainMeters,
            "elevation_loss_m": summary.elevationLossMeters,
            "max_speed_mps": summary.maxSpeedMps,
            "average_heart_rate_bpm": summary.averageHeartRate,
        ]
        if let value = summary.activeEnergyKcal { summaryPayload["active_energy_kcal"] = value }
        if let value = summary.maxHeartRate { summaryPayload["max_heart_rate_bpm"] = value }
        if let value = summary.averageCadenceSPM { summaryPayload["average_cadence_spm"] = value }

        append([
            "record": "session_end",
            "schema": Self.currentSchema,
            "session_id": summary.sessionID,
            "timestamp": summary.endedAt.timeIntervalSince1970,
            "summary": summaryPayload,
        ])

        fileHandle?.synchronizeFile()
        closeHandleOnly()

        do {
            let data = try encoder.encode(summary)
            try data.write(to: directory.appendingPathComponent("summary.json"), options: .atomic)
        } catch {
            // samples.jsonl remains the durable source if summary serialization fails.
        }

        sessionDirectory = nil
        sessionID = ""
    }

    func listSummaries() -> [TrackerSummary] {
        guard let root = try? sessionsRoot(create: false),
              let children = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else { return [] }

        var summaries: [TrackerSummary] = []
        for directory in children {
            let url = directory.appendingPathComponent("summary.json")
            guard let data = try? Data(contentsOf: url),
                  let summary = try? decoder.decode(TrackerSummary.self, from: data) else { continue }
            summaries.append(summary)
        }
        return summaries.sorted { $0.startedAt > $1.startedAt }
    }

    func loadRoute(sessionID: String) -> [CLLocationCoordinate2D] {
        guard let root = try? sessionsRoot(create: false) else { return [] }
        let url = root
            .appendingPathComponent(sessionID, isDirectory: true)
            .appendingPathComponent("samples.jsonl")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        var coordinates: [CLLocationCoordinate2D] = []
        coordinates.reserveCapacity(2_000)

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["record"] as? String == "sample",
                  object["kind"] as? String == "location",
                  let payload = object["payload"] as? [String: Any],
                  let latitude = payload["latitude"] as? Double,
                  let longitude = payload["longitude"] as? Double else { continue }
            coordinates.append(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        }
        return coordinates
    }

    func deleteSession(sessionID: String) throws {
        guard !sessionID.isEmpty else { return }
        let root = try sessionsRoot(create: false)
        let directory = root.appendingPathComponent(sessionID, isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
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
