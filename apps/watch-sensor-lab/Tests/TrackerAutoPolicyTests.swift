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

    func testResumeRequiresMovementAndRejectsStationaryEvidence() {
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
                speedMps: 5,
                cadenceSPM: 180,
                motionCandidate: .running
            )
        )
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
