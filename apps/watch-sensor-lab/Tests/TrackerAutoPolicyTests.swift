import XCTest

final class TrackerAutoPolicyTests: XCTestCase {
    func testLowConfidenceMotionAloneIsIgnored() {
        let decision = TrackerAutoPolicy.decision(
            from: TrackerMotionEvidence(
                walking: true,
                confidence: .low
            )
        )

        XCTAssertNil(decision)
    }

    func testCoreMotionRunningWinsWhenTrusted() {
        let decision = TrackerAutoPolicy.decision(
            from: TrackerMotionEvidence(
                walking: true,
                running: true,
                confidence: .high
            ),
            speedMps: 3.0,
            cadenceSPM: 165
        )

        XCTAssertEqual(decision?.activity, .running)
        XCTAssertEqual(decision?.dwellSeconds, 2.0)
    }

    func testCoreMotionCyclingIsDeterministic() {
        let decision = TrackerAutoPolicy.decision(
            from: TrackerMotionEvidence(
                cycling: true,
                confidence: .medium
            ),
            speedMps: 5.0,
            cadenceSPM: 0
        )

        XCTAssertEqual(decision?.activity, .cycling)
        XCTAssertEqual(decision?.confidence, "moyenne")
        XCTAssertEqual(decision?.dwellSeconds, 2.0)
    }

    func testConcreteAutoDecisionsDoNotUseTenSecondDwell() {
        let frames: [(TrackerMotionEvidence, Double, Double)] = [
            (.init(walking: true, confidence: .high), 1.2, 90),
            (.init(running: true, confidence: .high), 2.8, 165),
            (.init(cycling: true, confidence: .high), 4.5, 0),
        ]

        for (evidence, speed, cadence) in frames {
            let decision = TrackerAutoPolicy.decision(
                from: evidence,
                speedMps: speed,
                cadenceSPM: cadence
            )
            XCTAssertNotNil(decision)
            XCTAssertLessThanOrEqual(decision?.dwellSeconds ?? 99, 2.5)
        }
    }

    func testWalkingFlagCannotBeatNoisyCyclingCadence() {
        let decision = TrackerAutoPolicy.decision(
            from: TrackerMotionEvidence(
                walking: true,
                confidence: .high
            ),
            speedMps: 4.2,
            cadenceSPM: 82
        )

        XCTAssertEqual(decision?.activity, .cycling)
        XCTAssertEqual(decision?.provenance, "GPS · vélo")
    }

    func testWalkingFlagNeedsCyclingGradeSpeedWhenCadenceIsMissing() {
        let fastRunWithoutCadence = TrackerAutoPolicy.decision(
            from: TrackerMotionEvidence(walking: true, confidence: .high),
            speedMps: 3.8,
            cadenceSPM: 0
        )
        let clearCyclingSpeed = TrackerAutoPolicy.decision(
            from: TrackerMotionEvidence(walking: true, confidence: .high),
            speedMps: 5.2,
            cadenceSPM: 0
        )

        XCTAssertNil(fastRunWithoutCadence)
        XCTAssertEqual(clearCyclingSpeed?.activity, .cycling)
    }

    func testWalkingFlagCannotBeatRunningCadenceAndSpeed() {
        let decision = TrackerAutoPolicy.decision(
            from: TrackerMotionEvidence(
                walking: true,
                confidence: .high
            ),
            speedMps: 2.8,
            cadenceSPM: 168
        )

        XCTAssertEqual(decision?.activity, .running)
        XCTAssertEqual(decision?.provenance, "GPS + cadence · course")
    }

    func testSensorFallbackCanClassifyWalkingWithoutCoreMotionLabel() {
        let decision = TrackerAutoPolicy.decision(
            from: TrackerMotionEvidence(confidence: .low),
            speedMps: 1.2,
            cadenceSPM: 92
        )

        XCTAssertEqual(decision?.activity, .walking)
        XCTAssertEqual(decision?.confidence, "capteurs")
    }

    func testNoMovementCandidateReturnsNil() {
        XCTAssertNil(
            TrackerAutoPolicy.decision(
                from: TrackerMotionEvidence(
                    stationary: true,
                    confidence: .high
                ),
                speedMps: 0,
                cadenceSPM: 0
            )
        )
    }

    func testPauseArmsForStillStartWithReliableGPS() {
        XCTAssertTrue(
            TrackerAutoPolicy.canArmPause(
                activity: .cycling,
                elapsedSeconds: 120,
                horizontalAccuracy: 5,
                movementObserved: false
            )
        )
    }

    func testPauseArmsImmediatelyAfterRealMovementWithGoodGPS() {
        XCTAssertTrue(
            TrackerAutoPolicy.canArmPause(
                activity: .cycling,
                elapsedSeconds: 2,
                horizontalAccuracy: 6,
                movementObserved: true
            )
        )
    }

    func testPauseStillRejectsBadGPS() {
        XCTAssertFalse(
            TrackerAutoPolicy.canArmPause(
                activity: .running,
                elapsedSeconds: 40,
                horizontalAccuracy: 80,
                movementObserved: true
            )
        )
    }

    func testPauseArmsFromTrustedIndoorMotionWithoutGPS() {
        XCTAssertTrue(
            TrackerAutoPolicy.canArmPause(
                activity: .other,
                elapsedSeconds: 2,
                horizontalAccuracy: 500,
                movementObserved: false,
                motionMovementObserved: true
            )
        )
    }

