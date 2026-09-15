import HealthKit
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

    func testWalkingGPSZeroWithoutStillnessCannotPause() {
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

    func testWalkingCanPauseAfterCorroboratedStillness() {
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

    func testFieldFailureStaleWalkingSpeedDoesNotBlockPauseForever() {
        XCTAssertTrue(
            TrackerAutoPauseStabilityPolicy.shouldStagePause(
                activity: .walking,
                enabled: true,
                stationary: true,
                speedMps: 0.6327603595463153,
                speedFresh: false,
                cadenceSPM: 0
            )
        )

        XCTAssertFalse(
            TrackerAutoPauseStabilityPolicy.shouldStagePause(
                activity: .walking,
                enabled: true,
                stationary: true,
                speedMps: 0.6327603595463153,
                speedFresh: true,
                cadenceSPM: 0
            )
        )
    }

    func testCapturedStoppedWatchSampleIsQuietInertialEvidence() {
        XCTAssertTrue(
            TrackerInertialStillnessPolicy.isQuietSample(
                accelX: 0.273895263671875,
                accelY: -0.9208831787109375,
                accelZ: -0.2893218994140625,
                gyroX: 0.0006912361131981015,
                gyroY: -0.008650983683764934,
                gyroZ: 0.0001020010095089674
            )
        )
    }

    func testCapturedWristMovementIsNotQuietInertialEvidence() {
        XCTAssertFalse(
            TrackerInertialStillnessPolicy.isQuietSample(
                accelX: 0.4322967529296875,
                accelY: -0.74371337890625,
                accelZ: -0.3543701171875,
                gyroX: -5.940701007843018,
                gyroY: -0.2054058462381363,
                gyroZ: 0.17864996194839478
            )
        )
    }

    func testInertialFallbackRequiresAWindowNotOneQuietSample() {
        XCTAssertFalse(
            TrackerInertialStillnessPolicy.isStill(
                windowCoverage: 1.8,
                quietSamples: 10,
                totalSamples: 10
            )
        )
        XCTAssertTrue(
            TrackerInertialStillnessPolicy.isStill(
                windowCoverage: 2.6,
                quietSamples: 12,
                totalSamples: 14
            )
        )
        XCTAssertFalse(
            TrackerInertialStillnessPolicy.isStill(
                windowCoverage: 2.6,
                quietSamples: 8,
                totalSamples: 14
            )
        )
    }

    func testAutomaticHealthKitPlaceholderIsWalkingNotMixedCardio() {
        XCTAssertEqual(ActivityKind.automatic.healthKitType, HKWorkoutActivityType.walking)
        XCTAssertNotEqual(ActivityKind.automatic.healthKitType, HKWorkoutActivityType.mixedCardio)
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

    func testCyclingRequiresStillnessAsWellAsLowSpeed() {
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

    func testPauseEvidenceWindowsOutliveWalkingDwellButSpeedExpiresQuickly() {
        XCTAssertEqual(TrackerAutoPauseStabilityPolicy.pauseDwell(for: .walking), 6.0)
        XCTAssertEqual(TrackerAutoPauseStabilityPolicy.stationaryEvidenceFreshness(for: .walking), 12.0)
        XCTAssertEqual(TrackerAutoPauseStabilityPolicy.speedEvidenceFreshness(for: .walking), 4.0)
        XCTAssertGreaterThan(
            TrackerAutoPauseStabilityPolicy.stationaryEvidenceFreshness(for: .walking),
            TrackerAutoPauseStabilityPolicy.pauseDwell(for: .walking)
        )
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
