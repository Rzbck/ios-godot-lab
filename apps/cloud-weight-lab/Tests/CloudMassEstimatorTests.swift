import XCTest
@testable import CloudWeightLab

final class CloudMassEstimatorTests: XCTestCase {
    private let estimator = CloudMassEstimator()

    func testEstimateKeepsOrderedRange() throws {
        let result = try XCTUnwrap(
            estimator.estimate(
                from: observation(width: 0.30, height: 0.24),
                cameraElevationDegrees: 55,
                isLandscape: true,
                motionReliable: true
            )
        )
        XCTAssertLessThan(result.lowKilograms, result.midpointKilograms)
        XCTAssertLessThan(result.midpointKilograms, result.highKilograms)
        XCTAssertGreaterThan(result.estimatedWidthMeters, 0)
        XCTAssertGreaterThan(result.estimatedDistanceMeters, 0)
        XCTAssertGreaterThan(result.angularWidthDegrees, 0)
    }

    func testLargerAngularCloudProducesMoreMass() throws {
        let small = try XCTUnwrap(
            estimator.estimate(
                from: observation(width: 0.18, height: 0.14),
                cameraElevationDegrees: 55,
                isLandscape: true,
                motionReliable: true
            )
        )
        let large = try XCTUnwrap(
            estimator.estimate(
                from: observation(width: 0.46, height: 0.36),
                cameraElevationDegrees: 55,
                isLandscape: true,
                motionReliable: true
            )
        )
        XCTAssertGreaterThan(large.midpointKilograms, small.midpointKilograms)
    }

    func testLowerElevationMeansGreaterDistanceAndMass() throws {
        let cloud = observation(width: 0.28, height: 0.20)
        let high = try XCTUnwrap(
            estimator.estimate(
                from: cloud,
                cameraElevationDegrees: 70,
                isLandscape: true,
                motionReliable: true
            )
        )
        let low = try XCTUnwrap(
            estimator.estimate(
                from: cloud,
                cameraElevationDegrees: 20,
                isLandscape: true,
                motionReliable: true
            )
        )
        XCTAssertGreaterThan(low.estimatedDistanceMeters, high.estimatedDistanceMeters)
        XCTAssertGreaterThan(low.midpointKilograms, high.midpointKilograms)
        XCTAssertLessThan(low.confidence, high.confidence)
    }

    func testClassifierProfiles() {
        XCTAssertEqual(
            CloudAnalyzer.classify(
                coverage: 0.20,
                aspectRatio: 1.2,
                brightness: 0.75,
                saturation: 0.18
            ),
            .cumulus
        )
        XCTAssertEqual(
            CloudAnalyzer.classify(
                coverage: 0.82,
                aspectRatio: 2.0,
                brightness: 0.62,
                saturation: 0.16
            ),
            .stratus
        )
        XCTAssertEqual(
            CloudAnalyzer.classify(
                coverage: 0.08,
                aspectRatio: 2.4,
                brightness: 0.82,
                saturation: 0.12
            ),
            .cirrus
        )
    }

    func testSkyGateRejectsCloudProbabilityOutsideSky() {
        let result = CloudAnalyzer.gatedCloudMask(
            cloudProbabilities: [0.90, 0.90, 0.20, 0.80],
            skyProbabilities: [0.90, 0.10, 0.90, 0.54],
            cloudThreshold: 0.52,
            skyThreshold: 0.55
        )
        XCTAssertEqual(result, [true, false, false, false])
    }

    func testSkyGateRejectsMismatchedMaps() {
        let result = CloudAnalyzer.gatedCloudMask(
            cloudProbabilities: [0.90, 0.90],
            skyProbabilities: [0.90],
            cloudThreshold: 0.52,
            skyThreshold: 0.55
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testSkyProbabilityResamplingKeepsNormalizedRegions() {
        let source = [
            1.0, 0.0,
            0.0, 1.0
        ]
        let result = CloudAnalyzer.resampleProbabilityMap(
            source,
            sourceWidth: 2,
            sourceHeight: 2,
            targetWidth: 4,
            targetHeight: 4
        )
        XCTAssertEqual(result.count, 16)
        XCTAssertEqual(result[0], 1.0)
        XCTAssertEqual(result[3], 0.0)
        XCTAssertEqual(result[12], 0.0)
        XCTAssertEqual(result[15], 1.0)
    }

    private func observation(width: Double, height: Double) -> CloudObservation {
        CloudObservation(
            id: 0,
            kind: .cumulus,
            confidence: 0.86,
            coverage: width * height * 0.72,
            bounds: CGRect(x: 0.3, y: 0.3, width: width, height: height),
            centroid: CGPoint(x: 0.45, y: 0.42),
            averageBrightness: 0.76,
            averageSaturation: 0.14,
            fieldOfViewDegrees: 64
        )
    }
}
