import Foundation

struct CloudMassEstimator {
    func estimate(from analysis: CloudFrameAnalysis) -> CloudMassEstimate? {
        guard analysis.coverage > 0.01,
              analysis.bounds.width > 0.03,
              analysis.bounds.height > 0.02 else {
            return nil
        }

        let kind = analysis.kind
        let altitudeMid = midpoint(kind.altitudeMeters)
        let lwcMid = midpoint(kind.waterContentGramsPerCubicMeter)
        let depthMid = midpoint(kind.depthRatio)

        let midGeometry = geometry(
            analysis: analysis,
            altitudeMeters: altitudeMid,
            depthRatio: depthMid
        )
        let lowGeometry = geometry(
            analysis: analysis,
            altitudeMeters: kind.altitudeMeters.lowerBound,
            depthRatio: kind.depthRatio.lowerBound
        )
        let highGeometry = geometry(
            analysis: analysis,
            altitudeMeters: kind.altitudeMeters.upperBound,
            depthRatio: kind.depthRatio.upperBound
        )

        let shapeFactor = 0.42
        let lowMass = lowGeometry.volume * shapeFactor * (kind.waterContentGramsPerCubicMeter.lowerBound / 1_000.0)
        let midMass = midGeometry.volume * shapeFactor * (lwcMid / 1_000.0)
        let highMass = highGeometry.volume * shapeFactor * (kind.waterContentGramsPerCubicMeter.upperBound / 1_000.0)

        return CloudMassEstimate(
            lowKilograms: max(1, lowMass),
            midpointKilograms: max(1, midMass),
            highKilograms: max(lowMass, highMass),
            estimatedWidthMeters: midGeometry.width,
            estimatedHeightMeters: midGeometry.height,
            confidence: (analysis.confidence * 0.70).clamped(0.05...0.85)
        )
    }

    private func geometry(
        analysis: CloudFrameAnalysis,
        altitudeMeters: Double,
        depthRatio: Double
    ) -> (width: Double, height: Double, depth: Double, volume: Double) {
        // A single image cannot recover cloud distance. V1 assumes the user points
        // comfortably above the horizon (~55° elevation) and widens the final range
        // through the cloud-type altitude bounds.
        let assumedElevation = 55.0 * .pi / 180.0
        let lineOfSightDistance = altitudeMeters / sin(assumedElevation)
        let fov = max(35, analysis.fieldOfViewDegrees) * .pi / 180.0
        let angularWidth = max(0.02, fov * analysis.bounds.width)
        let width = max(20, 2 * lineOfSightDistance * tan(angularWidth / 2))

        let aspect = (analysis.bounds.height / max(analysis.bounds.width, 0.01)).clamped(0.15...2.5)
        let height = max(10, width * aspect * 0.72)
        let depth = max(10, width * depthRatio)
        let volume = width * height * depth
        return (width, height, depth, volume)
    }

    private func midpoint(_ range: ClosedRange<Double>) -> Double {
        (range.lowerBound + range.upperBound) / 2
    }
}
