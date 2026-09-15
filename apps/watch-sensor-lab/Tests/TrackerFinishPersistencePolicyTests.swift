import XCTest

final class TrackerFinishPersistencePolicyTests: XCTestCase {
    func testFinalConfirmationReturnsConcreteOverride() {
        XCTAssertEqual(
            TrackerFinishPersistencePolicy.forcedFinalActivity(
                event: "final_activity_confirmed",
                payload: ["to": "cycling"]
            ),
            .cycling
        )
    }

    func testUnrelatedOrAutomaticEventsDoNotCollapseSegments() {
        XCTAssertNil(
            TrackerFinishPersistencePolicy.forcedFinalActivity(
                event: "auto_activity_changed",
                payload: ["to": "cycling"]
            )
        )
        XCTAssertNil(
            TrackerFinishPersistencePolicy.forcedFinalActivity(
                event: "final_activity_confirmed",
                payload: ["to": "automatic"]
            )
        )
    }

    func testPendingPlansRetryOnBindAndActivation() {
        XCTAssertTrue(TrackerFinishPersistencePolicy.shouldSchedulePendingPlans(
            pendingCount: 1,
            reconciliationIsActive: false,
            trigger: .initialBind
        ))
        XCTAssertTrue(TrackerFinishPersistencePolicy.shouldSchedulePendingPlans(
            pendingCount: 1,
            reconciliationIsActive: false,
            trigger: .connectivityActivated
        ))
    }

    func testPendingPlansRetryOnlyWhenReachableAndIdle() {
        XCTAssertFalse(TrackerFinishPersistencePolicy.shouldSchedulePendingPlans(
            pendingCount: 1,
            reconciliationIsActive: false,
            trigger: .reachabilityChanged(isReachable: false)
        ))
        XCTAssertFalse(TrackerFinishPersistencePolicy.shouldSchedulePendingPlans(
            pendingCount: 1,
            reconciliationIsActive: true,
            trigger: .reachabilityChanged(isReachable: true)
        ))
        XCTAssertTrue(TrackerFinishPersistencePolicy.shouldSchedulePendingPlans(
            pendingCount: 1,
            reconciliationIsActive: false,
            trigger: .reachabilityChanged(isReachable: true)
        ))
    }

    func testNoPendingPlanDoesNotSchedule() {
        XCTAssertFalse(TrackerFinishPersistencePolicy.shouldSchedulePendingPlans(
            pendingCount: 0,
            reconciliationIsActive: false,
            trigger: .connectivityActivated
        ))
    }
}
