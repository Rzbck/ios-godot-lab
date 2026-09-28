import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

final class CloudSessionRecorder {
    struct DetectionRecord: Codable {
        let id: Int
        let kind: String
        let confidence: Double
        let coveragePercent: Double
        let centroidX: Double
        let centroidY: Double
        let boundsX: Double
        let boundsY: Double
        let boundsWidth: Double
        let boundsHeight: Double
        let midpointKilograms: Double
        let lowKilograms: Double
        let highKilograms: Double
        let estimatedWidthMeters: Double
        let estimatedHeightMeters: Double
        let estimatedDepthMeters: Double
        let estimatedDistanceMeters: Double
        let projectedAreaSquareMeters: Double
        let estimatedVolumeCubicMeters: Double
        let angularWidthDegrees: Double
        let angularHeightDegrees: Double
        let centerElevationDegrees: Double
        let massConfidence: Double
    }

    struct TelemetryRecord: Codable {
        let timestamp: TimeInterval
        let telemetry: CloudTelemetrySnapshot
        let detections: [DetectionRecord]
    }

    struct EventRecord: Codable {
        let timestamp: TimeInterval
        let type: String
        let detail: String
        let cloudCoveragePercent: Double
        let skyCoveragePercent: Double
        let maskChangePercent: Double
        let visibleTracks: Int
        let clippedPercent: Double
        let neutralHighlightPercent: Double
        let thermalState: String
    }

    struct VisualRecord: Codable {
        let timestamp: TimeInterval
        let relativePath: String
        let reason: String
        let byteCount: Int
        let cloudCount: Int
        let cloudCoveragePercent: Double
        let skyCoveragePercent: Double
    }

    struct Manifest: Codable {
        let schemaVersion: Int
        let sessionID: String
        let appVersion: String
        let buildSHA: String
        let startedAt: TimeInterval
        var endedAt: TimeInterval?
        var state: String
        var telemetryRecords: Int
        var eventRecords: Int
        var visualFrames: Int
        var visualBytes: Int64
        let baselineFrameRateHz: Double
        let eventFrameRateHz: Double
        let maxVisualDimension: Int
        let telemetryChunkRecords: Int
        let storagePolicy: String
    }

    struct SessionSummary: Codable {
        let sessionID: String
        let appVersion: String
        let buildSHA: String
        let startedAt: TimeInterval
        let endedAt: TimeInterval?
        let state: String
        let telemetryRecords: Int
        let eventRecords: Int
        let visualFrames: Int
        let visualBytes: Int64
        let totalBytes: Int64
    }

    struct FileRecord: Codable {
        let path: String
        let byteCount: Int64
    }

    private final class ActiveSession {
        let id: String
        let directory: URL
        let telemetryDirectory: URL
        let keyframesDirectory: URL
        let burstsDirectory: URL
        let eventsURL: URL
        let visualIndexURL: URL
        let manifestURL: URL
        let startedAt: TimeInterval
        let version: String
        let buildSHA: String

        var telemetryHandle: FileHandle
        var telemetryChunkIndex = 1
        var recordsInTelemetryChunk = 0
        var telemetryRecordCount = 0
        var eventRecordCount = 0
        var visualFrameCount = 0
        var visualBytes: Int64 = 0
        var lastVisualTimestamp: TimeInterval = 0
        var burstUntil: TimeInterval = 0
        var previousTelemetry: CloudTelemetrySnapshot?
        var lastEventTimes: [String: TimeInterval] = [:]
        var lastManifestWrite: TimeInterval = 0
        var visualCaptureStoppedForQuota = false

        init(
            id: String,
            directory: URL,
            telemetryDirectory: URL,
            keyframesDirectory: URL,
            burstsDirectory: URL,
            eventsURL: URL,
            visualIndexURL: URL,
            manifestURL: URL,
            startedAt: TimeInterval,
            version: String,
            buildSHA: String,
            telemetryHandle: FileHandle
        ) {
            self.id = id
            self.directory = directory
            self.telemetryDirectory = telemetryDirectory
            self.keyframesDirectory = keyframesDirectory
            self.burstsDirectory = burstsDirectory
            self.eventsURL = eventsURL
            self.visualIndexURL = visualIndexURL
            self.manifestURL = manifestURL
            self.startedAt = startedAt
            self.version = version
            self.buildSHA = buildSHA
            self.telemetryHandle = telemetryHandle
        }
    }

