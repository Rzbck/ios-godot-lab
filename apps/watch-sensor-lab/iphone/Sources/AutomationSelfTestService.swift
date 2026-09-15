import Foundation
import Network

/// Read-only on-device self-test endpoint.
///
/// This service never starts HKWorkoutSession, never writes HealthKit, never
/// touches the session store, and never sends WatchConnectivity commands. It
/// only executes deterministic shared policies already covered by XCTest.
/// Windows reaches it over usbmux on device port 37992.
final class AutomationSelfTestService {
    static let shared = AutomationSelfTestService()

    static let protocolName = "wsl_selftest_v1"
    static let devicePort: UInt16 = 37992

    private let queue = DispatchQueue(
        label: "com.rzbck.watchsensorlab.selftest-api",
        qos: .utility
    )
    private var listener: NWListener?

    private init() {}

    func start() {
        guard listener == nil else { return }
        guard let port = NWEndpoint.Port(rawValue: Self.devicePort) else {
            return
        }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: port)
            listener.newConnectionHandler = { [weak self] connection in
                self?.accept(connection)
            }
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    AppTelemetry.shared.event(
                        "selftest_api_ready",
                        fields: [
                            "port": Self.devicePort,
                            "protocol": Self.protocolName,
                            "read_only": true,
                            "healthkit_mutation": false,
                        ]
                    )
                case .failed(let error):
                    AppTelemetry.shared.error(
                        "selftest_api_failed",
                        error: error,
                        fields: ["port": Self.devicePort]
                    )
                default:
                    break
                }
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            AppTelemetry.shared.error(
                "selftest_api_start_failed",
                error: error,
                fields: ["port": Self.devicePort]
            )
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .ready:
                if self.isDisallowedNetworkPath(connection.currentPath) {
                    connection.cancel()
                    return
                }
                self.receive(on: connection, buffer: Data())
            case .failed(_), .cancelled:
                break
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func isDisallowedNetworkPath(_ path: NWPath?) -> Bool {
        guard let path else { return false }
        return path.usesInterfaceType(.wifi)
            || path.usesInterfaceType(.cellular)
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 4_096
        ) { [weak self, weak connection] data, _, isComplete, error in
            guard let self, let connection else { return }
            guard error == nil else {
                connection.cancel()
                return
            }

            var next = buffer
            if let data { next.append(data) }
            guard next.count <= 16 * 1_024 else {
                self.send(
                    ["ok": false, "error": "request_too_large"],
                    on: connection
                )
                return
            }

            if let newline = next.firstIndex(of: 0x0A) {
                self.handle(Data(next[..<newline]), on: connection)
                return
            }

            if isComplete {
                if next.isEmpty {
                    connection.cancel()
                } else {
                    self.handle(next, on: connection)
                }
                return
            }

            self.receive(on: connection, buffer: next)
        }
    }

    private func handle(_ data: Data, on connection: NWConnection) {
        guard
            let request = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any]
        else {
            send(["ok": false, "error": "invalid_json"], on: connection)
            return
        }

        if let requestedProtocol = request["protocol"] as? String,
           requestedProtocol != Self.protocolName {
            send(
                [
                    "ok": false,
                    "error": "unsupported_protocol",
                    "protocol": Self.protocolName,
                ],
                on: connection
            )
            return
        }

        let command = (request["command"] as? String ?? "run").lowercased()
        guard command == "run" || command == "ping" else {
            send(
                ["ok": false, "error": "unknown_command"],
                on: connection
            )
            return
        }

        if command == "ping" {
            send(
                [
                    "ok": true,
                    "command": "ping",
                    "protocol": Self.protocolName,
                    "build_sha": BuildInfo.gitSHA,
                    "read_only": true,
                    "healthkit_mutation": false,
                    "workout_mutation": false,
                    "device_port": Self.devicePort,
                ],
                on: connection
            )
            return
        }

        let report = SelfTestRunner.run()
        send(
            [
                "ok": report.failed == 0,
                "command": "run",
                "protocol": Self.protocolName,
                "build_sha": BuildInfo.gitSHA,
                "read_only": true,
                "healthkit_mutation": false,
                "workout_mutation": false,
                "passed": report.passed,
                "failed": report.failed,
                "tests": report.tests.map { result in
                    [
                        "name": result.name,
                        "passed": result.passed,
                        "detail": result.detail,
                    ] as [String: Any]
                },
            ],
            on: connection
        )
    }

    private func send(_ payload: [String: Any], on connection: NWConnection) {
        guard
            JSONSerialization.isValidJSONObject(payload),
            var data = try? JSONSerialization.data(withJSONObject: payload)
        else {
            connection.cancel()
            return
        }
        data.append(0x0A)
        connection.send(
            content: data,
            completion: .contentProcessed { _ in
                connection.cancel()
            }
        )
    }
}

private struct SelfTestResult {
    let name: String
    let passed: Bool
    let detail: String
}

private struct SelfTestReport {
    let tests: [SelfTestResult]

    var passed: Int { tests.filter(\.passed).count }
    var failed: Int { tests.count - passed }
}

