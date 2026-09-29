import AVFoundation
import CoreGraphics
import Foundation

// Compatibility only: the analyzer core is the exact V8/V11 implementation.
// These adapters let it run inside the current V12 telemetry/lifecycle shell
// without changing its segmentation geometry.
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
        // The legacy analyzer has no persistent semantic-gate state to reset.
    }
}

// CameraService still passes stabilized detections to the overlay API. The V8
// display intentionally ignores them: detailed raw cloud contours stay visible
// even while a small/new physical track is still being confirmed.
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
            relaxedSkyCoveragePercent: skyCoveragePercent,
            semanticBlockerCoveragePercent: 0,
            semanticTreeCoveragePercent: 0,
            semanticBuildingCoveragePercent: 0,
            semanticPersonCoveragePercent: 0,
            semanticPlantCoveragePercent: 0,
            semanticWallCoveragePercent: 0,
            semanticFallbackCoveragePercent: 0,
            skySceneActive: skyCoveragePercent >= 5.0,
            skyGateMode: "legacy_skywater_strict",
            inferenceMode: "legacy_synchronous"
        )
    }
}