    private let fileManager = FileManager.default
    private let ioQueue = DispatchQueue(label: "cloudweight.session-recorder", qos: .utility)
    private let context = CIContext(options: [.cacheIntermediates: false])

    private let schemaVersion = 2
    private let telemetryChunkRecordLimit = 5_000
    private let baselineSnapshotInterval: TimeInterval = 1.0
    private let burstSnapshotInterval: TimeInterval = 0.25
    private let eventBurstDuration: TimeInterval = 2.5
    private let minimumSemanticVisualCoveragePercent = 1.5
    private let minimumVisualMaskChangePercent = 12.0
    private let maxSnapshotDimension = 640
    private let jpegQuality = 0.34
    private let maxSessionVisualBytes: Int64 = 320 * 1024 * 1024
    private let maxGlobalBytes: Int64 = 512 * 1024 * 1024
    private let maxStoredSessions = 8

    private var rootDirectory: URL
    private var active: ActiveSession?

    init() {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        rootDirectory = support.appendingPathComponent("CloudWeightSessionsV10", isDirectory: true)
        try? fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? rootDirectory.setResourceValues(values)
        recoverInterruptedSessions()
        pruneOldSessions(excluding: nil)
    }

    func startSession(buildSHA: String, version: String) {
        ioQueue.sync {
            guard active == nil else { return }

            let startedAt = Date().timeIntervalSince1970
            let id = "session-\(Int(startedAt * 1_000))-\(String(buildSHA.prefix(8)))"
            var directory = rootDirectory.appendingPathComponent(id, isDirectory: true)
            let telemetryDirectory = directory.appendingPathComponent("telemetry", isDirectory: true)
            let visualDirectory = directory.appendingPathComponent("visual", isDirectory: true)
            let keyframesDirectory = visualDirectory.appendingPathComponent("keyframes", isDirectory: true)
            let burstsDirectory = visualDirectory.appendingPathComponent("bursts", isDirectory: true)

            do {
                try fileManager.createDirectory(at: telemetryDirectory, withIntermediateDirectories: true)
                try fileManager.createDirectory(at: keyframesDirectory, withIntermediateDirectories: true)
                try fileManager.createDirectory(at: burstsDirectory, withIntermediateDirectories: true)
            } catch {
                return
            }

            var directoryValues = URLResourceValues()
            directoryValues.isExcludedFromBackup = true
            try? directory.setResourceValues(directoryValues)

            let eventsURL = directory.appendingPathComponent("events.ndjson")
            let visualIndexURL = visualDirectory.appendingPathComponent("visual.ndjson")
            let manifestURL = directory.appendingPathComponent("manifest.json")
            fileManager.createFile(atPath: eventsURL.path, contents: Data())
            fileManager.createFile(atPath: visualIndexURL.path, contents: Data())

            let telemetryURL = telemetryChunkURL(in: telemetryDirectory, index: 1)
            fileManager.createFile(atPath: telemetryURL.path, contents: Data())
            guard let telemetryHandle = try? FileHandle(forWritingTo: telemetryURL) else {
                return
            }

            let session = ActiveSession(
                id: id,
                directory: directory,
                telemetryDirectory: telemetryDirectory,
                keyframesDirectory: keyframesDirectory,
                burstsDirectory: burstsDirectory,
                eventsURL: eventsURL,
                visualIndexURL: visualIndexURL,
                manifestURL: manifestURL,
                startedAt: startedAt,
                version: version,
                buildSHA: buildSHA,
                telemetryHandle: telemetryHandle
            )
            active = session
            persistManifest(session: session, state: "recording", endedAt: nil)
            pruneOldSessions(excluding: id)
        }
    }

