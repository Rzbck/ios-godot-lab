import Foundation
import OSLog

/// Structured, bounded, local-first telemetry for Watch Sensor Lab.
///
/// Every record is emitted as one JSON line prefixed with `WSL_TELEMETRY|`
/// so a tethered host can stream it through the device syslog. Records are also
/// persisted locally as rotating JSONL files for post-mortem debugging.
final class AppTelemetry {
    static let shared = AppTelemetry()

    private let queue = DispatchQueue(label: "com.rzbck.watchsensorlab.telemetry", qos: .utility)
    private let logger = Logger(subsystem: "com.rzbck.watchsensorlab", category: "telemetry")
    private let bootID = UUID().uuidString
    private var sequence: UInt64 = 0
    private var platform = "unknown"
    private var buildSHA = "unknown"
    private var configured = false
    private var relay: ((String) -> Void)?
    private let maxFileBytes: UInt64 = 4 * 1024 * 1024
    private let maxRotatedFiles = 4

    private init() {}

    func configure(
        platform: String,
        buildSHA: String,
        relay: ((String) -> Void)? = nil
    ) {
        queue.async {
            self.platform = platform
            self.buildSHA = buildSHA
            self.relay = relay
            guard !self.configured else { return }
            self.configured = true
            self.write(
                kind: "lifecycle",
                name: "telemetry_boot",
                screen: nil,
                fields: [
                    "bundle_id": Bundle.main.bundleIdentifier ?? "unknown",
                    "app_version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                    "build_number": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
                ]
            )
        }
    }

    func event(
        _ name: String,
        screen: String? = nil,
        fields: [String: Any] = [:]
    ) {
        queue.async {
            self.write(kind: "event", name: name, screen: screen, fields: fields)
        }
    }

    func action(
        _ name: String,
        screen: String? = nil,
        fields: [String: Any] = [:]
    ) {
        queue.async {
            self.write(kind: "action", name: name, screen: screen, fields: fields)
        }
    }

    func snapshot(
        _ name: String = "app_state",
        screen: String? = nil,
        fields: [String: Any]
    ) {
        queue.async {
            self.write(kind: "snapshot", name: name, screen: screen, fields: fields)
        }
    }

    func error(
        _ name: String,
        screen: String? = nil,
        error: Error? = nil,
        fields: [String: Any] = [:]
    ) {
        var payload = fields
        if let error {
            payload["error"] = error.localizedDescription
        }
        queue.async {
            self.write(kind: "error", name: name, screen: screen, fields: payload)
        }
    }

    /// Re-emits a structured line received from another device (for example the Watch)
    /// through the iPhone telemetry stream without rewriting the nested record.
    func relayRemoteJSON(_ json: String, source: String) {
        queue.async {
            self.write(
                kind: "relay",
                name: "remote_telemetry",
                screen: nil,
                fields: ["source": source, "record": json]
            )
        }
    }

    private func write(
        kind: String,
        name: String,
        screen: String?,
        fields: [String: Any]
    ) {
        sequence &+= 1
        var record: [String: Any] = [
            "schema": "watch_sensor_lab_telemetry_v1",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "uptime_s": ProcessInfo.processInfo.systemUptime,
            "sequence": sequence,
            "boot_id": bootID,
            "platform": platform,
            "build_sha": buildSHA,
            "kind": kind,
            "name": name,
        ]
        if let screen { record["screen"] = screen }
        if !fields.isEmpty { record["fields"] = jsonSafe(fields) }

        guard JSONSerialization.isValidJSONObject(record),
              let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8)
        else { return }

        let line = "WSL_TELEMETRY|" + json
        logger.notice("\(line, privacy: .public)")
        relay?(json)
        persist(json + "\n")
    }

    private func jsonSafe(_ value: Any) -> Any {
        switch value {
        case let value as String: return value
        case let value as Bool: return value
        case let value as Int: return value
        case let value as Int64: return value
        case let value as UInt64: return value
        case let value as Double:
            return value.isFinite ? value : String(describing: value)
        case let value as Float:
            return value.isFinite ? value : String(describing: value)
        case let value as Date:
            return ISO8601DateFormatter().string(from: value)
        case let value as UUID:
            return value.uuidString
        case let value as [String: Any]:
            return value.mapValues(jsonSafe)
        case let value as [Any]:
            return value.map(jsonSafe)
        case Optional<Any>.none:
            return NSNull()
        default:
            return String(describing: value)
        }
    }

    private func persist(_ line: String) {
        guard let data = line.data(using: .utf8), let fileURL = telemetryFileURL() else { return }
        rotateIfNeeded(fileURL: fileURL)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // Telemetry must never interfere with product behavior.
        }
    }

    private func telemetryDirectoryURL() -> URL? {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = root.appendingPathComponent("WatchSensorLabTelemetry", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func telemetryFileURL() -> URL? {
        telemetryDirectoryURL()?.appendingPathComponent("current.jsonl")
    }

    private func rotateIfNeeded(fileURL: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let size = attrs[.size] as? NSNumber,
              size.uint64Value >= maxFileBytes,
              let directory = telemetryDirectoryURL()
        else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let rotated = directory.appendingPathComponent("telemetry-\(formatter.string(from: Date())).jsonl")
        try? FileManager.default.moveItem(at: fileURL, to: rotated)

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let rotatedFiles = files
            .filter { $0.lastPathComponent.hasPrefix("telemetry-") && $0.pathExtension == "jsonl" }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return l > r
            }

        for old in rotatedFiles.dropFirst(maxRotatedFiles) {
            try? FileManager.default.removeItem(at: old)
        }
    }
}
