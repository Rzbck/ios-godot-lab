import XCTest
@testable import CloudWeightLab

final class CloudAnalyzerPostprocessingTests: XCTestCase {
    func testDenseTexturedFieldIsEligibleForTopologySplit() {
        XCTAssertTrue(
            CloudAnalyzer.shouldSplitDenseComponent(
                coverage: 0.67,
                probabilityStdDev: 0.09
            )
        )
    }

    func testUniformDenseLayerIsNotForcedIntoArtificialPatches() {
        XCTAssertFalse(
            CloudAnalyzer.shouldSplitDenseComponent(
                coverage: 0.82,
                probabilityStdDev: 0.025
            )
        )
    }

    func testFrameSpanningTexturedLayerGetsTopologyProbe() {
        XCTAssertTrue(
            CloudAnalyzer.shouldProbeTopology(
                coverage: 0.82,
                probabilityStdDev: 0.035
            )
        )
    }

    func testUniformBroadLayerDoesNotGetTopologyProbe() {
        XCTAssertFalse(
            CloudAnalyzer.shouldProbeTopology(
                coverage: 0.82,
                probabilityStdDev: 0.025
            )
        )
    }

    func testTopologySeedThresholdsStartAboveLegacyThreshold() {
        let thresholds = CloudAnalyzer.topologySeedThresholds(
            meanProbability: 0.68,
            probabilityStdDev: 0.09
        )

        XCTAssertGreaterThanOrEqual(thresholds.count, 2)
        XCTAssertGreaterThan(
            thresholds[0],
            thresholds[thresholds.count - 1]
        )
        XCTAssertGreaterThanOrEqual(
            thresholds[thresholds.count - 1],
            0.58
        )
    }

    func testBroadCloudFieldCannotBeClassifiedAsCumulus() {
        let kind = CloudAnalyzer.classify(
            coverage: 0.67,
            aspectRatio: 1.15,
            brightness: 0.72,
            saturation: 0.12,
            fill: 0.88,
            probabilityStdDev: 0.08,
            brightnessStdDev: 0.13
        )
        XCTAssertEqual(kind, .stratocumulus)
    }

    func testUniformBroadLayerClassifiesAsStratus() {
        let kind = CloudAnalyzer.classify(
            coverage: 0.78,
            aspectRatio: 1.3,
            brightness: 0.68,
            saturation: 0.10,
            fill: 0.91,
            probabilityStdDev: 0.02,
            brightnessStdDev: 0.04
        )
        XCTAssertEqual(kind, .stratus)
    }
}