    func endSession() {
        ioQueue.sync {
            guard let session = active else { return }
            session.telemetryHandle.synchronizeFile()
            session.telemetryHandle.closeFile()
            persistManifest(
                session: session,
                state: "completed",
                endedAt: Date().timeIntervalSince1970
            )
            active = nil
            pruneOldSessions(excluding: nil)
        }
    }

    func record(telemetry: CloudTelemetrySnapshot, detections: [CloudDetection]) {
        let timestamp = Date().timeIntervalSince1970
        let detectionRecords = detections.map(Self.detectionRecord)

        ioQueue.async { [weak self] in
            guard let self, let session = self.active else { return }

            if session.recordsInTelemetryChunk >= self.telemetryChunkRecordLimit {
                self.rotateTelemetryChunk(session)
            }

            let record = TelemetryRecord(
                timestamp: timestamp,
                telemetry: telemetry,
                detections: detectionRecords
            )
            self.appendJSONLine(record, to: session.telemetryHandle)
            session.telemetryRecordCount += 1
            session.recordsInTelemetryChunk += 1

            let reasons = self.eventReasons(
                telemetry: telemetry,
                previous: session.previousTelemetry,
                session: session,
                timestamp: timestamp
            )
            for reason in reasons {
                let event = EventRecord(
                    timestamp: timestamp,
                    type: reason.type,
                    detail: reason.detail,
                    cloudCoveragePercent: telemetry.cloudCoveragePercent,
                    skyCoveragePercent: telemetry.skyCoveragePercent,
                    maskChangePercent: telemetry.maskChangePercent,
                    visibleTracks: telemetry.trackingVisibleTracks,
                    clippedPercent: telemetry.sceneClippedPercent,
                    neutralHighlightPercent: telemetry.sceneNeutralHighlightPercent,
                    thermalState: telemetry.thermalState
                )
                self.appendJSONLine(event, to: session.eventsURL)
                session.eventRecordCount += 1
                if self.shouldTriggerVisualBurst(reason: reason, telemetry: telemetry) {
                    session.burstUntil = max(session.burstUntil, timestamp + self.eventBurstDuration)
                }
            }
            session.previousTelemetry = telemetry

            if timestamp - session.lastManifestWrite >= 5 {
                self.persistManifest(session: session, state: "recording", endedAt: nil)
                session.lastManifestWrite = timestamp
            }
        }
    }

    func maybeCapture(
        sampleBuffer: CMSampleBuffer,
        overlayImage: CGImage?,
        telemetry: CloudTelemetrySnapshot,
        detections: [CloudDetection]
    ) {
        let timestamp = Date().timeIntervalSince1970

        ioQueue.async { [weak self] in
            guard let self, let session = self.active else { return }
            guard !session.visualCaptureStoppedForQuota else { return }

            let burst = timestamp <= session.burstUntil
            let validatedCloud = !detections.isEmpty
                || telemetry.trackingVisibleTracks > 0
            let semanticCloud =
                !telemetry.sceneRejected
                && telemetry.cloudCoveragePercent >= self.minimumSemanticVisualCoveragePercent
            let significantTransition =
                telemetry.maskChangePercent >= self.minimumVisualMaskChangePercent

            // No periodic black/idle frames. Keep only useful diagnostic
            // moments: cloud mask, validated detection, transition or event.
            // A burst increases capture cadence, but never creates frames on
            // its own when the image contains no useful cloud diagnostic.
            guard validatedCloud
                    || semanticCloud
                    || significantTransition else {
                return
            }

            let interval = burst ? self.burstSnapshotInterval : self.baselineSnapshotInterval
            guard timestamp - session.lastVisualTimestamp >= interval else { return }
            session.lastVisualTimestamp = timestamp

            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
                  let jpeg = self.makeCompositeJPEG(
                    pixelBuffer: pixelBuffer,
                    overlayImage: overlayImage
                  ) else {
                return
            }

            if session.visualBytes + Int64(jpeg.count) > self.maxSessionVisualBytes {
                session.visualCaptureStoppedForQuota = true
                let event = EventRecord(
                    timestamp: timestamp,
                    type: "visual_quota_reached",
                    detail: "visual capture stopped at \(session.visualBytes) bytes",
                    cloudCoveragePercent: telemetry.cloudCoveragePercent,
                    skyCoveragePercent: telemetry.skyCoveragePercent,
                    maskChangePercent: telemetry.maskChangePercent,
                    visibleTracks: telemetry.trackingVisibleTracks,
                    clippedPercent: telemetry.sceneClippedPercent,
                    neutralHighlightPercent: telemetry.sceneNeutralHighlightPercent,
                    thermalState: telemetry.thermalState
                )
                self.appendJSONLine(event, to: session.eventsURL)
                session.eventRecordCount += 1
                return
            }

            let reason: String
            if burst {
                reason = "event"
            } else if validatedCloud {
                reason = "cloud"
            } else if semanticCloud {
                reason = "semantic"
            } else {
                reason = "transition"
            }

            let milliseconds = Int(timestamp * 1_000)
            let folder = burst ? session.burstsDirectory : session.keyframesDirectory
            let fileName = "frame-\(milliseconds)-\(reason).jpg"
            let url = folder.appendingPathComponent(fileName)
            do {
                try jpeg.write(to: url, options: .atomic)
            } catch {
                return
            }

            let relativePath = "visual/\(burst ? "bursts" : "keyframes")/\(fileName)"
            let visual = VisualRecord(
                timestamp: timestamp,
                relativePath: relativePath,
                reason: reason,
                byteCount: jpeg.count,
                cloudCount: detections.count,
                cloudCoveragePercent: telemetry.cloudCoveragePercent,
                skyCoveragePercent: telemetry.skyCoveragePercent
            )
            self.appendJSONLine(visual, to: session.visualIndexURL)
            session.visualFrameCount += 1
            session.visualBytes += Int64(jpeg.count)
        }
    }

