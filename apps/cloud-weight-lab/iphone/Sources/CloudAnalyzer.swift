// Kept as the stable project-facing type name. The implementation now lives
// in AdaptiveCloudAnalyzer.swift so the adaptive probability/topology pipeline
// can evolve without changing CameraService or the diagnostics API surface.
typealias CloudAnalyzer = AdaptiveCloudAnalyzer
