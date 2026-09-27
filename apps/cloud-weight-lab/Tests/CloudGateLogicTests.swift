import XCTest
@testable import CloudWeightLab

final class CloudGateLogicTests: XCTestCase {
    func testIndoorStrongCloudDoesNotOpenFallbackWithoutSkyEvidence() {
        let gate = CloudSemanticGate()
        let count = 100
        let result = gate.makeMask(
            cloudProbabilities: Array(repeating: 0.95, count: count),
            skyProbabilities: Array(repeating: 0.01, count: count),
            blockerProbabilities: Array(repeating: 0.10, count: count),
            classCoverage: .zero,
            lowLight: false
        )
        XCTAssertFalse(result.metrics.skySceneActive)
        XCTAssertEqual(result.mask.filter { $0 }.count, 0)
    }

    func testTwilightFallbackHoldsAfterSkyWasEstablished() {
        let gate = CloudSemanticGate()
        let count = 100
        for _ in 0..<2 {
            _ = gate.makeMask(
                cloudProbabilities: Array(repeating: 0.2, count: count),
                skyProbabilities: Array(repeating: 0.8, count: count),
                blockerProbabilities: Array(repeating: 0.05, count: count),
                classCoverage: .zero,
                lowLight: true
            )
        }
        let twilight = gate.makeMask(
            cloudProbabilities: Array(repeating: 0.80, count: count),
            skyProbabilities: Array(repeating: 0.02, count: count),
            blockerProbabilities: Array(repeating: 0.05, count: count),
            classCoverage: .zero,
            lowLight: true
        )
        XCTAssertTrue(twilight.metrics.skySceneActive)
        XCTAssertGreaterThan(twilight.mask.filter { $0 }.count, 0)
        XCTAssertEqual(twilight.metrics.mode, "hysteresis_hold")
    }

    func testTreeBlockerRejectsEvenWithSkyHistory() {
        let gate = CloudSemanticGate()
        let count = 100
        for _ in 0..<2 {
            _ = gate.makeMask(
                cloudProbabilities: Array(repeating: 0.2, count: count),
                skyProbabilities: Array(repeating: 0.8, count: count),
                blockerProbabilities: Array(repeating: 0.05, count: count),
                classCoverage: .zero,
                lowLight: false
            )
        }
        let blocked = gate.makeMask(
            cloudProbabilities: Array(repeating: 0.95, count: count),
            skyProbabilities: Array(repeating: 0.70, count: count),
            blockerProbabilities: Array(repeating: 0.90, count: count),
            classCoverage: CloudSemanticClassCoverage(
                treePercent: 100,
                buildingPercent: 0,
                personPercent: 0,
                plantPercent: 0,
                wallPercent: 0
            ),
            lowLight: false
        )
        XCTAssertEqual(blocked.mask.filter { $0 }.count, 0)
        XCTAssertGreaterThan(blocked.metrics.treeCoveragePercent, 90)
    }

    func testHysteresisEventuallyExitsSkyScene() {
        let gate = CloudSemanticGate()
        let count = 100
        for _ in 0..<2 {
            _ = gate.makeMask(
                cloudProbabilities: Array(repeating: 0.2, count: count),
                skyProbabilities: Array(repeating: 0.8, count: count),
                blockerProbabilities: Array(repeating: 0.05, count: count),
                classCoverage: .zero,
                lowLight: false
            )
        }
        var last = false
        for _ in 0..<20 {
            let result = gate.makeMask(
                cloudProbabilities: Array(repeating: 0.1, count: count),
                skyProbabilities: Array(repeating: 0.0, count: count),
                blockerProbabilities: Array(repeating: 0.05, count: count),
                classCoverage: .zero,
                lowLight: false
            )
            last = result.metrics.skySceneActive
        }
        XCTAssertFalse(last)
    }
}
