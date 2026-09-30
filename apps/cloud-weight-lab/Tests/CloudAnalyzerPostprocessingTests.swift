import XCTest
@testable import CloudWeightLab

final class CloudAnalyzerPostprocessingTests: XCTestCase {
    func testStrictGateRejectsStrongCloudWithoutLocalSkyProof() {
        let mask = CloudAnalyzer.gatedCloudMask(
            cloudProbabilities: [0.95],
            skyProbabilities: [0.20],
            cloudThreshold: 0.52,
            skyThreshold: 0.55
        )

        XCTAssertEqual(mask, [false])
    }

    func testStrictGatePreservesGapInsteadOfWeakSemanticBridge() {
        let mask = CloudAnalyzer.gatedCloudMask(
            cloudProbabilities: [0.80, 0.82, 0.90, 0.81, 0.79],
            skyProbabilities: [0.80, 0.72, 0.30, 0.74, 0.77],
            cloudThreshold: 0.52,
            skyThreshold: 0.55
        )

        XCTAssertEqual(mask, [true, true, false, true, true])
    }

    func testStrictGateKeepsCloudWhenBothModelsAgree() {
        let mask = CloudAnalyzer.gatedCloudMask(
            cloudProbabilities: [0.40, 0.60, 0.91],
            skyProbabilities: [0.90, 0.70, 0.88],
            cloudThreshold: 0.52,
            skyThreshold: 0.55
        )

        XCTAssertEqual(mask, [false, true, true])
    }

    func testStrictGateRejectsMismatchedProbabilityMaps() {
        let mask = CloudAnalyzer.gatedCloudMask(
            cloudProbabilities: [0.80, 0.82],
            skyProbabilities: [0.80],
            cloudThreshold: 0.52,
            skyThreshold: 0.55
        )

        XCTAssertTrue(mask.isEmpty)
    }
}
