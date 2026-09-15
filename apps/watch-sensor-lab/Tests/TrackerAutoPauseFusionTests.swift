import XCTest

final class TrackerAutoPauseFusionTests: XCTestCase {
    func testAdaptivePauseCanArmAtStartupFromGoodGPSWithoutPriorMovement() {
        XCTAssertTrue(
            TrackerAutoPolicy.canArmAdaptivePause(
                horizontalAccuracy: 6,
                motionEvidenceObserved: false
            )
        )
    }

    func testAdaptivePauseCanArmAtStartupFromStationaryMotionWithoutGPS() {
        XCTAssertTrue(
            TrackerAutoPolicy.canArmAdaptivePause(
                horizontalAccuracy: -1,
                motionEvidenceObserved: true
            )
        )
    }

    func testAdaptivePauseDoesNotArmBeforeAnyRealSensorEvidence() {
        XCTAssertFalse(
            TrackerAutoPolicy.canArmAdaptivePause(
                horizontalAccuracy: -1,
                motionEvidenceObserved: false
            )
        )
    }

    func testFieldFailureStaleCadenceCannotResumeWalking() {
        let decision = TrackerAutoPolicy.resumeDecision(
            activity: .walking,
            enabled: true,
            evidence: TrackerAutoResumeEvidence(
                speedMps: 0,
                gpsFresh: false,
                gpsReliable: false,
                gpsSustained: false,
                cadenceSPM: 113.32170724868774,
                cadenceFresh: false,
                stationary: true,
                motionCandidate: nil,
                motionFresh: true
            )
        )

        XCTAssertFalse(decision.shouldResume)
        XCTAssertEqual(decision.reason, "stale_cadence_rejected")
    }

    func testIsolatedWalkingMotionCallbackCannotResumeStoppedWorkout() {
        let decision = TrackerAutoPolicy.resumeDecision(
            activity: .walking,
            enabled: true,
            evidence: TrackerAutoResumeEvidence(
                speedMps: 0,
                gpsFresh: false,
                gpsReliable: false,
                gpsSustained: false,
                cadenceSPM: 0,
                cadenceFresh: false,
                stationary: false,
                motionCandidate: .walking,
                motionFresh: true
            )
        )

        XCTAssertFalse(decision.shouldResume)
        XCTAssertEqual(decision.reason, "motion_only_rejected")
    }

    func testFreshCadenceAndMotionConsensusResumesWalkingWithoutGPS() {
        let decision = TrackerAutoPolicy.resumeDecision(
            activity: .walking,
            enabled: true,
            evidence: TrackerAutoResumeEvidence(
                speedMps: 0,
                gpsFresh: false,
                gpsReliable: false,
                gpsSustained: false,
                cadenceSPM: 92,
                cadenceFresh: true,
                stationary: false,
                motionCandidate: .walking,
                motionFresh: true
            )
        )

        XCTAssertTrue(decision.shouldResume)
        XCTAssertEqual(decision.reason, "cadence_motion_consensus")
        XCTAssertEqual(decision.agreeingEvidenceCount, 2)
    }

    func testSingleGoodGPSSampleCannotResumeWalking() {
        let decision = TrackerAutoPolicy.resumeDecision(
            activity: .walking,
            enabled: true,
            evidence: TrackerAutoResumeEvidence(
                speedMps: 1.4,
                gpsFresh: true,
                gpsReliable: true,
                gpsSustained: false,
                cadenceSPM: 0,
                cadenceFresh: false,
                stationary: false,
                motionCandidate: nil,
                motionFresh: false
            )
        )

        XCTAssertFalse(decision.shouldResume)
        XCTAssertEqual(decision.reason, "single_gps_sample_rejected")
    }

    func testSustainedReliableGPSCanResumeWalkingWithoutMotionClassifier() {
        let decision = TrackerAutoPolicy.resumeDecision(
            activity: .walking,
            enabled: true,
            evidence: TrackerAutoResumeEvidence(
                speedMps: 1.2,
                gpsFresh: true,
                gpsReliable: true,
                gpsSustained: true,
                cadenceSPM: 0,
                cadenceFresh: false,
                stationary: false,
                motionCandidate: nil,
                motionFresh: false
            )
        )

        XCTAssertTrue(decision.shouldResume)
        XCTAssertEqual(decision.reason, "strong_sustained_gps")
    }

    func testFreshWalkingCadenceCanResumeWithoutGPSOrMotionClassifier() {
        let decision = TrackerAutoPolicy.resumeDecision(
            activity: .walking,
            enabled: true,
            evidence: TrackerAutoResumeEvidence(
                speedMps: 0,
                gpsFresh: false,
                gpsReliable: false,
                gpsSustained: false,
                cadenceSPM: 99,
                cadenceFresh: true,
                stationary: false,
                motionCandidate: nil,
                motionFresh: false
            )
        )

        XCTAssertTrue(decision.shouldResume)
        XCTAssertEqual(decision.reason, "strong_fresh_cadence")
    }