    func sessionsData() -> Data {
        ioQueue.sync {
            if let active {
                active.telemetryHandle.synchronizeFile()
                persistManifest(session: active, state: "recording", endedAt: nil)
            }
            let summaries = sessionDirectories()
                .compactMap(sessionSummary)
                .sorted { $0.startedAt > $1.startedAt }
            return encode(summaries)
        }
    }

    func activeSessionID() -> String? {
        ioQueue.sync { active?.id }
    }

    func sessionManifestData(id: String) -> Data? {
        ioQueue.sync {
            guard let directory = sessionDirectory(id: id) else { return nil }
            if let active, active.id == id {
                active.telemetryHandle.synchronizeFile()
                persistManifest(session: active, state: "recording", endedAt: nil)
            }
            return try? Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        }
    }

    func sessionFilesData(id: String) -> Data? {
        ioQueue.sync {
            guard let directory = sessionDirectory(id: id) else { return nil }
            if let active, active.id == id {
                active.telemetryHandle.synchronizeFile()
            }
            let files = recursiveFiles(in: directory).compactMap { url -> FileRecord? in
                let path = relativePath(url, under: directory)
                guard !path.isEmpty,
                      let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
                      let size = values.fileSize else {
                    return nil
                }
                return FileRecord(path: path, byteCount: Int64(size))
            }.sorted { $0.path < $1.path }
            return encode(files)
        }
    }

    func sessionFileData(id: String, relativePath: String) -> Data? {
        ioQueue.sync {
            guard let directory = sessionDirectory(id: id),
                  let url = safeFileURL(relativePath: relativePath, under: directory) else {
                return nil
            }
            if let active, active.id == id {
                active.telemetryHandle.synchronizeFile()
            }
            return try? Data(contentsOf: url, options: [.mappedIfSafe])
        }
    }

    private func telemetryChunkURL(in directory: URL, index: Int) -> URL {
        directory.appendingPathComponent(String(format: "telemetry-%04d.ndjson", index))
    }

    private func rotateTelemetryChunk(_ session: ActiveSession) {
        session.telemetryHandle.synchronizeFile()
        session.telemetryHandle.closeFile()
        session.telemetryChunkIndex += 1
        session.recordsInTelemetryChunk = 0
        let url = telemetryChunkURL(
            in: session.telemetryDirectory,
            index: session.telemetryChunkIndex
        )
        fileManager.createFile(atPath: url.path, contents: Data())
        if let next = try? FileHandle(forWritingTo: url) {
            session.telemetryHandle = next
        }
    }

