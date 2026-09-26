import XCTest
@testable import CloudWeightLab

final class CloudMassEstimatorTests: XCTestCase {
    private let estimator = CloudMassEstimator()

    func testEstimateKeepsOrderedRange() throws {
        let result = try XCTUnwrap(estimator.estimate(from: analysis(width: 0.30, height: 0.24)))
        XCTAssertLessThan(result.lowKilograms, result.midpointKilograms)
        XCTAssertLessThan(result.midpointKilograms, result.highKilograms)
        XCTAssertGreaterThan(result.estimatedWidthMeters, 0)
    }

    func testLargerAngularCloudProducesMoreMass() throws {
        let small = try XCTUnwrap(estimator.estimate(from: analysis(width: 0.18, height: 0.14)))
        let large = try XCTUnwrap(estimator.estimate(from: analysis(width: 0.46, height: 0.36)))
        XCTAssertGreaterThan(large.midpointKilograms, small.midpointKilograms)
    }

    func testClassifierProfiles() {
        XCTAssertEqual(
            CloudAnalyzer.classify(coverage: 0.30, aspectRatio: 1.2, brightness: 0.75, saturation: 0.18),
            .cumulus
        )
        XCTAssertEqual(
            CloudAnalyzer.classify(coverage: 0.82, aspectRatio: 2.0, brightness: 0.62, saturation: 0.16),
            .stratus
        )
        XCTAssertEqual(
            CloudAnalyzer.classify(coverage: 0.10, aspectRatio: 2.4, brightness: 0.82, saturation: 0.12),
            .cirrus
        )
    }

    private func analysis(width: Double, height: Double) -> CloudFrameAnalysis {
        CloudFrameAnalysis(
            timestamp: Date(),
            kind: .cumulus,
            confidence: 0.82,
            coverage: width * height * 0.72,
            bounds: CGRect(x: 0.3, y: 0.3, width: width, height: height),
            averageBrightness: 0.76,
            averageSaturation: 0.14,
            fieldOfViewDegrees: 64
        )
    }
}
