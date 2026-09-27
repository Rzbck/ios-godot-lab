import CoreGraphics
import Foundation
import OSLog
import QuartzCore

struct CloudAnalyzerTiming: Equatable {
    let preprocessingMilliseconds: Double
    let skyInferenceMilliseconds: Double
    let cloudInferenceMilliseconds: Double
    let postprocessingMilliseconds: Double
    let skyCoveragePercent: Double
}

struct CloudTelemetrySnapshot: Equatable, Codable {
    let analysisMilliseconds: Double
    let preprocessingMilliseconds: Double
    let skyInferenceMilliseconds: Double
    let cloudInferenceMilliseconds: Double
    let postprocessingMilliseconds: Double
    let effectiveHz: Double
    let maskChangePercent: Double
    let cloudCoveragePercent: Double
    let skyCoveragePercent: Double
    let coverageDeltaPercent: Double
    let rawDetections: Int
    let stabilizedDetections: Int
    let trackingActiveTracks: Int
    let trackingVisibleTracks: Int
    let trackingMatchedTracks: Int
    let trackingCreatedTracks: Int
    let trackingHiddenMissedTracks: Int
    let droppedFrames: Int
    let throttledFrames: Int
    let thermalState: String
    let orientation: String
    let deviceOrientation: String
    let captureWidth: Int
    let captureHeight: Int
    let captureRotationDegrees: Double
    let sceneLuminancePercent: Double
    let sceneRejected: Bool
}

final class CloudTelemetryMonitor {
    private struct Sample {
        let elapsedSeconds: Double
        let snapshot: CloudTelemetrySnapshot
    }

    private let logger = Logger(
        subsystem: "com.rzbck.cloudweightlab",
        category: "telemetry"
    )
    private let sessionStarted = CACurrentMediaTime()
    private let maxSamples = 180

    private var samples: [Sample] = []
    private var previousCompletionTime: CFTimeInterval?
    private var previousCoverage: Double?
    private var previousMask: [UInt8]?
    private var smoothedAnalysisMilliseconds: Double?
    private var smoothedHz: Double?
    private var lastLogTime = 0.0

    func reset() {
        samples.removeAll(keepingCapacity: true)
        previousCompletionTime = nil
        previousCoverage = nil
        previousMask = nil
        smoothedAnalysisMilliseconds = nil
        smoothedHz = nil
        lastLogTime = 0
    }

    func snapshot(
        analysisDurationSeconds: Double,
        analyzerTiming: CloudAnalyzerTiming?,
        analysis: CloudFrameAnalysis?,
        rawDetections: Int,
        stabilizedDetections: Int,
        trackingStats: CloudTrackingStats,
        droppedFrames: Int,
        throttledFrames: Int,
        orientation: String,
        deviceOrientation: String,
        captureWidth: Int,
        captureHeight: Int,
        captureRotationDegrees: Double,
        sceneLuminancePercent: Double,
        sceneRejected: Bool
    ) -> CloudTelemetrySnapshot {
        let now = CACurrentMediaTime()
        let milliseconds = analysisDurationSeconds * 1_000
        smoothedAnalysisMilliseconds = exponentialAverage(
            previous: smoothedAnalysisMilliseconds,
            value: milliseconds,
            alpha: 0.24
        )

        if let previousCompletionTime {
            let interval = max(0.001, now - previousCompletionTime)
            smoothedHz = exponentialAverage(
                previous: smoothedHz,
                value: 1.0 / interval,
                alpha: 0.28
            )
        }
        previousCompletionTime = now

        let coverage = analysis?.totalCoverage ?? 0
        let coverageDelta = abs(coverage - (previousCoverage ?? coverage)) * 100
        previousCoverage = coverage

        let currentMask = analysis?.overlayImage.flatMap(alphaMask)
        let maskChange = maskChangePercent(
            previous: previousMask,
            current: currentMask
        )
        previousMask = currentMask

        let snapshot = CloudTelemetrySnapshot(
            analysisMilliseconds: smoothedAnalysisMilliseconds ?? milliseconds,
            preprocessingMilliseconds: analyzerTiming?.preprocessingMilliseconds ?? 0,
            skyInferenceMilliseconds: analyzerTiming?.skyInferenceMilliseconds ?? 0,
            cloudInferenceMilliseconds: analyzerTiming?.cloudInferenceMilliseconds ?? 0,
            postprocessingMilliseconds: analyzerTiming?.postprocessingMilliseconds ?? 0,
            effectiveHz: smoothedHz ?? 0,
            maskChangePercent: maskChange,
            cloudCoveragePercent: coverage * 100,
            skyCoveragePercent: analyzerTiming?.skyCoveragePercent ?? 0,
            coverageDeltaPercent: coverageDelta,
            rawDetections: rawDetections,
            stabilizedDetections: stabilizedDetections,
            trackingActiveTracks: trackingStats.activeTracks,
            trackingVisibleTracks: trackingStats.visibleTracks,
            trackingMatchedTracks: trackingStats.matchedTracks,
            trackingCreatedTracks: trackingStats.createdTracks,
            trackingHiddenMissedTracks: trackingStats.hiddenMissedTracks,
            droppedFrames: droppedFrames,
            throttledFrames: throttledFrames,
            thermalState: thermalStateName(ProcessInfo.processInfo.thermalState),
            orientation: orientation,
            deviceOrientation: deviceOrientation,
            captureWidth: captureWidth,
            captureHeight: captureHeight,
            captureRotationDegrees: captureRotationDegrees,
            sceneLuminancePercent: sceneLuminancePercent,
            sceneRejected: sceneRejected
        )

        samples.append(
            Sample(
                elapsedSeconds: now - sessionStarted,
                snapshot: snapshot
            )
        )
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }

