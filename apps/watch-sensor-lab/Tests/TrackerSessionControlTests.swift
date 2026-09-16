import XCTest

final class TrackerSessionControlTests: XCTestCase {
    private let sessionID = "automation-session"
    private let now: TimeInterval = 1_000

    func testCodecRoundTripsCommandsAndAcknowledgements() {
        let raw = TrackerControlCodec.encode(
            action: .pause,
            token: "token-123"
        )
        let decoded = TrackerControlCodec.decode(raw)

        XCTAssertEqual(decoded?.action, .pause)
        XCTAssertEqual(decoded?.token, "token-123")

        let ack = TrackerControlCodec.acknowledgement(
            token: "token-123",
            result: .accepted
        )
        let parsedAck = TrackerControlCodec.parseAcknowledgement(ack)

        XCTAssertEqual(parsedAck?.token, "token-123")
        XCTAssertEqual(parsedAck?.result, .accepted)
    }

    func testCodecRejectsMalformedMessages() {
        XCTAssertNil(TrackerControlCodec.decode(nil))
        XCTAssertNil(TrackerControlCodec.decode("pause"))
        XCTAssertNil(TrackerControlCodec.decode("control::token"))
        XCTAssertNil(TrackerControlCodec.decode("control:pause:"))
        XCTAssertNil(TrackerControlCodec.decode("control:unknown:token"))

        XCTAssertNil(TrackerControlCodec.parseAcknowledgement(nil))
        XCTAssertNil(TrackerControlCodec.parseAcknowledgement("accepted"))
        XCTAssertNil(TrackerControlCodec.parseAcknowledgement("ack::accepted"))
        XCTAssertNil(TrackerControlCodec.parseAcknowledgement("ack:token:unknown"))
    }

    func testActivePauseIsAccepted() {
        let decision = evaluate(
            action: .pause,
            phase: .active,
            baseRevision: 7,
            authorityRevision: 7
        )

        XCTAssertEqual(decision, .accept())
    }

    func testPausedResumeIsAccepted() {
        let decision = evaluate(
            action: .resume,
            phase: .paused,
            baseRevision: 8,
            authorityRevision: 8
        )

        XCTAssertEqual(decision, .accept())
    }

    func testPauseAndResumeRejectWrongPhase() {
        XCTAssertEqual(
            evaluate(action: .pause, phase: .paused),
            .reject(.stateMismatch)
        )
        XCTAssertEqual(
            evaluate(action: .resume, phase: .active),
            .reject(.stateMismatch)
        )
    }

    func testStalePhoneCommandCannotOverrideNewerWatchAuthority() {
        let decision = evaluate(
            action: .pause,
            phase: .active,
            baseRevision: 10,
            authorityRevision: 12
        )

        XCTAssertEqual(decision, .reject(.staleRevision))
        XCTAssertFalse(decision.shouldApply)
    }

    func testWrongSessionCannotMutateAuthority() {
        let request = request(
            action: .pause,
            sessionID: "old-session",
            baseRevision: 4
        )
        let context = TrackerControlContext(
            sessionID: sessionID,
            authorityRevision: 4,
            phase: .active
        )

        let decision = TrackerControlPolicy.evaluate(
            request: request,
            context: context,
            now: now,
            lastToken: nil,
            lastResult: nil
        )

        XCTAssertEqual(decision, .reject(.sessionMismatch))
    }

    func testExpiredCommandCannotMutateAuthority() {
        let request = TrackerControlRequest(
            action: .pause,
            token: "expired",
            sessionID: sessionID,
            baseRevision: 4,
            issuedAt: now - TrackerControlPolicy.maximumCommandAge - 0.001,
            finishDisposition: nil,
            finalActivity: nil
        )
        let context = TrackerControlContext(
            sessionID: sessionID,
            authorityRevision: 4,
            phase: .active
        )

        let decision = TrackerControlPolicy.evaluate(
            request: request,
            context: context,
            now: now,
            lastToken: nil,
            lastResult: nil
        )

        XCTAssertEqual(decision, .reject(.expired))
    }

    func testDuplicateTransportReplaysResultWithoutApplyingTwice() {
        let request = request(
            action: .stop,
            token: "same-token",
            baseRevision: 15,
            disposition: .preserveDetectedSegments
        )
        let context = TrackerControlContext(
            sessionID: sessionID,
            authorityRevision: 99,
            phase: .ready
        )

        let decision = TrackerControlPolicy.evaluate(
            request: request,
            context: context,
            now: now + 500,
            lastToken: "same-token",
            lastResult: .accepted
        )

        XCTAssertEqual(
            decision,
            .duplicate(replaying: .accepted)
        )
        XCTAssertFalse(decision.shouldApply)
        XCTAssertTrue(decision.isDuplicate)
    }

    func testStopPreservingDetectedSegmentsIsAccepted() {
        let decision = evaluate(
            action: .stop,
            phase: .active,
            disposition: .preserveDetectedSegments
        )

        XCTAssertEqual(decision, .accept())
    }

    func testStopCanForceOneConcreteSport() {
        let decision = evaluate(
            action: .stop,
            phase: .active,
            disposition: .forceSingleActivity,
            finalActivity: .cycling
        )

        XCTAssertEqual(decision, .accept())
    }

    func testStopCannotForceAutomaticAsSingleSport() {
        XCTAssertEqual(
            evaluate(
                action: .stop,
                phase: .active,
                disposition: .forceSingleActivity,
                finalActivity: .automatic
            ),
            .reject(.invalidFinishActivity)
        )

        XCTAssertEqual(
            evaluate(
                action: .stop,
                phase: .active,
                disposition: .forceSingleActivity,
                finalActivity: nil
            ),
            .reject(.invalidFinishActivity)
        )
    }

    func testCommandAtMaximumAgeBoundaryIsStillAccepted() {
        let request = TrackerControlRequest(
            action: .pause,
            token: "boundary",
            sessionID: sessionID,
            baseRevision: 2,
            issuedAt: now - TrackerControlPolicy.maximumCommandAge,
            finishDisposition: nil,
            finalActivity: nil
        )
        let context = TrackerControlContext(
            sessionID: sessionID,
            authorityRevision: 2,
            phase: .active
        )

        let decision = TrackerControlPolicy.evaluate(
            request: request,
            context: context,
            now: now,
            lastToken: nil,
            lastResult: nil
        )

        XCTAssertEqual(decision, .accept())
    }

    private func evaluate(
        action: TrackerControlAction,
        phase: TrackerControlPhase,
        baseRevision: Int64 = 1,
        authorityRevision: Int64 = 1,
        disposition: TrackerFinishDisposition? = nil,
        finalActivity: ActivityKind? = nil
    ) -> TrackerControlDecision {
        TrackerControlPolicy.evaluate(
            request: request(
                action: action,
                baseRevision: baseRevision,
                disposition: disposition,
                finalActivity: finalActivity
            ),
            context: TrackerControlContext(
                sessionID: sessionID,
                authorityRevision: authorityRevision,
                phase: phase
            ),
            now: now,
            lastToken: nil,
            lastResult: nil
        )
    }

    private func request(
        action: TrackerControlAction,
        token: String = "token",
        sessionID: String? = nil,
        baseRevision: Int64,
        disposition: TrackerFinishDisposition? = nil,
        finalActivity: ActivityKind? = nil
    ) -> TrackerControlRequest {
        TrackerControlRequest(
            action: action,
            token: token,
            sessionID: sessionID ?? self.sessionID,
            baseRevision: baseRevision,
            issuedAt: now,
            finishDisposition: disposition,
            finalActivity: finalActivity
        )
    }
}
