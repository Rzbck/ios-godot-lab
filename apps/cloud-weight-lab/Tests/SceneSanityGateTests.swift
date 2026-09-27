import XCTest
@testable import CloudWeightLab

final class SceneSanityGateTests: XCTestCase {
    func testRejectsNearlyBlackScene() {
        XCTAssertTrue(
            SceneSanityGate.shouldReject(
                meanLuminance: 0.04,
                darkFraction: 0.90
            )
        )
    }

    func testKeepsDimButUsableScene() {
        XCTAssertFalse(
            SceneSanityGate.shouldReject(
                meanLuminance: 0.16,
                darkFraction: 0.76
            )
        )
    }

    func testKeepsBrightScene() {
        XCTAssertFalse(
            SceneSanityGate.shouldReject(
                meanLuminance: 0.48,
                darkFraction: 0.08
            )
        )
    }
}