    private struct EventReason {
        let type: String
        let detail: String
    }

    private func eventReasons(
        telemetry: CloudTelemetrySnapshot,
        previous: CloudTelemetrySnapshot?,
        session: ActiveSession,
        timestamp: TimeInterval
    ) -> [EventReason] {
        var candidates: [EventReason] = []

        if telemetry.trackingCreatedTracks > 0 {
            candidates.append(EventReason(
                type: "track_created",
                detail: "\(telemetry.trackingCreatedTracks) new track(s)"
            ))
        }
        if telemetry.trackingHiddenMissedTracks > 0 {
            candidates.append(EventReason(
                type: "track_missed",
                detail: "\(telemetry.trackingHiddenMissedTracks) hidden missed track(s)"
            ))
        }
        if telemetry.maskChangePercent >= 8 {
            candidates.append(EventReason(
                type: "mask_jump",
                detail: String(format: "mask delta %.1f%%", telemetry.maskChangePercent)
            ))
        }
        if telemetry.sceneClippedPercent >= 2.0 || telemetry.sceneNeutralHighlightPercent >= 5.0 {
            candidates.append(EventReason(
                type: "highlight_glare",
                detail: String(
                    format: "clipped %.1f%% neutralHighlight %.1f%%",
                    telemetry.sceneClippedPercent,
                    telemetry.sceneNeutralHighlightPercent
                )
            ))
        }
        if let previous {
            if telemetry.sceneRejected != previous.sceneRejected {
                candidates.append(EventReason(
                    type: telemetry.sceneRejected ? "scene_rejected" : "scene_accepted",
                    detail: "scene gate changed"
                ))
            }
            let wasSky = previous.skyCoveragePercent >= 5
            let isSky = telemetry.skyCoveragePercent >= 5
            if wasSky != isSky {
                candidates.append(EventReason(
                    type: isSky ? "sky_enter" : "sky_exit",
                    detail: String(format: "sky %.1f%%", telemetry.skyCoveragePercent)
                ))
            }
            if telemetry.thermalState != previous.thermalState {
                candidates.append(EventReason(
                    type: "thermal_change",
                    detail: "\(previous.thermalState)->\(telemetry.thermalState)"
                ))
            }
        }

        return candidates.filter { reason in
            let minimumSpacing: TimeInterval
            switch reason.type {
            case "track_created", "track_missed": minimumSpacing = 1.5
            case "mask_jump": minimumSpacing = 1.0
            case "highlight_glare": minimumSpacing = 2.0
            default: minimumSpacing = 0
            }
            let previousTime = session.lastEventTimes[reason.type] ?? 0
            guard timestamp - previousTime >= minimumSpacing else { return false }
            session.lastEventTimes[reason.type] = timestamp
            return true
        }
    }

    private func shouldTriggerVisualBurst(
        reason: EventReason,
        telemetry: CloudTelemetrySnapshot
    ) -> Bool {
        switch reason.type {
        case "track_created":
            return telemetry.cloudCoveragePercent >= 3.0
                && telemetry.trackingVisibleTracks > 0
        case "track_missed":
            return false
        case "mask_jump":
            return telemetry.maskChangePercent >= 12.0
        case "highlight_glare":
            return telemetry.sceneClippedPercent >= 4.0
                || telemetry.sceneNeutralHighlightPercent >= 10.0
        case "sky_enter", "sky_exit", "scene_rejected", "scene_accepted", "thermal_change":
            return true
        default:
            return false
        }
    }

