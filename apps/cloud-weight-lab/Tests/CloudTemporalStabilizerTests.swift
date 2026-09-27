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

    func testSingleMissingAnalysisDoesNotBlinkTrack() {
        let stabilizer = CloudTemporalStabilizer()

        _ = stabilizer.update(raw: [
            detection(id: 0, x: 0.50, y: 0.45, mass: 220_000)
        ])
        let oneMiss = stabilizer.update(raw: [])
        let twoMisses = stabilizer.update(raw: [])

        XCTAssertEqual(oneMiss.count, 1)
        XCTAssertTrue(twoMisses.isEmpty)
    }

    private func detection(
        id: Int,
        x: Double,
        y: Double,
        mass: Double
    ) -> CloudDetection {
        let observation = CloudObservation(
            id: id,
            kind: .cumulus,
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
            confidence: 0.78
        )
        return CloudDetection(observation: observation, estimate: estimate)
    }
}