        if now - lastLogTime >= 2.0 {
            lastLogTime = now
            let line = String(
                format: "pipeline=%.0fms prep=%.0fms sky=%.0fms cloud=%.0fms post=%.0fms hz=%.2f maskDelta=%.1f%% cloudCov=%.1f%% skyCov=%.1f%% raw=%d visible=%d tracks=%d hidden=%d matched=%d new=%d drop=%d throttle=%d thermal=%@ capture=%@ %dx%d rot=%.1f device=%@ luma=%.1f%% rejected=%@",
                snapshot.analysisMilliseconds,
                snapshot.preprocessingMilliseconds,
                snapshot.skyInferenceMilliseconds,
                snapshot.cloudInferenceMilliseconds,
                snapshot.postprocessingMilliseconds,
                snapshot.effectiveHz,
                snapshot.maskChangePercent,
                snapshot.cloudCoveragePercent,
                snapshot.skyCoveragePercent,
                snapshot.rawDetections,
                snapshot.trackingVisibleTracks,
                snapshot.trackingActiveTracks,
                snapshot.trackingHiddenMissedTracks,
                snapshot.trackingMatchedTracks,
                snapshot.trackingCreatedTracks,
                snapshot.droppedFrames,
                snapshot.throttledFrames,
                snapshot.thermalState,
                snapshot.orientation,
                snapshot.captureWidth,
                snapshot.captureHeight,
                snapshot.captureRotationDegrees,
                snapshot.deviceOrientation,
                snapshot.sceneLuminancePercent,
                snapshot.sceneRejected ? "yes" : "no"
            )
            logger.info("\(line, privacy: .public)")
        }