    func testWalkingDoesNotPauseWhileCadenceShowsMovement() {
        XCTAssertFalse(
            TrackerAutoPolicy.shouldStagePause(
                activity: .walking,
                enabled: true,
                stationary: false,
                speedMps: 0.4,
                cadenceSPM: 90
            )
        )

        XCTAssertTrue(
            TrackerAutoPolicy.shouldStagePause(
                activity: .walking,
                enabled: true,
                stationary: true,
                speedMps: 0.1,
                cadenceSPM: 0
            )
        )
    }

    func testGenericSportGetsSameAutoPauseBehavior() {
        XCTAssertTrue(
            TrackerAutoPolicy.shouldStagePause(
                activity: .soccer,
                enabled: true,
                stationary: true,
                speedMps: 0.1,
                cadenceSPM: 0
            )
        )

        XCTAssertTrue(
            TrackerAutoPolicy.shouldStageResume(
                activity: .soccer,
                enabled: true,
                stationary: false,
                speedMps: 1.0,
                cadenceSPM: 90,
                motionCandidate: .running,
                gpsEvidenceConfirmed: false,
                motionEvidenceFresh: true,
                cadenceEvidenceFresh: true
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
                motionCandidate: nil,
                gpsEvidenceConfirmed: true,
                motionEvidenceFresh: false,
                cadenceEvidenceFresh: false
            )
        )

        XCTAssertTrue(
            TrackerAutoPolicy.shouldStageResume(
                activity: .running,
                enabled: true,
                stationary: true,
                speedMps: 2.2,
                cadenceSPM: 0,
                motionCandidate: nil,
                gpsEvidenceConfirmed: true,
                motionEvidenceFresh: false,
                cadenceEvidenceFresh: false
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

    func testFrozenCadenceCannotResumeAfterAutoPause() {
        XCTAssertFalse(
            TrackerAutoPolicy.shouldStageResume(
                activity: .walking,
                enabled: true,
                stationary: false,
                speedMps: 0,
                cadenceSPM: 113,
                motionCandidate: nil,
                gpsEvidenceConfirmed: false,
                motionEvidenceFresh: false,
                cadenceEvidenceFresh: false
            )
        )
    }

    func testSingleFreshMotionCallbackCannotResume() {
        XCTAssertFalse(
            TrackerAutoPolicy.shouldStageResume(
                activity: .running,
                enabled: true,
                stationary: false,
                speedMps: 0,
                cadenceSPM: 0,
                motionCandidate: .running,
                gpsEvidenceConfirmed: false,
                motionEvidenceFresh: true,
                cadenceEvidenceFresh: false
            )
        )
    }

    func testFreshMotionAndCadenceCanResumeWithoutGPS() {
        XCTAssertTrue(
            TrackerAutoPolicy.shouldStageResume(
                activity: .running,
                enabled: true,
                stationary: false,
                speedMps: 0,
                cadenceSPM: 150,
                motionCandidate: .running,
                gpsEvidenceConfirmed: false,
                motionEvidenceFresh: true,
                cadenceEvidenceFresh: true
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
        XCTAssertEqual(probe.confirmedRecentSpeedMps(now: 103), 0)

        _ = probe.observe(
            sampleTimestamp: 102,
            now: 102,
            horizontalAccuracy: 6,
            nativeSpeedMps: 3.6,
            derivedSpeedMps: 3.5,
            plausibleMaxSpeedMps: 28
        )
        XCTAssertGreaterThan(probe.confirmedRecentSpeedMps(now: 103), 1.4)
        XCTAssertEqual(probe.recentSpeedMps(now: 106), 0)

        probe.reset()
        XCTAssertEqual(probe.recentSpeedMps(now: 106), 0)
    }

    func testAutoResumeProbeRejectsPoorSpeedAccuracy() {
        var probe = TrackerAutoResumeProbe()

        XCTAssertNil(
            probe.observe(
                sampleTimestamp: 100,
                now: 100,
                horizontalAccuracy: 4,
                nativeSpeedMps: 4,
                speedAccuracyMps: 12,
                derivedSpeedMps: 4,
                plausibleMaxSpeedMps: 28
            )
        )
        XCTAssertEqual(probe.confirmedRecentSpeedMps(now: 100), 0)
    }

    func testAutoResumeProbeRequiresTemporallyCoherentGPSFixes() {
        var probe = TrackerAutoResumeProbe()

        _ = probe.observe(
            sampleTimestamp: 100,
            now: 100,
            horizontalAccuracy: 5,
            nativeSpeedMps: 3.2,
            derivedSpeedMps: 3.2,
            plausibleMaxSpeedMps: 28
        )
        _ = probe.observe(
            sampleTimestamp: 109,
            now: 109,
            horizontalAccuracy: 5,
            nativeSpeedMps: 3.4,
            derivedSpeedMps: 3.4,
            plausibleMaxSpeedMps: 28
        )

        XCTAssertEqual(probe.confirmedRecentSpeedMps(now: 109), 0)
    }

    func testSyntheticWalkRunCycleReplayProducesExpectedCandidates() {
        let frames: [(TrackerMotionEvidence, Double, Double)] = [
            (.init(walking: true, confidence: .high), 1.2, 90),
            (.init(walking: true, confidence: .high), 2.8, 165),
            (.init(walking: true, confidence: .high), 5.2, 0),
        ]

        let activities = frames.compactMap { evidence, speed, cadence in
            TrackerAutoPolicy.decision(
                from: evidence,
                speedMps: speed,
                cadenceSPM: cadence
            )?.activity
        }

        XCTAssertEqual(activities, [.walking, .running, .cycling])
    }
}
