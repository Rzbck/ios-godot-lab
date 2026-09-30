import AVFoundation
import CoreGraphics
import Foundation

// The control build intentionally restores the exact V8/V11 analyzer core.
// This file only adapts that core to the current telemetry/lifecycle shell;
// it must not change segmentation geometry.
struct CloudAnalysisEnvironment: Equatable {
    let lowLight: Bool
}

extension CloudAnalyzer {
    func analyze(
        sampleBuffer: CMSampleBuffer,
        fieldOfViewDegrees: Double,
        environment: CloudAnalysisEnvironment
    ) -> CloudFrameAnalysis? {
        analyze(
            sampleBuffer: sampleBuffer,
            fieldOfViewDegrees: fieldOfViewDegrees
        )
    }

    func resetSemanticGate() {
        // The legacy analyzer has no persistent semantic cache/gate state.
    }
}

// Keep the UI on the detailed raw legacy contour for this control build.
// Tracking still runs for IDs/mass estimates, but it cannot rewrite geometry.
extension CloudOverlayStabilizer {
    func update(_ image: CGImage?, detections: [CloudDetection]) -> CGImage? {
        update(image)
    }
}

extension CloudAnalyzerTiming {
    init(
        preprocessingMilliseconds: Double,
        skyInferenceMilliseconds: Double,
        cloudInferenceMilliseconds: Double,
        postprocessingMilliseconds: Double,
        skyCoveragePercent: Double
    ) {
        self.init(
            preprocessingMilliseconds: preprocessingMilliseconds,
            skyInferenceMilliseconds: skyInferenceMilliseconds,
            cloudInferenceMilliseconds: cloudInferenceMilliseconds,
            inferenceWallMilliseconds: skyInferenceMilliseconds + cloudInferenceMilliseconds,
            parallelOverlapMilliseconds: 0,
            postprocessingMilliseconds: postprocessingMilliseconds,
            skyCoveragePercent: skyCoveragePercent,
            strictSkyCoveragePercent: skyCoveragePercent,
            relaxedSkyCoveragePercent: 0,
            semanticBlockerCoveragePercent: 0,
            semanticTreeCoveragePercent: 0,
            semanticBuildingCoveragePercent: 0,
            semanticPersonCoveragePercent: 0,
            semanticPlantCoveragePercent: 0,
            semanticWallCoveragePercent: 0,
            semanticFallbackCoveragePercent: 0,
            skySceneActive: skyCoveragePercent >= 5.0,
            skyGateMode: "legacy_strict_sync",
            inferenceMode: "legacy_synchronous"
        )
    }
}