        return snapshot
    }

    func makeReport(buildSHA: String) -> String {
        guard !samples.isEmpty else {
            return [
                "CLOUD_WEIGHT_DIAG_V8",
                "build=\(buildSHA)",
                "samples=0",
                "privacy=local_bounded_diagnostics"
            ].joined(separator: "\n")
        }

        let snapshots = samples.map(\.snapshot)
        let pipelines = snapshots.map(\.analysisMilliseconds)
        let preps = snapshots.map(\.preprocessingMilliseconds)
        let skies = snapshots.map(\.skyInferenceMilliseconds)
        let clouds = snapshots.map(\.cloudInferenceMilliseconds)
        let posts = snapshots.map(\.postprocessingMilliseconds)
        let maskChanges = snapshots.map(\.maskChangePercent)
        let rates = snapshots.map(\.effectiveHz).filter { $0 > 0 }
        let droppedTotal = snapshots.reduce(0) { $0 + $1.droppedFrames }
        let throttledTotal = snapshots.reduce(0) { $0 + $1.throttledFrames }
        let hiddenMissTotal = snapshots.reduce(0) { $0 + $1.trackingHiddenMissedTracks }
        let createdTrackTotal = snapshots.reduce(0) { $0 + $1.trackingCreatedTracks }
        let rejectedTotal = snapshots.filter(\.sceneRejected).count
        let latest = snapshots.last!

        var lines = [
            "CLOUD_WEIGHT_DIAG_V8",
            "build=\(buildSHA)",
            "samples=\(samples.count)",
            "privacy=local_bounded_diagnostics",
            "capture_last=\(latest.orientation) \(latest.captureWidth)x\(latest.captureHeight) rot=\(number(latest.captureRotationDegrees, decimals: 1))",
            "device_orientation_last=\(latest.deviceOrientation)",
            "thermal_last=\(latest.thermalState)",
            "scene_luma_last_pct=\(number(latest.sceneLuminancePercent, decimals: 1))",
            "scene_rejected_last=\(latest.sceneRejected)",
            "scene_rejected_total=\(rejectedTotal)",
            "pipeline_ms_avg=\(number(average(pipelines), decimals: 1))",
            "pipeline_ms_p95=\(number(percentile(pipelines, fraction: 0.95), decimals: 1))",
            "pipeline_ms_max=\(number(pipelines.max() ?? 0, decimals: 1))",
            "preprocess_ms_avg=\(number(average(preps), decimals: 1))",
            "sky_ms_avg=\(number(average(skies), decimals: 1))",
            "cloud_ms_avg=\(number(average(clouds), decimals: 1))",
            "post_ms_avg=\(number(average(posts), decimals: 1))",
            "effective_hz_avg=\(number(average(rates), decimals: 2))",
            "mask_delta_pct_avg=\(number(average(maskChanges), decimals: 2))",
            "mask_delta_pct_p95=\(number(percentile(maskChanges, fraction: 0.95), decimals: 2))",
            "drop_total=\(droppedTotal)",
            "throttle_total=\(throttledTotal)",
            "tracking_hidden_miss_total=\(hiddenMissTotal)",
            "tracking_created_total=\(createdTrackTotal)",
            "last_cloud_coverage_pct=\(number(latest.cloudCoveragePercent, decimals: 1))",
            "last_sky_coverage_pct=\(number(latest.skyCoveragePercent, decimals: 1))",
            "last_raw_to_visible=\(latest.rawDetections)->\(latest.trackingVisibleTracks)",
            "last_tracks_active_hidden=\(latest.trackingActiveTracks)/\(latest.trackingHiddenMissedTracks)",
            "series_last_20:"
        ]

        for sample in samples.suffix(20) {
            let value = sample.snapshot
            lines.append(
                "t=\(number(sample.elapsedSeconds, decimals: 1))s total=\(number(value.analysisMilliseconds, decimals: 0)) prep=\(number(value.preprocessingMilliseconds, decimals: 0)) sky=\(number(value.skyInferenceMilliseconds, decimals: 0)) cloud=\(number(value.cloudInferenceMilliseconds, decimals: 0)) post=\(number(value.postprocessingMilliseconds, decimals: 0)) hz=\(number(value.effectiveHz, decimals: 2)) mask=\(number(value.maskChangePercent, decimals: 1)) cloudCov=\(number(value.cloudCoveragePercent, decimals: 1)) skyCov=\(number(value.skyCoveragePercent, decimals: 1)) raw=\(value.rawDetections) visible=\(value.trackingVisibleTracks) active=\(value.trackingActiveTracks) hidden=\(value.trackingHiddenMissedTracks) matched=\(value.trackingMatchedTracks) new=\(value.trackingCreatedTracks) drop=\(value.droppedFrames) throttle=\(value.throttledFrames) capture=\(value.orientation) size=\(value.captureWidth)x\(value.captureHeight) rot=\(number(value.captureRotationDegrees, decimals: 1)) device=\(value.deviceOrientation) luma=\(number(value.sceneLuminancePercent, decimals: 1)) reject=\(value.sceneRejected) thermal=\(value.thermalState)"
            )
        }

        return lines.joined(separator: "\n")
    }

    private func exponentialAverage(
        previous: Double?,
        value: Double,
        alpha: Double
    ) -> Double {
        guard let previous else { return value }
        return previous + (value - previous) * alpha
    }

    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func percentile(_ values: [Double], fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = Int((Double(sorted.count - 1) * fraction.clamped(0...1)).rounded())
        return sorted[index]
    }

    private func number(_ value: Double, decimals: Int) -> String {
        String(
            format: "%.*f",
            locale: Locale(identifier: "en_US_POSIX"),
            decimals,
            value
        )
    }

    private func alphaMask(from image: CGImage) -> [UInt8]? {
        guard image.bitsPerPixel >= 32,
              let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return nil
        }

        let bytesPerPixel = max(1, image.bitsPerPixel / 8)
        let alphaOffset = min(3, bytesPerPixel - 1)
        var mask = [UInt8](repeating: 0, count: image.width * image.height)

        for y in 0..<image.height {
            let row = y * image.bytesPerRow
            for x in 0..<image.width {
                let offset = row + x * bytesPerPixel + alphaOffset
                mask[y * image.width + x] = bytes[offset] > 0 ? 1 : 0
            }
        }
        return mask
    }

    private func maskChangePercent(
        previous: [UInt8]?,
        current: [UInt8]?
    ) -> Double {
        guard let previous,
              let current,
              previous.count == current.count,
              !current.isEmpty else {
            return 0
        }

        var changed = 0
        for index in current.indices where current[index] != previous[index] {
            changed += 1
        }
        return Double(changed) / Double(current.count) * 100
    }

    private func thermalStateName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}
