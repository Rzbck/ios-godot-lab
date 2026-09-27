import AVFoundation
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import QuartzCore
import UniformTypeIdentifiers

final class CloudDiagnosticsStore {
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
    }

    struct TelemetryRecord: Codable {
        let timestamp: TimeInterval
        let telemetry: CloudTelemetrySnapshot
        let detections: [DetectionRecord]
    }

    struct SnapshotRecord: Codable {
        let id: String
        let timestamp: TimeInterval
        let fileName: String
        let byteCount: Int
        let orientation: String
        let cloudCount: Int
        let cloudCoveragePercent: Double
        let skyCoveragePercent: Double
    }

    struct StatusPayload: Codable {
        let app: String
        let version: String
        let build: String
        let timestamp: TimeInterval
        let telemetry: CloudTelemetrySnapshot?
        let detections: [DetectionRecord]
        let snapshotCount: Int
        let captureEnabled: Bool
        let diagnosticFrameRateHz: Double
        let diagnosticFrameCapacity: Int
        let diagnosticMaxDimension: Int
    }

    private let lock = NSLock()
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let imageQueue = DispatchQueue(label: "cloudweight.diagnostics.images", qos: .utility)
    private let fileManager = FileManager.default
    private let maxTelemetryRecords = 900
    private let maxSnapshots = 48
    private let snapshotLifetime: TimeInterval = 10 * 60
    private let snapshotInterval: CFTimeInterval = 0.25
    private let maxSnapshotDimension = 480
    private let jpegQuality = 0.32

    private var latestTelemetry: CloudTelemetrySnapshot?
    private var latestDetections: [DetectionRecord] = []
    private var telemetryRecords: [TelemetryRecord] = []
    private var snapshots: [SnapshotRecord] = []
    private var captureEnabled = false
    private var snapshotCaptureInFlight = false
    private var lastSnapshotTime: CFTimeInterval = 0

    private let directory: URL

    init() {
        directory = fileManager.temporaryDirectory
            .appendingPathComponent("CloudWeightDiagnosticsV8", isDirectory: true)
        try? fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        cleanupFilesOlderThanLifetime()
    }

    func setCaptureEnabled(_ enabled: Bool) {
        lock.lock()
        captureEnabled = enabled
        if !enabled {
            lastSnapshotTime = 0
        }
        lock.unlock()
    }

    func record(
        telemetry: CloudTelemetrySnapshot,
        detections: [CloudDetection]
    ) {
        let detectionRecords = detections.map(Self.detectionRecord)
        let telemetryRecord = TelemetryRecord(
            timestamp: Date().timeIntervalSince1970,
            telemetry: telemetry,
            detections: detectionRecords
        )

        lock.lock()
        latestTelemetry = telemetry
        latestDetections = detectionRecords
        telemetryRecords.append(telemetryRecord)
        if telemetryRecords.count > maxTelemetryRecords {
            telemetryRecords.removeFirst(telemetryRecords.count - maxTelemetryRecords)
        }
        lock.unlock()
    }

    func maybeCapture(
        sampleBuffer: CMSampleBuffer,
        overlayImage: CGImage?,
        telemetry: CloudTelemetrySnapshot,
        detections: [CloudDetection]
    ) {
        let now = CACurrentMediaTime()

        lock.lock()
        let shouldCapture = captureEnabled
            && !snapshotCaptureInFlight
            && now - lastSnapshotTime >= snapshotInterval
        if shouldCapture {
            lastSnapshotTime = now
            snapshotCaptureInFlight = true
        }
        lock.unlock()

        guard shouldCapture else { return }

        imageQueue.async { [weak self] in
            guard let self else { return }
            defer {
                self.lock.lock()
                self.snapshotCaptureInFlight = false
                self.lock.unlock()
            }
            self.writeSnapshot(
                sampleBuffer: sampleBuffer,
                overlayImage: overlayImage,
                telemetry: telemetry,
                detections: detections
            )
        }
    }

    private func writeSnapshot(
        sampleBuffer: CMSampleBuffer,
        overlayImage: CGImage?,
        telemetry: CloudTelemetrySnapshot,
        detections: [CloudDetection]
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
              let jpeg = makeCompositeJPEG(
                pixelBuffer: pixelBuffer,
                overlayImage: overlayImage
              ) else {
            return
        }

        let timestamp = Date().timeIntervalSince1970
        let id = String(Int(timestamp * 1_000))
        let fileName = "snapshot-\(id).jpg"
        let url = directory.appendingPathComponent(fileName)

        do {
            try jpeg.write(to: url, options: .atomic)
        } catch {
            return
        }

        let record = SnapshotRecord(
            id: id,
            timestamp: timestamp,
            fileName: fileName,
            byteCount: jpeg.count,
            orientation: telemetry.orientation,
            cloudCount: detections.count,
            cloudCoveragePercent: telemetry.cloudCoveragePercent,
            skyCoveragePercent: telemetry.skyCoveragePercent
        )

        lock.lock()
        snapshots.append(record)
        cleanupSnapshotsLocked(now: timestamp)
        lock.unlock()
    }

    func statusData(buildSHA: String, version: String) -> Data {
        lock.lock()
        cleanupSnapshotsLocked(now: Date().timeIntervalSince1970)
        let payload = StatusPayload(
            app: "Cloud Weight Lab",
            version: version,
            build: buildSHA,
            timestamp: Date().timeIntervalSince1970,
            telemetry: latestTelemetry,
            detections: latestDetections,
            snapshotCount: snapshots.count,
            captureEnabled: captureEnabled,
            diagnosticFrameRateHz: 1.0 / snapshotInterval,
            diagnosticFrameCapacity: maxSnapshots,
            diagnosticMaxDimension: maxSnapshotDimension
        )
        lock.unlock()
        return encode(payload)
    }

    func telemetryData(limit: Int, after timestamp: TimeInterval?) -> Data {
        lock.lock()
        let safeLimit = min(max(1, limit), maxTelemetryRecords)
        let filtered: [TelemetryRecord]
        if let timestamp {
            filtered = telemetryRecords.filter { $0.timestamp > timestamp }
        } else {
            filtered = telemetryRecords
        }
        let payload = Array(filtered.suffix(safeLimit))
        lock.unlock()
        return encode(payload)
    }

    func snapshotListData() -> Data {
        lock.lock()
        cleanupSnapshotsLocked(now: Date().timeIntervalSince1970)
        let payload = snapshots
        lock.unlock()
        return encode(payload)
    }

    func latestSnapshotData() -> Data? {
        lock.lock()
        cleanupSnapshotsLocked(now: Date().timeIntervalSince1970)
        let record = snapshots.last
        lock.unlock()
        guard let record else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(record.fileName))
    }

    func snapshotData(id: String) -> Data? {
        lock.lock()
        cleanupSnapshotsLocked(now: Date().timeIntervalSince1970)
        let record = snapshots.first { $0.id == id }
        lock.unlock()
        guard let record else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(record.fileName))
    }

    func removeAllSnapshots() {
        lock.lock()
        let doomed = snapshots
        snapshots.removeAll(keepingCapacity: true)
        lock.unlock()

        for item in doomed {
            try? fileManager.removeItem(at: directory.appendingPathComponent(item.fileName))
        }
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
            highKilograms: detection.estimate.highKilograms
        )
    }

    private func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(value)) ?? Data("{}".utf8)
    }

    private func cleanupSnapshotsLocked(now: TimeInterval) {
        var doomed: [SnapshotRecord] = []

        while let first = snapshots.first,
              now - first.timestamp > snapshotLifetime {
            doomed.append(first)
            snapshots.removeFirst()
        }

        if snapshots.count > maxSnapshots {
            let overflow = snapshots.count - maxSnapshots
            doomed.append(contentsOf: snapshots.prefix(overflow))
            snapshots.removeFirst(overflow)
        }

        for item in doomed {
            try? fileManager.removeItem(at: directory.appendingPathComponent(item.fileName))
        }
    }

    private func cleanupFilesOlderThanLifetime() {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else {
            return
        }

        let now = Date()
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            let modified = values?.contentModificationDate ?? .distantPast
            if now.timeIntervalSince(modified) > snapshotLifetime {
                try? fileManager.removeItem(at: url)
            }
        }
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