    func testUnreliableGPSCannotResumeEvenAtCyclingSpeed() {
        let decision = TrackerAutoPolicy.resumeDecision(
            activity: .cycling,
            enabled: true,
            evidence: TrackerAutoResumeEvidence(
                speedMps: 6,
                gpsFresh: true,
                gpsReliable: false,
                gpsSustained: true,
                cadenceSPM: 0,
                cadenceFresh: false,
                stationary: false,
                motionCandidate: nil,
                motionFresh: false
            )
        )

        XCTAssertFalse(decision.shouldResume)
        XCTAssertEqual(decision.reason, "unreliable_gps_rejected")
    }

    func testStrongSustainedCyclingGPSCanOverrideStaleStationaryMotion() {
        let decision = TrackerAutoPolicy.resumeDecision(
            activity: .cycling,
            enabled: true,
            evidence: TrackerAutoResumeEvidence(
                speedMps: 3.2,
                gpsFresh: true,
                gpsReliable: true,
                gpsSustained: true,
                cadenceSPM: 0,
                cadenceFresh: false,
                stationary: true,
                motionCandidate: nil,
                motionFresh: true
            )
        )

        XCTAssertTrue(decision.shouldResume)
        XCTAssertEqual(decision.reason, "strong_sustained_gps")
    }

    func testProbeRejectsNativeSpeedWhenSpeedAccuracyIsTooPoor() {
        var probe = TrackerAutoResumeProbe()

        let speed = probe.observe(
            sampleTimestamp: 100,
            now: 100,
            horizontalAccuracy: 5,
            nativeSpeedMps: 1.2,
            speedAccuracyMps: 2.0,
            derivedSpeedMps: 1.2,
            plausibleMaxSpeedMps: 8
        )

        XCTAssertNil(speed)
        XCTAssertFalse(probe.lastSampleReliable)
        XCTAssertFalse(probe.hasSustainedMovement(now: 100))
    }

    func testProbeRequiresTwoReliableNativeMovementSamples() {
        var probe = TrackerAutoResumeProbe()

        XCTAssertNotNil(
            probe.observe(
                sampleTimestamp: 100,
                now: 100,
                horizontalAccuracy: 5,
                nativeSpeedMps: 1.2,
                speedAccuracyMps: 0.25,
                derivedSpeedMps: 1.1,
                plausibleMaxSpeedMps: 8
            )
        )
        XCTAssertFalse(probe.hasSustainedMovement(now: 100))

        XCTAssertNotNil(
            probe.observe(
                sampleTimestamp: 101,
                now: 101,
                horizontalAccuracy: 5,
                nativeSpeedMps: 1.3,
                speedAccuracyMps: 0.25,
                derivedSpeedMps: 1.2,
                plausibleMaxSpeedMps: 8
            )
        )
        XCTAssertTrue(probe.hasSustainedMovement(now: 101))
    }

    func testDerivedGPSMovementRequiresThreeExcellentAccuracySamples() {
        var probe = TrackerAutoResumeProbe()

        for timestamp in [100.0, 101.0] {
            XCTAssertNotNil(
                probe.observe(
                    sampleTimestamp: timestamp,
                    now: timestamp,
                    horizontalAccuracy: 6,
                    nativeSpeedMps: -1,
                    speedAccuracyMps: -1,
                    derivedSpeedMps: 1.1,
                    plausibleMaxSpeedMps: 8
                )
            )
        }
        XCTAssertFalse(probe.hasSustainedMovement(now: 101))

        XCTAssertNotNil(
            probe.observe(
                sampleTimestamp: 102,
                now: 102,
                horizontalAccuracy: 6,
                nativeSpeedMps: -1,
                speedAccuracyMps: -1,
                derivedSpeedMps: 1.2,
                plausibleMaxSpeedMps: 8
            )
        )
        XCTAssertTrue(probe.hasSustainedMovement(now: 102))
    }

    func testPoorHorizontalAccuracyNeverBecomesResumeEvidence() {
        var probe = TrackerAutoResumeProbe()

        XCTAssertNil(
            probe.observe(
                sampleTimestamp: 100,
                now: 100,
                horizontalAccuracy: 32,
                nativeSpeedMps: 4,
                speedAccuracyMps: 0.2,
                derivedSpeedMps: 4,
                plausibleMaxSpeedMps: 28
            )
        )
        XCTAssertFalse(probe.isFresh(now: 100))
        XCTAssertEqual(probe.recentSpeedMps(now: 100), 0)
    }
}
