import XCTest

final class TrackerAutomationScenarioTests: XCTestCase {
    func testScenarioJSONRoundTripIsStable() throws {
        let scenario = TrackerAutomationFixtures.walkRunCycle
        try scenario.validate()

        let data = try JSONEncoder().encode(scenario)
        let decoded = try JSONDecoder().decode(
            TrackerAutomationScenario.self,
            from: data
        )

        XCTAssertEqual(decoded, scenario)
    }

    func testWalkRunCycleReplayUsesVirtualTimeOnly() throws {
        let result = try TrackerAutomationReplayer.replay(
            TrackerAutomationFixtures.walkRunCycle
        )

        XCTAssertEqual(
            result.activityCandidates,
            [.walking, .walking, .running, .running, .cycling, .cycling]
        )
        XCTAssertEqual(result.totalDistanceMeters, 110, accuracy: 0.001)
        XCTAssertEqual(result.maximumSpeedMps, 7.2, accuracy: 0.001)
        XCTAssertEqual(result.finalHeartRateBPM, 142, accuracy: 0.001)
    }

    func testReplayStartsNeutralUntilConcreteEvidenceArrives() throws {
        let scenario = TrackerAutomationScenario(
            name: "neutral-start",
            frames: [
                TrackerAutomationFrame(
                    offsetSeconds: 0,
                    motion: TrackerMotionEvidence(confidence: .low),
                    speedMps: 0,
                    cadenceSPM: 0,
                    heartRateBPM: 80,
                    distanceDeltaMeters: 0,
                    horizontalAccuracyMeters: 5
                ),
                TrackerAutomationFrame(
                    offsetSeconds: 1,
                    motion: TrackerMotionEvidence(walking: true),
                    speedMps: 5.2,
                    cadenceSPM: 0,
                    heartRateBPM: 100,
                    distanceDeltaMeters: 4.2,
                    horizontalAccuracyMeters: 5
                ),
            ]
        )

        let result = try TrackerAutomationReplayer.replay(scenario)

        XCTAssertEqual(result.activityCandidates, [.cycling])
        XCTAssertTrue(result.pauseCandidateFrameIndexes.contains(0))
    }

    func testStopAndResumeWalkingNeedsMoreThanOneMovingGPSFix() throws {
        let result = try TrackerAutomationReplayer.replay(
            TrackerAutomationFixtures.stopAndResumeWalking
        )

        XCTAssertTrue(result.pauseCandidateFrameIndexes.contains(1))
        XCTAssertTrue(result.pauseCandidateFrameIndexes.contains(2))
        XCTAssertTrue(result.resumeCandidateFrameIndexes.isEmpty)
        XCTAssertEqual(result.autoPauseFrameIndexes, [2])
        XCTAssertTrue(result.endedPaused)
    }

    func testReplayRequiresDwellBeforePauseAndResume() throws {
        let scenario = TrackerAutomationScenario(
            name: "dwell-state-machine",
            frames: [
                frame(at: 0, stationary: false, speed: 1.2, cadence: 90, distance: 2),
                frame(at: 1, stationary: true, speed: 0.1, cadence: 0, distance: 0),
                frame(at: 2.5, stationary: true, speed: 0.1, cadence: 0, distance: 0),
                frame(at: 3.1, stationary: true, speed: 0.1, cadence: 0, distance: 0),
                frame(at: 4, stationary: false, speed: 1.1, cadence: 90, distance: 1),
                frame(at: 5, stationary: false, speed: 1.2, cadence: 92, distance: 1),
                frame(at: 6, stationary: false, speed: 1.2, cadence: 92, distance: 1),
            ]
        )

        let result = try TrackerAutomationReplayer.replay(scenario)

        XCTAssertEqual(result.autoPauseFrameIndexes, [3])
        XCTAssertEqual(result.autoResumeFrameIndexes, [6])
        XCTAssertFalse(result.endedPaused)
    }

    func testAutoPauseDisabledRemovesPauseAndResumeCandidates() throws {
        let base = TrackerAutomationFixtures.stopAndResumeWalking
        let disabled = TrackerAutomationScenario(
            name: base.name,
            selectedActivity: base.selectedActivity,
            autoPauseEnabled: false,
            frames: base.frames
        )

        let result = try TrackerAutomationReplayer.replay(disabled)

        XCTAssertTrue(result.pauseCandidateFrameIndexes.isEmpty)
        XCTAssertTrue(result.resumeCandidateFrameIndexes.isEmpty)
    }

    func testScenarioRejectsNonMonotonicVirtualTime() {
        let invalid = TrackerAutomationScenario(
            name: "invalid-time",
            frames: [
                frame(at: 5),
                frame(at: 5),
            ]
        )

        XCTAssertThrowsError(try invalid.validate()) { error in
            XCTAssertEqual(
                error as? TrackerAutomationScenarioError,
                .nonMonotonicTime(1)
            )
        }
    }

    func testScenarioRejectsNegativeMetrics() {
        let invalid = TrackerAutomationScenario(
            name: "invalid-speed",
            frames: [
                TrackerAutomationFrame(
                    offsetSeconds: 0,
                    motion: TrackerMotionEvidence(walking: true),
                    speedMps: -1,
                    cadenceSPM: 0,
                    heartRateBPM: 80,
                    distanceDeltaMeters: 0,
                    horizontalAccuracyMeters: 5
                ),
            ]
        )

        XCTAssertThrowsError(try invalid.validate()) { error in
            XCTAssertEqual(
                error as? TrackerAutomationScenarioError,
                .negativeMetric(0)
            )
        }
    }

    private func frame(
        at offset: TimeInterval,
        stationary: Bool = false,
        speed: Double = 1,
        cadence: Double = 90,
        distance: Double = 1
    ) -> TrackerAutomationFrame {
        TrackerAutomationFrame(
            offsetSeconds: offset,
            motion: TrackerMotionEvidence(walking: !stationary, stationary: stationary),
            speedMps: speed,
            cadenceSPM: cadence,
            heartRateBPM: 90,
            distanceDeltaMeters: distance,
            horizontalAccuracyMeters: 5
        )
    }
}
