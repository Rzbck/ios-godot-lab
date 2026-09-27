import CoreGraphics
import Foundation
import OSLog
import QuartzCore

struct CloudAnalyzerTiming: Equatable {
    let preprocessingMilliseconds: Double
    let skyInferenceMilliseconds: Double
    let cloudInferenceMilliseconds: Double
    let inferenceWallMilliseconds: Double
    let parallelOverlapMilliseconds: Double
    let postprocessingMilliseconds: Double
    let skyCoveragePercent: Double
    let strictSkyCoveragePercent: Double
    let relaxedSkyCoveragePercent: Double
    let semanticBlockerCoveragePercent: Double
    let semanticTreeCoveragePercent: Double
    let semanticBuildingCoveragePercent: Double
    let semanticPersonCoveragePercent: Double
    let semanticPlantCoveragePercent: Double
    let semanticWallCoveragePercent: Double
    let semanticFallbackCoveragePercent: Double
    let skySceneActive: Bool
    let skyGateMode: String
    let inferenceMode: String
}

struct CloudTelemetrySnapshot: Equatable, Codable {
    let analysisMilliseconds: Double
    let preprocessingMilliseconds: Double
    let skyInferenceMilliseconds: Double
    let cloudInferenceMilliseconds: Double
    let inferenceWallMilliseconds: Double
    let parallelOverlapMilliseconds: Double
    let postprocessingMilliseconds: Double
    let effectiveHz: Double
    let maskChangePercent: Double
    let cloudCoveragePercent: Double
    let skyCoveragePercent: Double
    let strictSkyCoveragePercent: Double
    let relaxedSkyCoveragePercent: Double
    let semanticBlockerCoveragePercent: Double
    let semanticTreeCoveragePercent: Double
    let semanticBuildingCoveragePercent: Double
    let semanticPersonCoveragePercent: Double
    let semanticPlantCoveragePercent: Double
    let semanticWallCoveragePercent: Double
    let semanticFallbackCoveragePercent: Double
    let skySceneActive: Bool
    let skyGateMode: String
    let inferenceMode: String
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
    let sceneSaturationPercent: Double
    let sceneDarkPercent: Double
    let sceneBrightPercent: Double
    let sceneClippedPercent: Double
    let sceneNeutralHighlightPercent: Double
    let sceneRejected: Bool
    let lowLightMode: Bool
    let cameraISO: Double
    let cameraExposureMilliseconds: Double
    let cameraExposureTargetOffset: Double
    let cameraLowLightBoostSupported: Bool
    let cameraLowLightBoostEnabled: Bool
    let cameraWhiteBalanceTemperatureKelvin: Double
    let cameraWhiteBalanceTint: Double
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
        sceneSaturationPercent: Double,
        sceneDarkPercent: Double,
        sceneBrightPercent: Double,
        sceneClippedPercent: Double,
        sceneNeutralHighlightPercent: Double,
        sceneRejected: Bool,
        lowLightMode: Bool,
        cameraISO: Double,
        cameraExposureMilliseconds: Double,
        cameraExposureTargetOffset: Double,
        cameraLowLightBoostSupported: Bool,
        cameraLowLightBoostEnabled: Bool,
        cameraWhiteBalanceTemperatureKelvin: Double,
        cameraWhiteBalanceTint: Double
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
        let maskChange = maskChangePercent(previous: previousMask, current: currentMask)
        previousMask = currentMask