    private func persistManifest(
        session: ActiveSession,
        state: String,
        endedAt: TimeInterval?
    ) {
        let manifest = Manifest(
            schemaVersion: schemaVersion,
            sessionID: session.id,
            appVersion: session.version,
            buildSHA: session.buildSHA,
            startedAt: session.startedAt,
            endedAt: endedAt,
            state: state,
            telemetryRecords: session.telemetryRecordCount,
            eventRecords: session.eventRecordCount,
            visualFrames: session.visualFrameCount,
            visualBytes: session.visualBytes,
            baselineFrameRateHz: 1.0 / baselineSnapshotInterval,
            eventFrameRateHz: 1.0 / burstSnapshotInterval,
            maxVisualDimension: maxSnapshotDimension,
            telemetryChunkRecords: telemetryChunkRecordLimit,
            storagePolicy: "local_persistent_bounded_no_cloud_upload"
        )
        try? encode(manifest).write(to: session.manifestURL, options: .atomic)
    }

    private func sessionSummary(directory: URL) -> SessionSummary? {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else {
            return nil
        }
        return SessionSummary(
            sessionID: manifest.sessionID,
            appVersion: manifest.appVersion,
            buildSHA: manifest.buildSHA,
            startedAt: manifest.startedAt,
            endedAt: manifest.endedAt,
            state: manifest.state,
            telemetryRecords: manifest.telemetryRecords,
            eventRecords: manifest.eventRecords,
            visualFrames: manifest.visualFrames,
            visualBytes: manifest.visualBytes,
            totalBytes: directorySize(directory)
        )
    }

    private func recoverInterruptedSessions() {
        for directory in sessionDirectories() {
            let manifestURL = directory.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  var manifest = try? JSONDecoder().decode(Manifest.self, from: data),
                  manifest.state == "recording" else {
                continue
            }

            let telemetryDirectory = directory.appendingPathComponent("telemetry", isDirectory: true)
            let telemetryFiles = (try? fileManager.contentsOfDirectory(
                at: telemetryDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ))?.filter { $0.pathExtension == "ndjson" } ?? []
            let eventsURL = directory.appendingPathComponent("events.ndjson")
            let visualDirectory = directory.appendingPathComponent("visual", isDirectory: true)
            let visualIndexURL = visualDirectory.appendingPathComponent("visual.ndjson")

            manifest.telemetryRecords = telemetryFiles.reduce(0) {
                $0 + countJSONLines(in: $1)
            }
            manifest.eventRecords = countJSONLines(in: eventsURL)
            manifest.visualFrames = countJSONLines(in: visualIndexURL)
            manifest.visualBytes = recursiveFiles(in: visualDirectory)
                .filter { ["jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
                .reduce(Int64(0)) { partial, url in
                    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    return partial + Int64(size)
                }
            manifest.endedAt = latestModificationTime(in: directory) ?? Date().timeIntervalSince1970
            manifest.state = "interrupted"
            try? encode(manifest).write(to: manifestURL, options: .atomic)
        }
    }

    private func countJSONLines(in url: URL) -> Int {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]), !data.isEmpty else {
            return 0
        }
        return data.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
    }

    private func latestModificationTime(in directory: URL) -> TimeInterval? {
        recursiveFiles(in: directory).compactMap { url in
            try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate?
                .timeIntervalSince1970
        }.max()
    }

    private func pruneOldSessions(excluding protectedID: String?) {
        var items = sessionDirectories().compactMap { directory -> (URL, TimeInterval, Int64)? in
            if directory.lastPathComponent == protectedID { return nil }
            guard let summary = sessionSummary(directory: directory) else { return nil }
            return (directory, summary.startedAt, summary.totalBytes)
        }.sorted { $0.1 > $1.1 }

        while items.count > maxStoredSessions - (protectedID == nil ? 0 : 1) {
            let doomed = items.removeLast()
            try? fileManager.removeItem(at: doomed.0)
        }

        var totalBytes = sessionDirectories().reduce(Int64(0)) { partial, directory in
            partial + directorySize(directory)
        }
        while totalBytes > maxGlobalBytes, let doomed = items.last {
            items.removeLast()
            totalBytes -= directorySize(doomed.0)
            try? fileManager.removeItem(at: doomed.0)
        }
    }

    private func sessionDirectories() -> [URL] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return urls.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    private func sessionDirectory(id: String) -> URL? {
        guard !id.isEmpty,
              id.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else {
            return nil
        }
        let directory = rootDirectory.appendingPathComponent(id, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }
        return directory
    }

