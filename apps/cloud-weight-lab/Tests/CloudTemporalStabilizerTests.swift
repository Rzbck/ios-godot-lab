import XCTest
@testable import CloudWeightLab

final class CloudTemporalStabilizerTests: XCTestCase {
    func testNearbyDetectionKeepsStableIdentity() throws {
        let stabilizer = CloudTemporalStabilizer()

        let first = stabilizer.update(raw: [
            detection(id: 0, x: 0.30, y: 0.30, mass: 100_000)
        ])
        let second = stabilizer.update(raw: [
            detection(id: 7, x: 0.33, y: 0.31, mass: 120_000)
        ])

        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(first[0].id, second[0].id)
    }

    func testMassJumpIsSmoothed() throws {
        let stabilizer = CloudTemporalStabilizer()

        _ = stabilizer.update(raw: [
            detection(id: 0, x: 0.40, y: 0.40, mass: 100_000)
        ])
        let second = try XCTUnwrap(
            stabilizer.update(raw: [
                detection(id: 1, x: 0.41, y: 0.40, mass: 500_000)
            ]).first
        )

        XCTAssertGreaterThan(second.estimate.midpointKilograms, 100_000)
        XCTAssertLessThan(second.estimate.midpointKilograms, 500_000)
    }

    func testClassifierFlickerDoesNotImmediatelyMoveKindOrMass() throws {
        let stabilizer = CloudTemporalStabilizer()
        let initial = try XCTUnwrap(
            stabilizer.update(raw: [
                detection(id: 0, x: 0.40, y: 0.40, mass: 500_000, kind: .cumulus)
            ]).first
        )

        for index in 0..<14 {
            let next = try XCTUnwrap(
                stabilizer.update(raw: [
                    detection(
                        id: index + 1,
                        x: 0.40,
                        y: 0.40,
                        mass: 80_000,
                        kind: .stratocumulus
                    )
                ]).first
            )
            XCTAssertEqual(next.observation.kind, .cumulus)
            XCTAssertGreaterThan(next.estimate.midpointKilograms, initial.estimate.midpointKilograms * 0.80)
        }
    }

    func testSustainedKindChangeEventuallySwitches() throws {
        let stabilizer = CloudTemporalStabilizer()
        _ = stabilizer.update(raw: [
            detection(id: 0, x: 0.40, y: 0.40, mass: 500_000, kind: .cumulus)
        ])

        var latest: CloudDetection?
        for index in 0..<15 {
            latest = stabilizer.update(raw: [
                detection(
                    id: index + 1,
                    x: 0.40,
                    y: 0.40,
                    mass: 80_000,
                    kind: .stratocumulus
                )
            ]).first
        }
        XCTAssertEqual(try XCTUnwrap(latest).observation.kind, .stratocumulus)
    }

    func testSingleMissingAnalysisIsHiddenButIdentityRecovers() throws {
        let stabilizer = CloudTemporalStabilizer()

        let first = try XCTUnwrap(
            stabilizer.update(raw: [
                detection(id: 0, x: 0.50, y: 0.45, mass: 220_000)
            ]).first
        )

        let oneMiss = stabilizer.update(raw: [])
        XCTAssertTrue(oneMiss.isEmpty)
        XCTAssertEqual(stabilizer.lastStats.hiddenMissedTracks, 1)
        XCTAssertEqual(stabilizer.lastStats.activeTracks, 1)

        let recovered = try XCTUnwrap(
            stabilizer.update(raw: [
                detection(id: 9, x: 0.515, y: 0.455, mass: 225_000)
            ]).first
        )
        XCTAssertEqual(recovered.id, first.id)
        XCTAssertEqual(stabilizer.lastStats.hiddenMissedTracks, 0)
    }

    func testThreeMissesKeepTrackHiddenAndIdentityRecovers() throws {
        let stabilizer = CloudTemporalStabilizer()

        let first = try XCTUnwrap(
            stabilizer.update(raw: [
                detection(id: 0, x: 0.50, y: 0.45, mass: 220_000)
            ]).first
        )

        _ = stabilizer.update(raw: [])
        _ = stabilizer.update(raw: [])
        let thirdMiss = stabilizer.update(raw: [])

        XCTAssertTrue(thirdMiss.isEmpty)
        XCTAssertEqual(stabilizer.lastStats.activeTracks, 1)

        let recovered = try XCTUnwrap(
            stabilizer.update(raw: [
                detection(id: 99, x: 0.515, y: 0.455, mass: 225_000)
            ]).first
        )

        XCTAssertEqual(recovered.id, first.id)
    }

    func testFourMissesRemoveTrack() {
        let stabilizer = CloudTemporalStabilizer()

        _ = stabilizer.update(raw: [
            detection(id: 0, x: 0.50, y: 0.45, mass: 220_000)
        ])

        _ = stabilizer.update(raw: [])
        _ = stabilizer.update(raw: [])
        _ = stabilizer.update(raw: [])
        _ = stabilizer.update(raw: [])

        XCTAssertEqual(stabilizer.lastStats.activeTracks, 0)
    }

    func testTwoNearbyCloudsDoNotSwapIdsWhenInputOrderChanges() throws {
        let stabilizer = CloudTemporalStabilizer()

        let first = stabilizer.update(raw: [
            detection(id: 0, x: 0.18, y: 0.30, mass: 160_000),
            detection(id: 1, x: 0.58, y: 0.30, mass: 120_000)
        ])
        XCTAssertEqual(first.count, 2)

        let leftID = try XCTUnwrap(first.min(by: { $0.observation.centroid.x < $1.observation.centroid.x })?.id)
        let rightID = try XCTUnwrap(first.max(by: { $0.observation.centroid.x < $1.observation.centroid.x })?.id)

        let second = stabilizer.update(raw: [
            detection(id: 7, x: 0.56, y: 0.31, mass: 130_000),
            detection(id: 8, x: 0.20, y: 0.31, mass: 170_000)
        ])

        let leftSecond = try XCTUnwrap(second.min(by: { $0.observation.centroid.x < $1.observation.centroid.x }))
        let rightSecond = try XCTUnwrap(second.max(by: { $0.observation.centroid.x < $1.observation.centroid.x }))
        XCTAssertEqual(leftSecond.id, leftID)
        XCTAssertEqual(rightSecond.id, rightID)
    }

    private func detection(
        id: Int,
        x: Double,
        y: Double,
        mass: Double,
        kind: CloudKind = .cumulus
    ) -> CloudDetection {
        let observation = CloudObservation(
            id: id,
            kind: kind,
            confidence: 0.82,
            coverage: 0.12,
            bounds: CGRect(x: x, y: y, width: 0.24, height: 0.18),
            centroid: CGPoint(x: x + 0.12, y: y + 0.09),
            averageBrightness: 0.75,
            averageSaturation: 0.14,
            fieldOfViewDegrees: 64
        )
        let estimate = CloudMassEstimate(
            lowKilograms: mass * 0.6,
            midpointKilograms: mass,
            highKilograms: mass * 1.5,
            estimatedWidthMeters: 900,
            estimatedHeightMeters: 650,
            estimatedDepthMeters: 450,
            estimatedDistanceMeters: 2_000,
            projectedAreaSquareMeters: 300_000,
            estimatedVolumeCubicMeters: 135_000_000,
            angularWidthDegrees: 12,
            angularHeightDegrees: 8,
            centerElevationDegrees: 55,
            confidence: 0.78
        )
        return CloudDetection(observation: observation, estimate: estimate)
    }
}
