import CoreGraphics
import Foundation
import OSLog
import QuartzCore

struct CloudTelemetrySnapshot: Equatable {
    let analysisMilliseconds: Double
    let effectiveHz: Double
    let maskChangePercent: Double
    let cloudCoveragePercent: Double
    let coverageDeltaPercent: Double
    let rawDetections: Int
    let stabilizedDetections: Int
    let throttledFrames: Int
    let thermalState: String
}

final class CloudTelemetryMonitor {
    private let logger = Logger(
        subsystem: "com.rzbck.cloudweightlab",
        category: "telemetry"
    )

    private var previousCompletionTime: CFTimeInterval?
    private var previousCoverage: Double?
    private var previousMask: [UInt8]?
    private var smoothedAnalysisMilliseconds: Double?
    private var smoothedHz: Double?
    private var lastLogTime = 0.0

    func reset() {
        previousCompletionTime = nil
        previousCoverage = nil
        previousMask = nil
        smoothedAnalysisMilliseconds = nil
        smoothedHz = nil
        lastLogTime = 0
    }

    func snapshot(
        analysisDurationSeconds: Double,
        analysis: CloudFrameAnalysis?,
        rawDetections: Int,
        stabilizedDetections: Int,
        throttledFrames: Int
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
            effectiveHz: smoothedHz ?? 0,
            maskChangePercent: maskChange,
            cloudCoveragePercent: coverage * 100,
            coverageDeltaPercent: coverageDelta,
            rawDetections: rawDetections,
            stabilizedDetections: stabilizedDetections,
            throttledFrames: throttledFrames,
            thermalState: thermalStateName(ProcessInfo.processInfo.thermalState)
        )

        if now - lastLogTime >= 2.0 {
            lastLogTime = now
            let line = String(
                format: "analysis=%.0fms hz=%.2f maskDelta=%.1f%% coverage=%.1f%% coverageDelta=%.1f%% raw=%d stable=%d throttle=%d thermal=%@",
                snapshot.analysisMilliseconds,
                snapshot.effectiveHz,
                snapshot.maskChangePercent,
                snapshot.cloudCoveragePercent,
                snapshot.coverageDeltaPercent,
                snapshot.rawDetections,
                snapshot.stabilizedDetections,
                snapshot.throttledFrames,
                snapshot.thermalState
            )
            logger.info("\(line, privacy: .public)")
        }

        return snapshot
    }

    private func exponentialAverage(
        previous: Double?,
        value: Double,
        alpha: Double
    ) -> Double {
        guard let previous else { return value }
        return previous + (value - previous) * alpha
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