    private func safeFileURL(relativePath: String, under directory: URL) -> URL? {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/") else {
            return nil
        }
        let url = directory.appendingPathComponent(relativePath).standardizedFileURL
        let prefix = directory.standardizedFileURL.path + "/"
        guard url.path.hasPrefix(prefix),
              fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }

    private func recursiveFiles(in directory: URL) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                files.append(url)
            }
        }
        return files
    }

    private func relativePath(_ url: URL, under directory: URL) -> String {
        let prefix = directory.standardizedFileURL.path + "/"
        let value = url.standardizedFileURL.path
        guard value.hasPrefix(prefix) else { return "" }
        return String(value.dropFirst(prefix.count))
    }

    private func directorySize(_ directory: URL) -> Int64 {
        recursiveFiles(in: directory).reduce(Int64(0)) { partial, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return partial + Int64(size)
        }
    }

    private func appendJSONLine<T: Encodable>(_ value: T, to handle: FileHandle) {
        let encoder = JSONEncoder()
        guard var data = try? encoder.encode(value) else { return }
        data.append(0x0A)
        handle.write(data)
    }

    private func appendJSONLine<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        guard var data = try? encoder.encode(value) else { return }
        data.append(0x0A)
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        handle.seekToEndOfFile()
        handle.write(data)
        handle.closeFile()
    }

    private func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(value)) ?? Data("{}".utf8)
    }

    private static func detectionRecord(_ detection: CloudDetection) -> DetectionRecord {
        DetectionRecord(
            id: detection.id,
            kind: detection.observation.kind.rawValue,
            confidence: detection.observation.confidence,
            coveragePercent: detection.observation.coverage * 100,
            centroidX: Double(detection.observation.centroid.x),
            centroidY: Double(detection.observation.centroid.y),
            boundsX: Double(detection.observation.bounds.origin.x),
            boundsY: Double(detection.observation.bounds.origin.y),
            boundsWidth: Double(detection.observation.bounds.size.width),
            boundsHeight: Double(detection.observation.bounds.size.height),
            midpointKilograms: detection.estimate.midpointKilograms,
            lowKilograms: detection.estimate.lowKilograms,
            highKilograms: detection.estimate.highKilograms,
            estimatedWidthMeters: detection.estimate.estimatedWidthMeters,
            estimatedHeightMeters: detection.estimate.estimatedHeightMeters,
            estimatedDepthMeters: detection.estimate.estimatedDepthMeters,
            estimatedDistanceMeters: detection.estimate.estimatedDistanceMeters,
            projectedAreaSquareMeters: detection.estimate.projectedAreaSquareMeters,
            estimatedVolumeCubicMeters: detection.estimate.estimatedVolumeCubicMeters,
            angularWidthDegrees: detection.estimate.angularWidthDegrees,
            angularHeightDegrees: detection.estimate.angularHeightDegrees,
            centerElevationDegrees: detection.estimate.centerElevationDegrees,
            massConfidence: detection.estimate.confidence
        )
    }

    private func makeCompositeJPEG(
        pixelBuffer: CVPixelBuffer,
        overlayImage: CGImage?
    ) -> Data? {
        let source = CIImage(cvPixelBuffer: pixelBuffer)
        guard let baseImage = context.createCGImage(source, from: source.extent) else {
            return nil
        }

        let sourceWidth = baseImage.width
        let sourceHeight = baseImage.height
        let maximum = max(sourceWidth, sourceHeight)
        let scale = min(1.0, Double(maxSnapshotDimension) / Double(maximum))
        let width = max(1, Int((Double(sourceWidth) * scale).rounded()))
        let height = max(1, Int((Double(sourceHeight) * scale).rounded()))

        guard let canvas = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        canvas.interpolationQuality = .medium
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        canvas.draw(baseImage, in: rect)
        if let overlayImage {
            canvas.draw(overlayImage, in: rect)
        }

        guard let composite = canvas.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(
            destination,
            composite,
            [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary
        )
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
