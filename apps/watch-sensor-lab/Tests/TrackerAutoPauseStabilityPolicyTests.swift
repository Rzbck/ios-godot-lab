import XCTest

final class TrackerAutoPauseStabilityPolicyTests: XCTestCase {
    func testFieldFailureWalkingCadenceVetoesPauseEvenWhenGPSIsZero() {
        XCTAssertFalse(
            TrackerAutoPauseStabilityPolicy.shouldStagePause(
                activity: .walking,
                enabled: true,
                stationary: true,
                speedMps: 0,
                cadenceSPM: 103.7
            )
        )
    }

    func testWalkingGPSZeroWithoutStationaryMotionCannotPause() {
        XCTAssertFalse(
            TrackerAutoPauseStabilityPolicy.shouldStagePause(
                activity: .walking,
                enabled: true,
                stationary: false,
                speedMps: 0,
                cadenceSPM: 0
            )
        )
    }

    func testWalkingCanPauseAfterRealStationaryEvidence() {
        XCTAssertTrue(
            TrackerAutoPauseStabilityPolicy.shouldStagePause(
                activity: .walking,
                enabled: true,
                stationary: true,
                speedMps: 0.05,
                cadenceSPM: 0
            )
        )
    }

    func testRunningCadenceVetoesFalsePause() {
        XCTAssertFalse(
            TrackerAutoPauseStabilityPolicy.shouldStagePause(
                activity: .running,
                enabled: true,
                stationary: true,
                speedMps: 0,
                cadenceSPM: 150
            )
        )
    }

    func testCyclingRequiresStationaryMotionAsWellAsLowSpeed() {
        XCTAssertFalse(
            TrackerAutoPauseStabilityPolicy.shouldStagePause(
                activity: .cycling,
                enabled: true,
                stationary: false,
                speedMps: 0,
                cadenceSPM: 0
            )
        )
        XCTAssertTrue(
            TrackerAutoPauseStabilityPolicy.shouldStagePause(
                activity: .cycling,
                enabled: true,
                stationary: true,
                speedMps: 0.1,
                cadenceSPM: 0
            )
        )
    }

    func testAutomaticPlaceholderAndGenericSportsFailClosed() {
        for activity in [ActivityKind.automatic, .soccer, .yoga, .other] {
            XCTAssertFalse(TrackerAutoPauseStabilityPolicy.supports(activity))
            XCTAssertFalse(
                TrackerAutoPauseStabilityPolicy.shouldStagePause(
                    activity: activity,
                    enabled: true,
                    stationary: true,
                    speedMps: 0,
                    cadenceSPM: 0
                )
            )
        }
    }

    func testPauseIsSlowerThanResumeAndHasPostResumeHysteresis() {
        XCTAssertEqual(TrackerAutoPauseStabilityPolicy.pauseDwell(for: .walking), 6.0)
        XCTAssertEqual(TrackerAutoPauseStabilityPolicy.resumeDwell(for: .walking), 1.0)
        XCTAssertEqual(TrackerAutoPauseStabilityPolicy.repauseCooldown(for: .walking), 10.0)
        XCTAssertGreaterThan(
            TrackerAutoPauseStabilityPolicy.pauseDwell(for: .walking),
            TrackerAutoPauseStabilityPolicy.resumeDwell(for: .walking)
        )
    }
}
