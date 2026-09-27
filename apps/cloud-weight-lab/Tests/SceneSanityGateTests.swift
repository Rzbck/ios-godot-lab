import XCTest
@testable import CloudWeightLab

final class SceneSanityGateTests: XCTestCase {
    func testAlmostBlackSceneIsRejected() {
        XCTAssertTrue(SceneSanityGate.shouldReject(meanLuminance: 0.01, darkFraction: 0.98))
    }

    func testTwilightIsNotHardRejected() {
        XCTAssertFalse(SceneSanityGate.shouldReject(meanLuminance: 0.07, darkFraction: 0.80))
    }

    func testDarkNightWithUsefulSignalIsStillAllowed() {
        XCTAssertFalse(SceneSanityGate.shouldReject(meanLuminance: 0.04, darkFraction: 0.88))
    }
}
