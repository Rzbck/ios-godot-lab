import CoreMotion
import Foundation
import UIKit

final class CloudMassEstimator {
    private struct MotionState {
        let cameraElevationDegrees: Double
        let isLandscape: Bool
        let reliable: Bool
    }

    private let motionManager = CMMotionManager()
    private let motionQueue = OperationQueue()
    private let stateLock = NSLock()
    private var smoothedCameraElevationDegrees: Double?
    private var outputIsLandscape: Bool
    private var motionReliable = false

    init() {
        switch UIDevice.current.orientation {
        case .landscapeLeft, .landscapeRight:
            outputIsLandscape = true
        case .portrait, .portraitUpsideDown:
            outputIsLandscape = false
        default:
            outputIsLandscape = UIScreen.main.bounds.width > UIScreen.main.bounds.height
        }

        motionQueue.name = "cloudweight.mass-geometry-motion"
        motionQueue.qualityOfService = .userInitiated
        motionQueue.maxConcurrentOperationCount = 1

        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let gravity = motion.gravity

            // For the back camera the optical axis is approximately -Z. Since
            // CMGravity points down, asin(gravity.z) gives camera elevation:
            // 0° at horizon, +90° when the back camera points at zenith.
            let z = min(max(gravity.z, -1.0), 1.0)
            let measuredElevation = asin(z) * 180.0 / .pi

            let absX = abs(gravity.x)
            let absY = abs(gravity.y)
            let landscapeCandidate: Bool?
            if absX > absY + 0.12 {
                landscapeCandidate = true
            } else if absY > absX + 0.12 {
                landscapeCandidate = false
            } else {
                landscapeCandidate = nil
            }

            self.stateLock.lock()
            if let previous = self.smoothedCameraElevationDegrees {
                self.smoothedCameraElevationDegrees = previous + (measuredElevation - previous) * 0.22
            } else {
                self.smoothedCameraElevationDegrees = measuredElevation
            }
            if let landscapeCandidate {
                self.outputIsLandscape = landscapeCandidate
            }
            self.motionReliable = true
            self.stateLock.unlock()
        }
    }

    deinit {
        motionManager.stopDeviceMotionUpdates()
    }

    func estimate(from observation: CloudObservation) -> CloudMassEstimate? {
        let state = currentMotionState()
        return estimate(
            from: observation,
            cameraElevationDegrees: state.cameraElevationDegrees,
            isLandscape: state.isLandscape,
            motionReliable: state.reliable
        )
    }

    func estimate(
        from observation: CloudObservation,
        cameraElevationDegrees: Double,
        isLandscape: Bool,
        motionReliable: Bool
    ) -> CloudMassEstimate? {
        guard observation.coverage > 0.002,
              observation.bounds.width > 0.015,
              observation.bounds.height > 0.015 else {
            return nil
        }

        let kind = observation.kind
        let sensorHorizontalFOV = max(20.0, observation.fieldOfViewDegrees) * .pi / 180.0
        let captureAspect = 16.0 / 9.0
        let sensorVerticalFOV = 2.0 * atan(tan(sensorHorizontalFOV / 2.0) / captureAspect)
        let horizontalFOV = isLandscape ? sensorHorizontalFOV : sensorVerticalFOV
        let verticalFOV = isLandscape ? sensorVerticalFOV : sensorHorizontalFOV

        let left = horizontalAngle(normalized: Double(observation.bounds.minX), fov: horizontalFOV)
        let right = horizontalAngle(normalized: Double(observation.bounds.maxX), fov: horizontalFOV)
        let top = verticalAngle(normalized: Double(observation.bounds.minY), fov: verticalFOV)
        let bottom = verticalAngle(normalized: Double(observation.bounds.maxY), fov: verticalFOV)
        let centerVerticalOffset = verticalAngle(
            normalized: Double(observation.centroid.y),
            fov: verticalFOV
        )

        let angularWidth = max(0.001, abs(right - left))
        let angularHeight = max(0.001, abs(top - bottom))
        let centerElevationDegrees = cameraElevationDegrees + centerVerticalOffset * 180.0 / .pi

        let altitudeMid = geometricMean(kind.altitudeMeters)
        let waterMid = geometricMean(kind.waterContentGramsPerCubicMeter)
        let depthMid = geometricMean(kind.depthRatio)

        let angleUncertainty = motionReliable ? 2.5 : 15.0
        let midElevation = centerElevationDegrees.clamped(3.0...89.0)
        let nearElevation = (centerElevationDegrees + angleUncertainty).clamped(3.0...89.0)
        let farElevation = (centerElevationDegrees - angleUncertainty).clamped(3.0...89.0)

        let lowDistance = distance(
            altitudeMeters: kind.altitudeMeters.lowerBound,
            elevationDegrees: nearElevation
        )
        let midDistance = distance(
            altitudeMeters: altitudeMid,
            elevationDegrees: midElevation
        )
        let highDistance = distance(
            altitudeMeters: kind.altitudeMeters.upperBound,
            elevationDegrees: farElevation
        )

        let boundsArea = max(Double(observation.bounds.width * observation.bounds.height), 0.0001)
        let projectedFill = (observation.coverage / boundsArea).clamped(0.05...1.0)

        let lowGeometry = geometry(
            distanceMeters: lowDistance,
            angularWidth: angularWidth,
            angularHeight: angularHeight,
            fill: projectedFill,
            depthRatio: kind.depthRatio.lowerBound
        )
        let midGeometry = geometry(
            distanceMeters: midDistance,
            angularWidth: angularWidth,
            angularHeight: angularHeight,
            fill: projectedFill,
            depthRatio: depthMid
        )
        let highGeometry = geometry(
            distanceMeters: highDistance,
            angularWidth: angularWidth,
            angularHeight: angularHeight,
            fill: projectedFill,
            depthRatio: kind.depthRatio.upperBound
        )

        let lowMassRaw = lowGeometry.volume
            * (kind.waterContentGramsPerCubicMeter.lowerBound / 1_000.0)
        let midMassRaw = midGeometry.volume * (waterMid / 1_000.0)
        let highMassRaw = highGeometry.volume
            * (kind.waterContentGramsPerCubicMeter.upperBound / 1_000.0)

        let midMass = max(1.0, midMassRaw)
        let lowMass = max(1.0, min(lowMassRaw, midMass * 0.98))
        let highMass = max(midMass * 1.02, highMassRaw)

        let elevationQuality = ((centerElevationDegrees - 2.0) / 28.0).clamped(0.25...1.0)
        let motionQuality = motionReliable ? 1.0 : 0.58
        let kindQuality = kind == .unknown ? 0.58 : 0.86
        let fillQuality = (0.65 + 0.35 * sqrt(projectedFill)).clamped(0.65...1.0)
        let uncertaintyRatio = max(1.0, highMass / max(1.0, lowMass))
        let uncertaintyQuality = (1.0 / (1.0 + 0.16 * log(uncertaintyRatio))).clamped(0.35...1.0)
        let confidence = (
            observation.confidence
                * elevationQuality
                * motionQuality
                * kindQuality
                * fillQuality
                * uncertaintyQuality
        ).clamped(0.04...0.90)

        return CloudMassEstimate(
            lowKilograms: lowMass,
            midpointKilograms: midMass,
            highKilograms: highMass,
            estimatedWidthMeters: midGeometry.width,
            estimatedHeightMeters: midGeometry.height,
            estimatedDepthMeters: midGeometry.depth,
            estimatedDistanceMeters: midDistance,
            projectedAreaSquareMeters: midGeometry.projectedArea,
            estimatedVolumeCubicMeters: midGeometry.volume,
            angularWidthDegrees: angularWidth * 180.0 / .pi,
            angularHeightDegrees: angularHeight * 180.0 / .pi,
            centerElevationDegrees: centerElevationDegrees,
            confidence: confidence
        )
    }

    private func currentMotionState() -> MotionState {
        stateLock.lock()
        let elevation = smoothedCameraElevationDegrees
        let landscape = outputIsLandscape
        let reliable = motionReliable
        stateLock.unlock()

        return MotionState(
            cameraElevationDegrees: elevation ?? 55.0,
            isLandscape: landscape,
            reliable: reliable
        )
    }

    private func horizontalAngle(normalized: Double, fov: Double) -> Double {
        atan((normalized * 2.0 - 1.0) * tan(fov / 2.0))
    }

    private func verticalAngle(normalized: Double, fov: Double) -> Double {
        atan((1.0 - normalized * 2.0) * tan(fov / 2.0))
    }

    private func distance(altitudeMeters: Double, elevationDegrees: Double) -> Double {
        let elevation = elevationDegrees.clamped(3.0...89.0) * .pi / 180.0
        return min(150_000.0, max(10.0, altitudeMeters / sin(elevation)))
    }

    private func geometry(
        distanceMeters: Double,
        angularWidth: Double,
        angularHeight: Double,
        fill: Double,
        depthRatio: Double
    ) -> (
        width: Double,
        height: Double,
        depth: Double,
        projectedArea: Double,
        volume: Double
    ) {
        let width = max(5.0, 2.0 * distanceMeters * tan(angularWidth / 2.0))
        let height = max(5.0, 2.0 * distanceMeters * tan(angularHeight / 2.0))
        let projectedArea = max(25.0, width * height * fill)
        let characteristicLength = sqrt(projectedArea)
        let depth = max(5.0, characteristicLength * depthRatio)
        let volume = projectedArea * depth
        return (width, height, depth, projectedArea, volume)
    }

    private func geometricMean(_ range: ClosedRange<Double>) -> Double {
        sqrt(max(0.000_001, range.lowerBound) * max(0.000_001, range.upperBound))
    }
}