private enum SelfTestRunner {
    static func run() -> SelfTestReport {
        var results: [SelfTestResult] = []

        func check(_ name: String, _ condition: @autoclosure () -> Bool, detail: String) {
            let passed = condition()
            results.append(
                SelfTestResult(
                    name: name,
                    passed: passed,
                    detail: passed ? "ok" : detail
                )
            )
        }

        let automaticReview = TrackerWorkflowPolicy.finishReview(
            selectedActivity: .automatic,
            effectiveActivity: .walking,
            suggestedActivity: .cycling
        )
        check(
            "finish.auto.requires_review",
            automaticReview.required && automaticReview.suggestedActivity == .cycling,
            detail: "Auto finish review contract failed"
        )

        let manualReview = TrackerWorkflowPolicy.finishReview(
            selectedActivity: .running,
            effectiveActivity: .running,
            suggestedActivity: .cycling
        )
        check(
            "finish.manual.no_review",
            !manualReview.required,
            detail: "Manual finish unexpectedly requires review"
        )

        let encoded = TrackerControlCodec.encode(
            action: .pause,
            token: "selftest-token"
        )
        let decoded = TrackerControlCodec.decode(encoded)
        check(
            "control.codec.roundtrip",
            decoded?.action == .pause && decoded?.token == "selftest-token",
            detail: "Control codec roundtrip failed"
        )

        let stale = TrackerControlPolicy.evaluate(
            request: TrackerControlRequest(
                action: .pause,
                token: "stale",
                sessionID: "session",
                baseRevision: 2,
                issuedAt: 100,
                finishDisposition: nil,
                finalActivity: nil
            ),
            context: TrackerControlContext(
                sessionID: "session",
                authorityRevision: 3,
                phase: .active
            ),
            now: 101,
            lastToken: nil,
            lastResult: nil
        )
        check(
            "control.stale_revision.rejected",
            stale.result == .staleRevision && !stale.shouldApply,
            detail: "Stale control could mutate Watch authority"
        )

        let duplicate = TrackerControlPolicy.evaluate(
            request: TrackerControlRequest(
                action: .stop,
                token: "duplicate",
                sessionID: "session",
                baseRevision: 1,
                issuedAt: 0,
                finishDisposition: .preserveDetectedSegments,
                finalActivity: nil
            ),
            context: TrackerControlContext(
                sessionID: "other",
                authorityRevision: 99,
                phase: .ready
            ),
            now: 999,
            lastToken: "duplicate",
            lastResult: .accepted
        )
        check(
            "control.duplicate.idempotent",
            duplicate.isDuplicate
                && !duplicate.shouldApply
                && duplicate.result == .accepted,
            detail: "Duplicate command was not replayed idempotently"
        )

        let invalidFinish = TrackerControlPolicy.evaluate(
            request: TrackerControlRequest(
                action: .stop,
                token: "finish",
                sessionID: "session",
                baseRevision: 4,
                issuedAt: 100,
                finishDisposition: .forceSingleActivity,
                finalActivity: .automatic
            ),
            context: TrackerControlContext(
                sessionID: "session",
                authorityRevision: 4,
                phase: .active
            ),
            now: 101,
            lastToken: nil,
            lastResult: nil
        )
        check(
            "finish.force_auto.rejected",
            invalidFinish.result == .invalidFinishActivity,
            detail: "Automatic activity accepted as a forced single sport"
        )

        let walking = TrackerAutoPolicy.decision(
            from: TrackerMotionEvidence(
                walking: true,
                confidence: .high
            )
        )
        check(
            "auto.walking.synthetic",
            walking?.activity == .walking && walking?.dwellSeconds == 8,
            detail: "Synthetic walking classification failed"
        )

        let running = TrackerAutoPolicy.decision(
            from: TrackerMotionEvidence(
                running: true,
                confidence: .high
            )
        )
        check(
            "auto.running.synthetic",
            running?.activity == .running && running?.dwellSeconds == 7,
            detail: "Synthetic running classification failed"
        )

        let cycling = TrackerAutoPolicy.decision(
            from: TrackerMotionEvidence(
                cycling: true,
                confidence: .high
            )
        )
        check(
            "auto.cycling.synthetic",
            cycling?.activity == .cycling && cycling?.dwellSeconds == 9,
            detail: "Synthetic cycling classification failed"
        )

        check(
            "autopause.walking.stop",
            TrackerAutoPolicy.shouldStagePause(
                activity: .walking,
                enabled: true,
                stationary: true,
                speedMps: 0.1,
                cadenceSPM: 0
            ),
            detail: "Walking stop did not stage Auto Pause"
        )

        check(
            "autopause.walking.resume",
            TrackerAutoPolicy.shouldStageResume(
                activity: .walking,
                enabled: true,
                stationary: false,
                speedMps: 1.0,
                cadenceSPM: 80,
                motionCandidate: .walking,
                motionEvidenceFresh: true,
                cadenceEvidenceFresh: true
            ),
            detail: "Walking movement did not stage resume"
        )

        return SelfTestReport(tests: results)
    }
}
