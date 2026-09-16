import XCTest

final class TrackerAutoPolicyTests: XCTestCase {
    func testLowConfidenceEvidenceIsIgnored() {
        let decision = TrackerAutoPolicy.decision(
            from: TrackerMotionEvidence(
                walking: true,
                confidence: .low
            )
        )

        XCTAssertNil(decision)
    }

    func testRunningWinsWhenRunningEvidenceIsPresent() {
        let decision = TrackerAutoPolicy.decision(
            from: TrackerMotionEvidence(
                walking: true,
                running: true,
                confidence: .high
            )
        )

        XCTAssertEqual(decision?.activity, .running)
        XCTAssertEqual(decision?.dwellSeconds, 7)
    }

    func testCyclingDetectionIsDeterministic() {
        let decision = TrackerAutoPolicy.decision(
            from: TrackerMotionEvidence(
                cycling: true,
                confidence: .medium
            )
        )

        XCTAssertEqual(decision?.activity, .cycling)
        XCTAssertEqual(decision?.confidence, "moyenne")
        XCTAssertEqual(decision?.dwellSeconds, 9)
    }

    func testWalkingDetectionIsDeterministic() {
        let decision = TrackerAutoPolicy.decision(
            from: TrackerMotionEvidence(
                walking: true,
                confidence: .high
            )
        )

        XCTAssertEqual(decision?.activity, .walking)
        XCTAssertEqual(decision?.confidence, "élevée")
        XCTAssertEqual(decision?.dwellSeconds, 8)
    }

    func testNoMovementCandidateReturnsNil() {
        XCTAssertNil(
            TrackerAutoPolicy.decision(
                from: TrackerMotionEvidence(
                    stationary: true,
                    confidence: .high
                )
            )
        )
    }

    func testWalkingPauseThresholds() {
        XCTAssertTrue(
            TrackerAutoPolicy.shouldStagePause(
                activity: .walking,
                enabled: true,
                stationary: false,
                speedMps: 0.4,
                cadenceSPM: 90
            )
        )

        XCTAssertFalse(
            TrackerAutoPolicy.shouldStagePause(
                activity: .walking,
                enabled: true,
                stationary: false,
                speedMps: 1.2,
                cadenceSPM: 90
            )
        )
    }

    func testCyclingPauseThresholds() {
        XCTAssertTrue(
            TrackerAutoPolicy.shouldStagePause(
                activity: .cycling,
                enabled: true,
                stationary: false,
                speedMps: 0.3,
                cadenceSPM: 0
            )
        )

        XCTAssertFalse(
            TrackerAutoPolicy.shouldStagePause(
                activity: .cycling,
                enabled: true,
                stationary: false,
                speedMps: 4.0,
                cadenceSPM: 0
            )
        )
    }

    func testAutoPauseDoesNotArmBeforeRealCyclingMovement() {
        XCTAssertFalse(
            TrackerAutoPolicy.canArmPause(
                activity: .cycling,
                elapsedSeconds: 60,
                horizontalAccuracy: 5,
                movementObserved: false
            )
        )
        XCTAssertFalse(
            TrackerAutoPolicy.canArmPause(
                activity: .cycling,
                elapsedSeconds: 12,
                horizontalAccuracy: 5,
                movementObserved: true
            )
        )
        XCTAssertFalse(
            TrackerAutoPolicy.canArmPause(
                activity: .cycling,
                elapsedSeconds: 25,
                horizontalAccuracy: 80,
                movementObserved: true
            )
        )
        XCTAssertTrue(
            TrackerAutoPolicy.canArmPause(
                activity: .cycling,
                elapsedSeconds: 25,
                horizontalAccuracy: 6,
                movementObserved: true
            )
        )
    }

    func testDisabledAutoPauseNeverStagesPauseOrResume() {
        XCTAssertFalse(
            TrackerAutoPolicy.shouldStagePause(
                activity: .running,
                enabled: false,
                stationary: true,
                speedMps: 0,
                cadenceSPM: 0
            )
        )

        XCTAssertFalse(
            TrackerAutoPolicy.shouldStageResume(
                activity: .running,
                enabled: false,
                stationary: false,
                speedMps: 5,
                cadenceSPM: 180,
                motionCandidate: .running
            )
        )
    }