        let snapshot = CloudTelemetrySnapshot(
            analysisMilliseconds: smoothedAnalysisMilliseconds ?? milliseconds,
            preprocessingMilliseconds: analyzerTiming?.preprocessingMilliseconds ?? 0,
            skyInferenceMilliseconds: analyzerTiming?.skyInferenceMilliseconds ?? 0,
            cloudInferenceMilliseconds: analyzerTiming?.cloudInferenceMilliseconds ?? 0,
            inferenceWallMilliseconds: analyzerTiming?.inferenceWallMilliseconds ?? 0,
            parallelOverlapMilliseconds: analyzerTiming?.parallelOverlapMilliseconds ?? 0,
            postprocessingMilliseconds: analyzerTiming?.postprocessingMilliseconds ?? 0,
            effectiveHz: smoothedHz ?? 0,
            maskChangePercent: maskChange,
            cloudCoveragePercent: coverage * 100,
            skyCoveragePercent: analyzerTiming?.skyCoveragePercent ?? 0,
            strictSkyCoveragePercent: analyzerTiming?.strictSkyCoveragePercent ?? 0,
            relaxedSkyCoveragePercent: analyzerTiming?.relaxedSkyCoveragePercent ?? 0,
            semanticBlockerCoveragePercent: analyzerTiming?.semanticBlockerCoveragePercent ?? 0,
            semanticTreeCoveragePercent: analyzerTiming?.semanticTreeCoveragePercent ?? 0,
            semanticBuildingCoveragePercent: analyzerTiming?.semanticBuildingCoveragePercent ?? 0,
            semanticPersonCoveragePercent: analyzerTiming?.semanticPersonCoveragePercent ?? 0,
            semanticPlantCoveragePercent: analyzerTiming?.semanticPlantCoveragePercent ?? 0,
            semanticWallCoveragePercent: analyzerTiming?.semanticWallCoveragePercent ?? 0,
            semanticFallbackCoveragePercent: analyzerTiming?.semanticFallbackCoveragePercent ?? 0,
            skySceneActive: analyzerTiming?.skySceneActive ?? false,
            skyGateMode: analyzerTiming?.skyGateMode ?? (sceneRejected ? "scene_rejected" : "unavailable"),
            inferenceMode: analyzerTiming?.inferenceMode ?? "skipped",
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
            sceneSaturationPercent: sceneSaturationPercent,
            sceneDarkPercent: sceneDarkPercent,
            sceneBrightPercent: sceneBrightPercent,
            sceneClippedPercent: sceneClippedPercent,
            sceneNeutralHighlightPercent: sceneNeutralHighlightPercent,
            sceneRejected: sceneRejected,
            lowLightMode: lowLightMode,
            cameraISO: cameraISO,
            cameraExposureMilliseconds: cameraExposureMilliseconds,
            cameraExposureTargetOffset: cameraExposureTargetOffset,
            cameraLowLightBoostSupported: cameraLowLightBoostSupported,
            cameraLowLightBoostEnabled: cameraLowLightBoostEnabled,
            cameraWhiteBalanceTemperatureKelvin: cameraWhiteBalanceTemperatureKelvin,
            cameraWhiteBalanceTint: cameraWhiteBalanceTint
        )

