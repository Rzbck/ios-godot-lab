import Foundation

struct CloudMassEstimator {
    func estimate(from observation: CloudObservation) -> CloudMassEstimate? {
        guard observation.coverage > 0.002,
              observation.bounds.width > 0.015,
              observation.bounds.height > 0.015 else {
            return nil
        }

        let kind = observation.kind
        let altitudeMid = midpoint(kind.altitudeMeters)
        let lwcMid = midpoint(kind.waterContentGramsPerCubicMeter)
        let depthMid = midpoint(kind.depthRatio)

        let midGeometry = geometry(
            observation: observation,
            altitudeMeters: altitudeMid,
            depthRatio: depthMid
        )
        let lowGeometry = geometry(
            observation: observation,
            altitudeMeters: kind.altitudeMeters.lowerBound,
            depthRatio: kind.depthRatio.lowerBound
        )
        let highGeometry = geometry(
            observation: observation,
            altitudeMeters: kind.altitudeMeters.upperBound,
            depthRatio: kind.depthRatio.upperBound
        )

        let projectedFill = (observation.coverage / max(
            observation.bounds.width * observation.bounds.height,
            0.0001
        )).clamped(0.12...1.0)
        let shapeFactor = 0.30 + projectedFill * 0.28

        let lowMass = lowGeometry.volume * shapeFactor
            * (kind.waterContentGramsPerCubicMeter.lowerBound / 1_000.0)
        let midMass = midGeometry.volume * shapeFactor
            * (lwcMid / 1_000.0)
        let highMass = highGeometry.volume * shapeFactor
            * (kind.waterContentGramsPerCubicMeter.upperBound / 1_000.0)

        return CloudMassEstimate(
            lowKilograms: max(1, lowMass),
            midpointKilograms: max(1, midMass),
            highKilograms: max(midMass, highMass),
            estimatedWidthMeters: midGeometry.width,
            estimatedHeightMeters: midGeometry.height,
            confidence: (observation.confidence * 0.74).clamped(0.05...0.88)
        )
    }

    private func geometry(
        observation: CloudObservation,
        altitudeMeters: Double,
        depthRatio: Double
    ) -> (width: Double, height: Double, depth: Double, volume: Double) {
        let assumedElevation = 55.0 * .pi / 180.0
        let lineOfSightDistance = altitudeMeters / sin(assumedElevation)
        let fov = max(35, observation.fieldOfViewDegrees) * .pi / 180.0
        let angularWidth = max(0.01, fov * observation.bounds.width)
        let width = max(12, 2 * lineOfSightDistance * tan(angularWidth / 2))

        let aspect = (
            observation.bounds.height / max(observation.bounds.width, 0.01)
        ).clamped(0.10...3.0)
        let height = max(8, width * aspect * 0.72)
        let depth = max(8, width * depthRatio)
        let volume = width * height * depth
        return (width, height, depth, volume)
    }

    private func midpoint(_ range: ClosedRange<Double>) -> Double {
        (range.lowerBound + range.upperBound) / 2
    }
}