    func testStrongGPSEvidenceOverridesStaleStationaryMotion() {
        XCTAssertTrue(
            TrackerAutoPolicy.shouldStageResume(
                activity: .cycling,
                enabled: true,
                stationary: true,
                speedMps: 3.0,
                cadenceSPM: 0,
                motionCandidate: nil
            )
        )

        XCTAssertTrue(
            TrackerAutoPolicy.shouldStageResume(
                activity: .running,
                enabled: true,
                stationary: true,
                speedMps: 2.2,
                cadenceSPM: 0,
                motionCandidate: nil
            )
        )
    }

    func testStationaryMotionOnlyEvidenceCannotResumeCycling() {
        XCTAssertFalse(
            TrackerAutoPolicy.shouldStageResume(
                activity: .cycling,
                enabled: true,
                stationary: true,
                speedMps: 0,
                cadenceSPM: 0,
                motionCandidate: .cycling
            )
        )
    }

    func testResumeRequiresMovementAndRejectsStationaryMotionOnlyEvidence() {
        XCTAssertTrue(
            TrackerAutoPolicy.shouldStageResume(
                activity: .running,
                enabled: true,
                stationary: false,
                speedMps: 1.5,
                cadenceSPM: 0,
                motionCandidate: nil
            )
        )

        XCTAssertFalse(
            TrackerAutoPolicy.shouldStageResume(
                activity: .running,
                enabled: true,
                stationary: true,
                speedMps: 0,
                cadenceSPM: 0,
                motionCandidate: .running
            )
        )
    }

    func testAutoResumeProbeRejectsStaleAndPoorAccuracySamples() {
        var probe = TrackerAutoResumeProbe()

        XCTAssertNil(
            probe.observe(
                sampleTimestamp: 80,
                now: 100,
                horizontalAccuracy: 5,
                nativeSpeedMps: 4,
                derivedSpeedMps: 4,
                plausibleMaxSpeedMps: 28
            )
        )

        XCTAssertNil(
            probe.observe(
                sampleTimestamp: 100,
                now: 100,
                horizontalAccuracy: 60,
                nativeSpeedMps: 4,
                derivedSpeedMps: 4,
                plausibleMaxSpeedMps: 28
            )
        )

        XCTAssertEqual(probe.recentSpeedMps(now: 100), 0)
    }

    func testAutoResumeProbeProvidesFreshCyclingSpeedWithoutOwningDistance() {
        var probe = TrackerAutoResumeProbe()

        let first = probe.observe(
            sampleTimestamp: 100,
            now: 100,
            horizontalAccuracy: 6,
            nativeSpeedMps: 3.4,
            derivedSpeedMps: 3.2,
            plausibleMaxSpeedMps: 28
        )
        XCTAssertEqual(first ?? -1, 3.4, accuracy: 0.001)
        XCTAssertGreaterThan(probe.recentSpeedMps(now: 103), 1.4)
        XCTAssertEqual(probe.recentSpeedMps(now: 106), 0)

        probe.reset()
        XCTAssertEqual(probe.recentSpeedMps(now: 106), 0)
    }

    func testAutoResumeProbeCanFallbackToDerivedSpeed() {
        var probe = TrackerAutoResumeProbe()

        let speed = probe.observe(
            sampleTimestamp: 200,
            now: 200,
            horizontalAccuracy: 8,
            nativeSpeedMps: -1,
            derivedSpeedMps: 2.8,
            plausibleMaxSpeedMps: 28
        )

        XCTAssertEqual(speed ?? -1, 2.8, accuracy: 0.001)
    }

    func testSyntheticWalkRunCycleReplayProducesExpectedCandidates() {
        let frames: [TrackerMotionEvidence] = [
            .init(walking: true, confidence: .high),
            .init(walking: true, confidence: .high),
            .init(running: true, confidence: .high),
            .init(running: true, confidence: .high),
            .init(cycling: true, confidence: .high),
            .init(cycling: true, confidence: .high),
        ]

        let activities = frames.compactMap {
            TrackerAutoPolicy.decision(from: $0)?.activity
        }

        XCTAssertEqual(
            activities,
            [.walking, .walking, .running, .running, .cycling, .cycling]
        )
    }
}
