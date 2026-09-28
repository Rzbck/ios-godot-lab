// Kept as the stable project-facing type name. The implementation now lives
// in AdaptiveCloudAnalyzer.swift so the adaptive probability/topology pipeline
// can evolve without changing CameraService or the diagnostics API surface.
typealias CloudAnalyzer = AdaptiveCloudAnalyzer

extension AdaptiveCloudAnalyzer {
    // Compatibility profile kept for the pre-adaptive regression tests and
    // callers that still exercise the historical four-feature classifier.
    // The live analyzer no longer uses this path: runtime classification is
    // performed by CloudStructureAnalyzer from probability topology, texture,
    // shape and region statistics.
    static func classify(
        coverage: Double,
        aspectRatio: Double,
        brightness: Double,
        saturation: Double
    ) -> CloudKind {
        if coverage > 0.72 {
            return .stratus
        }
        if coverage < 0.12
            && aspectRatio > 2.0
            && brightness > 0.66
            && saturation < 0.25 {
            return .cirrus
        }
        if coverage < 0.30 && aspectRatio < 1.9 {
            return .cumulus
        }
        if coverage < 0.72 {
            return .stratocumulus
        }
        return .unknown
    }
}
