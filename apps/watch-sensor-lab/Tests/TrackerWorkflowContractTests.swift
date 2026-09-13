import XCTest

final class TrackerWorkflowContractTests: XCTestCase {
    func testAutomaticFinishRequiresReviewAndUsesSuggestion() {
        let review = TrackerWorkflowPolicy.finishReview(
            selectedActivity: .automatic,
            effectiveActivity: .walking,
            suggestedActivity: .cycling
        )

        XCTAssertTrue(review.required)
        XCTAssertEqual(review.suggestedActivity, .cycling)
    }

    func testManualFinishDoesNotRequireReview() {
        let review = TrackerWorkflowPolicy.finishReview(
            selectedActivity: .running,
            effectiveActivity: .running,
            suggestedActivity: .cycling
        )

        XCTAssertFalse(review.required)
        XCTAssertEqual(review.suggestedActivity, .cycling)
    }

    func testAutomaticFinishFallsBackToEffectiveActivity() {
        let review = TrackerWorkflowPolicy.finishReview(
            selectedActivity: .automatic,
            effectiveActivity: .walking
        )

        XCTAssertTrue(review.required)
        XCTAssertEqual(review.suggestedActivity, .walking)
    }

    func testFinishDispositionsRemainStable() {
        XCTAssertEqual(
            TrackerFinishDisposition.preserveDetectedSegments.rawValue,
            "preserveDetectedSegments"
        )
        XCTAssertEqual(
            TrackerFinishDisposition.forceSingleActivity.rawValue,
            "forceSingleActivity"
        )
    }

    func testAutomaticIsNeverAForcedSingleSportChoice() {
        let selectableSports = ActivityKind.allCases.filter { !$0.isAutomatic }

        XCTAssertFalse(selectableSports.isEmpty)
        XCTAssertFalse(selectableSports.contains(.automatic))
        XCTAssertTrue(selectableSports.contains(.walking))
        XCTAssertTrue(selectableSports.contains(.running))
        XCTAssertTrue(selectableSports.contains(.cycling))
    }
}
