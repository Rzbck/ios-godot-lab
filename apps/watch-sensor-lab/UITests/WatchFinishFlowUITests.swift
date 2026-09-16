import XCTest

final class WatchFinishFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAutoFinishCanPreserveDetection() {
        let app = launchHarness()
        openControls(in: app)

        let finish = app.buttons["Terminer"]
        finish.tap()

        let preserve = app.buttons.matching(
            NSPredicate(
                format: "label CONTAINS[c] %@",
                "Conserver la détection Auto"
            )
        ).firstMatch
        XCTAssertTrue(
            preserve.waitForExistence(timeout: 3),
            "Le bouton de conservation Auto n'est pas exposé par le harness watchOS."
        )
        preserve.tap()

        assertResult("preserve", in: app)
    }

    func testAutoFinishCanForceSuggestedConcreteSport() {
        let app = launchHarness()
        openControls(in: app)

        let finish = app.buttons["Terminer"]
        finish.tap()

        XCTAssertTrue(
            app.staticTexts["Suggestion : Vélo"]
                .waitForExistence(timeout: 3)
        )

        let confirm = app.buttons["Forcer · Vélo"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()

        assertResult("force:cycling", in: app)
    }

    func testFinishReviewCanBeCancelled() {
        let app = launchHarness()
        openControls(in: app)

        let finish = app.buttons["Terminer"]
        finish.tap()

        let cancel = app.buttons["Annuler"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.tap()

        assertResult("none", in: app)
    }

    private func launchHarness() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        return app
    }

    private func openControls(in app: XCUIApplication) {
        let finish = app.buttons["Terminer"]
        if finish.waitForExistence(timeout: 1) {
            return
        }

        for _ in 0..<4 where !finish.exists {
            app.swipeLeft()
        }

        if !finish.exists {
            for _ in 0..<4 where !finish.exists {
                app.swipeUp()
            }
        }

        XCTAssertTrue(
            finish.waitForExistence(timeout: 3),
            "La page Contrôles n'est pas atteignable dans le harness watchOS."
        )
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
