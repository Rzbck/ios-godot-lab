import XCTest

final class iPhoneFinishFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAutoFinishCanPreserveDetectedSegments() {
        let app = launchHarness()

        let finish = app.buttons["Terminer"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()

        XCTAssertTrue(
            app.navigationBars["Terminer la séance"]
                .waitForExistence(timeout: 3)
        )

        let preserve = app.buttons["Conserver les segments détectés"]
        XCTAssertTrue(preserve.waitForExistence(timeout: 3))
        preserve.tap()

        assertResult("preserve", in: app)
    }

    func testAutoFinishCanConfirmSuggestedConcreteSport() {
        let app = launchHarness()

        let finish = app.buttons["Terminer"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()

        XCTAssertTrue(
            app.staticTexts["Suggestion Auto : Vélo"]
                .waitForExistence(timeout: 3)
        )

        let confirm = app.buttons["Enregistrer comme Vélo"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()

        assertResult("force:cycling", in: app)
    }

    func testFinishReviewCanBeCancelledWithoutFinishing() {
        let app = launchHarness()

        let finish = app.buttons["Terminer"]
        XCTAssertTrue(finish.waitForExistence(timeout: 5))
        finish.tap()

        let cancel = app.buttons["Annuler"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.tap()

        XCTAssertTrue(finish.waitForExistence(timeout: 3))
        assertResult("none", in: app)
    }

    private func launchHarness() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }

    private func assertResult(
        _ expected: String,
        in app: XCUIApplication
    ) {
        let result = app.staticTexts["harness.finish.result"]
        XCTAssertTrue(result.exists)
        let predicate = NSPredicate(format: "label == %@", expected)
        let expectation = XCTNSPredicateExpectation(
            predicate: predicate,
            object: result
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: 3),
            .completed
        )
    }
}