        samples.append(Sample(elapsedSeconds: now - sessionStarted, snapshot: snapshot))
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }

        if now - lastLogTime >= 2.0 {
            lastLogTime = now
            let line = String(
                format: "pipeline=%.0fms prep=%.0fms sky=%.0fms cloud=%.0fms inferWall=%.0fms overlap=%.0fms post=%.0fms hz=%.2f gate=%@ infer=%@ skyEffective=%.1f%% strictSky=%.1f%% relaxedSky=%.1f%% blocker=%.1f%% tree=%.1f%% building=%.1f%% fallback=%.1f%% cloudCov=%.1f%% raw=%d visible=%d thermal=%@ luma=%.1f%% sat=%.1f%% iso=%.0f exp=%.2fms boost=%@ lowlight=%@",
                snapshot.analysisMilliseconds,
                snapshot.preprocessingMilliseconds,
                snapshot.skyInferenceMilliseconds,
                snapshot.cloudInferenceMilliseconds,
                snapshot.inferenceWallMilliseconds,
                snapshot.parallelOverlapMilliseconds,
                snapshot.postprocessingMilliseconds,
                snapshot.effectiveHz,
                snapshot.skyGateMode,
                snapshot.inferenceMode,
                snapshot.skyCoveragePercent,
                snapshot.strictSkyCoveragePercent,
                snapshot.relaxedSkyCoveragePercent,
                snapshot.semanticBlockerCoveragePercent,
                snapshot.semanticTreeCoveragePercent,
                snapshot.semanticBuildingCoveragePercent,
                snapshot.semanticFallbackCoveragePercent,
                snapshot.cloudCoveragePercent,
                snapshot.rawDetections,
                snapshot.trackingVisibleTracks,
                snapshot.thermalState,
                snapshot.sceneLuminancePercent,
                snapshot.sceneSaturationPercent,
                snapshot.cameraISO,
                snapshot.cameraExposureMilliseconds,
                snapshot.cameraLowLightBoostEnabled ? "on" : "off",
                snapshot.lowLightMode ? "yes" : "no"
            )
            logger.info("\(line, privacy: .public)")
        }

        return snapshot
    }

    func makeReport(buildSHA: String) -> String {
        guard !samples.isEmpty else {
            return [
                "CLOUD_WEIGHT_DIAG_V12",
                "build=\(buildSHA)",
                "samples=0",
                "privacy=local_persistent_session_recorder"
            ].joined(separator: "\n")
        }

        let snapshots = samples.map(\.snapshot)
        let pipelines = snapshots.map(\.analysisMilliseconds)
        let walls = snapshots.map(\.inferenceWallMilliseconds)
        let overlaps = snapshots.map(\.parallelOverlapMilliseconds)
        let rates = snapshots.map(\.effectiveHz).filter { $0 > 0 }
        let blocker = snapshots.map(\.semanticBlockerCoveragePercent)
        let fallback = snapshots.map(\.semanticFallbackCoveragePercent)
        let latest = snapshots.last!

        var lines = [
            "CLOUD_WEIGHT_DIAG_V12",
            "build=\(buildSHA)",
            "samples=\(samples.count)",
            "privacy=local_persistent_session_recorder",
            "gate_last=\(latest.skyGateMode)",
            "sky_scene_active_last=\(latest.skySceneActive)",
            "inference_mode_last=\(latest.inferenceMode)",
            "low_light_last=\(latest.lowLightMode)",
            "low_light_boost_supported=\(latest.cameraLowLightBoostSupported)",
            "low_light_boost_enabled_last=\(latest.cameraLowLightBoostEnabled)",
            "pipeline_ms_avg=\(number(average(pipelines), decimals: 1))",
            "pipeline_ms_p95=\(number(percentile(pipelines, fraction: 0.95), decimals: 1))",
            "inference_wall_ms_avg=\(number(average(walls), decimals: 1))",
            "parallel_overlap_ms_avg=\(number(average(overlaps), decimals: 1))",
            "effective_hz_avg=\(number(average(rates), decimals: 2))",
            "blocker_pct_avg=\(number(average(blocker), decimals: 2))",
            "fallback_pct_avg=\(number(average(fallback), decimals: 2))",
            "sky_effective_last_pct=\(number(latest.skyCoveragePercent, decimals: 1))",
            "strict_sky_last_pct=\(number(latest.strictSkyCoveragePercent, decimals: 1))",
            "relaxed_sky_last_pct=\(number(latest.relaxedSkyCoveragePercent, decimals: 1))",
            "tree_last_pct=\(number(latest.semanticTreeCoveragePercent, decimals: 1))",
            "building_last_pct=\(number(latest.semanticBuildingCoveragePercent, decimals: 1))",
            "person_last_pct=\(number(latest.semanticPersonCoveragePercent, decimals: 1))",
            "plant_last_pct=\(number(latest.semanticPlantCoveragePercent, decimals: 1))",
            "wall_last_pct=\(number(latest.semanticWallCoveragePercent, decimals: 1))",
            "scene_luma_last_pct=\(number(latest.sceneLuminancePercent, decimals: 1))",
            "scene_saturation_last_pct=\(number(latest.sceneSaturationPercent, decimals: 1))",
            "camera_iso_last=\(number(latest.cameraISO, decimals: 0))",
            "camera_exposure_last_ms=\(number(latest.cameraExposureMilliseconds, decimals: 2))",
            "camera_wb_temp_last_k=\(number(latest.cameraWhiteBalanceTemperatureKelvin, decimals: 0))",
            "camera_wb_tint_last=\(number(latest.cameraWhiteBalanceTint, decimals: 1))",
            "series_last_20:"
        ]

        for sample in samples.suffix(20) {
            let value = sample.snapshot
            lines.append(
                "t=\(number(sample.elapsedSeconds, decimals: 1))s total=\(number(value.analysisMilliseconds, decimals: 0)) inferWall=\(number(value.inferenceWallMilliseconds, decimals: 0)) overlap=\(number(value.parallelOverlapMilliseconds, decimals: 0)) hz=\(number(value.effectiveHz, decimals: 2)) gate=\(value.skyGateMode) skyEff=\(number(value.skyCoveragePercent, decimals: 1)) strictSky=\(number(value.strictSkyCoveragePercent, decimals: 1)) relaxedSky=\(number(value.relaxedSkyCoveragePercent, decimals: 1)) blocker=\(number(value.semanticBlockerCoveragePercent, decimals: 1)) tree=\(number(value.semanticTreeCoveragePercent, decimals: 1)) building=\(number(value.semanticBuildingCoveragePercent, decimals: 1)) fallback=\(number(value.semanticFallbackCoveragePercent, decimals: 1)) cloud=\(number(value.cloudCoveragePercent, decimals: 1)) raw=\(value.rawDetections) visible=\(value.trackingVisibleTracks) luma=\(number(value.sceneLuminancePercent, decimals: 1)) sat=\(number(value.sceneSaturationPercent, decimals: 1)) iso=\(number(value.cameraISO, decimals: 0)) exp=\(number(value.cameraExposureMilliseconds, decimals: 2)) boost=\(value.cameraLowLightBoostEnabled) low=\(value.lowLightMode) thermal=\(value.thermalState)"
            )
        }

        return lines.joined(separator: "\n")
    }

    private func exponentialAverage(previous: Double?, value: Double, alpha: Double) -> Double {
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

    private func maskChangePercent(previous: [UInt8]?, current: [UInt8]?) -> Double {
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
