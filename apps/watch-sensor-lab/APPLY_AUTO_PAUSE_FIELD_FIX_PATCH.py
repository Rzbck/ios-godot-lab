#!/usr/bin/env python3
'''Field-proven auto-pause stability + diagnostic observability patch.

Runs last in the generated source chain.

Session 1789494751175 on build da67fb38dce3 proved three production defects:
1. fused stillness did arm five auto-pause candidates, but partial sensor paths
   could still cancel the fused candidate independently;
2. derived GPS drift with no native speed (`location.speed == -1`) and ~20-25 m
   horizontal accuracy refreshed the movement-speed veto;
3. iPhone session persistence stamped Watch packets at receive time and the
   diagnostic `logs <session>` command ignored the durable session raw stream.

This patch gives one fused owner responsibility for auto-pause, adds hysteresis
to inertial stillness, accepts GPS as a pause movement veto only when its speed
evidence is trustworthy, preserves Watch source timestamps, and exposes compact
session-raw diagnostics through the existing read-only `logs` API.
'''
from pathlib import Path

ROOT = Path(__file__).resolve().parent
WATCH = ROOT / "watch/Sources/SensorModel.swift"
POLICY = ROOT / "Shared/TrackerAutoPauseStabilityPolicy.swift"
IPHONE = ROOT / "iphone/Sources/TrackerModel.swift"
STORE = ROOT / "iphone/Sources/SessionStore.swift"
DIAG = ROOT / "iphone/Sources/DiagnosticService.swift"
TESTS = ROOT / "Tests/TrackerAutoPauseStabilityPolicyTests.swift"


def replace_once_or_present(text: str, old: str, new: str, marker: str, label: str) -> str:
    if marker in text:
        return text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, got {count}")
    return text.replace(old, new, 1)


watch = WATCH.read_text(encoding="utf-8")
policy = POLICY.read_text(encoding="utf-8")
iphone = IPHONE.read_text(encoding="utf-8")
store = STORE.read_text(encoding="utf-8")
diag = DIAG.read_text(encoding="utf-8")
tests = TESTS.read_text(encoding="utf-8")

# ---------------------------------------------------------------------------
# Shared policy: make inertial stillness stateful and reject GPS drift as a
# fresh movement veto when neither native speed nor displacement is trustworthy.
# ---------------------------------------------------------------------------
policy = replace_once_or_present(
    policy,
    '''    static let minimumQuietFraction = 0.80
    static let minimumSamples = 8
''',
    '''    static let minimumQuietFraction = 0.80
    static let minimumQuietFractionToRemainStill = 0.60 // AUTO_PAUSE_INERTIAL_HYSTERESIS_POLICY
    static let minimumSamples = 8
''',
    "// AUTO_PAUSE_INERTIAL_HYSTERESIS_POLICY",
    "inertial hysteresis threshold",
)

policy = replace_once_or_present(
    policy,
    '''    static func isStill(
        windowCoverage: TimeInterval,
        quietSamples: Int,
        totalSamples: Int
    ) -> Bool {
        guard windowCoverage >= minimumCoverage,
              totalSamples >= minimumSamples,
              quietSamples >= 0,
              quietSamples <= totalSamples else { return false }

        return Double(quietSamples) / Double(totalSamples) >= minimumQuietFraction
    }
}
''',
    '''    static func isStill(
        windowCoverage: TimeInterval,
        quietSamples: Int,
        totalSamples: Int
    ) -> Bool {
        nextStillState(
            previouslyStill: false,
            windowCoverage: windowCoverage,
            quietSamples: quietSamples,
            totalSamples: totalSamples
        )
    }

    static func nextStillState( // AUTO_PAUSE_INERTIAL_HYSTERESIS_TRANSITION
        previouslyStill: Bool,
        windowCoverage: TimeInterval,
        quietSamples: Int,
        totalSamples: Int
    ) -> Bool {
        guard windowCoverage >= minimumCoverage,
              totalSamples >= minimumSamples,
              quietSamples >= 0,
              quietSamples <= totalSamples else { return false }

        let quietFraction = Double(quietSamples) / Double(totalSamples)
        let threshold = previouslyStill
            ? minimumQuietFractionToRemainStill
            : minimumQuietFraction
        return quietFraction >= threshold
    }
}

extension TrackerAutoPauseStabilityPolicy {
    static func speedSampleIsReliableForMovementVeto( // AUTO_PAUSE_RELIABLE_SPEED_POLICY
        nativeSpeedMps: Double,
        speedAccuracyMps: Double,
        deltaMeters: Double,
        previousHorizontalAccuracyMeters: Double,
        horizontalAccuracyMeters: Double
    ) -> Bool {
        let nativeSpeedReliable =
            nativeSpeedMps >= 0
            && speedAccuracyMps >= 0
            && speedAccuracyMps <= 1.5

        if nativeSpeedReliable {
            return true
        }

        guard deltaMeters >= 0,
              previousHorizontalAccuracyMeters >= 0,
              horizontalAccuracyMeters >= 0 else {
            return false
        }

        let uncertaintyBudget =
            0.5
            * (
                previousHorizontalAccuracyMeters
                + horizontalAccuracyMeters
            )

        return deltaMeters >= max(8.0, uncertaintyBudget)
    }
}
''',
    "// AUTO_PAUSE_RELIABLE_SPEED_POLICY",
    "reliable auto-pause speed policy",
)

# ---------------------------------------------------------------------------
# Watch runtime: one fused decision owner, inertial hysteresis, reliable GPS
# freshness, and compact decision telemetry.
# ---------------------------------------------------------------------------
watch = replace_once_or_present(
    watch,
    '''    private var inertialAutoPauseQuietFraction = 0.0
''',
    '''    private var inertialAutoPauseQuietFraction = 0.0
    private var lastAutoPauseEvaluationSend = Date.distantPast // AUTO_PAUSE_EVALUATION_TELEMETRY_STATE
''',
    "// AUTO_PAUSE_EVALUATION_TELEMETRY_STATE",
    "watch auto-pause evaluation telemetry state",
)

watch = replace_once_or_present(
    watch,
    '''            inertialAutoPauseStill = false
            inertialAutoPauseQuietFraction = 0
            resetPresentationData(keepActivity: true)
''',
    '''            inertialAutoPauseStill = false
            inertialAutoPauseQuietFraction = 0
            lastAutoPauseEvaluationSend = .distantPast // AUTO_PAUSE_RESET_EVALUATION_TELEMETRY
            resetPresentationData(keepActivity: true)
''',
    "// AUTO_PAUSE_RESET_EVALUATION_TELEMETRY",
    "watch reset auto-pause evaluation telemetry",
)

watch = replace_once_or_present(
    watch,
    '''        inertialAutoPauseStill = TrackerInertialStillnessPolicy.isStill(
            windowCoverage: now.timeIntervalSince(first.at),
            quietSamples: quietCount,
            totalSamples: totalCount
        )
''',
    '''        inertialAutoPauseStill = TrackerInertialStillnessPolicy.nextStillState( // AUTO_PAUSE_INERTIAL_HYSTERESIS_RUNTIME
            previouslyStill: inertialAutoPauseStill,
            windowCoverage: now.timeIntervalSince(first.at),
            quietSamples: quietCount,
            totalSamples: totalCount
        )
''',
    "// AUTO_PAUSE_INERTIAL_HYSTERESIS_RUNTIME",
    "watch inertial stillness hysteresis",
)

watch = replace_once_or_present(
    watch,
    '''                } else if self.phase == .active {
                    if WatchAutoPolicy.shouldStagePause(
                        activity: self.displayActivity,
                        stationary: false,
                        speedMps: self.currentSpeedMps,
                        cadenceSPM: self.freshCadenceSPM
                    ) {
                        self.stageAutoPauseIfNeeded()
                    } else {
                        self.cancelPendingAutoPause()
                    }
                }
''',
    '''                } else if self.phase == .active {
                    // AUTO_PAUSE_SINGLE_FUSED_DECISION_OWNER
                    self.stageAutoPauseIfNeeded()
                }
''',
    "// AUTO_PAUSE_SINGLE_FUSED_DECISION_OWNER",
    "watch Core Motion must not bypass fused pause ownership",
)

watch = replace_once_or_present(
    watch,
    '''                lastAutoPauseSpeedEvidenceAt = location.timestamp // AUTO_PAUSE_SPEED_EVIDENCE_MOVING
''',
    '''                if TrackerAutoPauseStabilityPolicy.speedSampleIsReliableForMovementVeto( // AUTO_PAUSE_RELIABLE_MOVING_SPEED_STAMP
                    nativeSpeedMps: location.speed,
                    speedAccuracyMps: location.speedAccuracy,
                    deltaMeters: delta,
                    previousHorizontalAccuracyMeters: previous.horizontalAccuracy,
                    horizontalAccuracyMeters: location.horizontalAccuracy
                ) {
                    lastAutoPauseSpeedEvidenceAt = location.timestamp
                }
''',
    "// AUTO_PAUSE_RELIABLE_MOVING_SPEED_STAMP",
    "watch reliable moving speed freshness",
)

watch = replace_once_or_present(
    watch,
    '''                    lastAutoPauseSpeedEvidenceAt = location.timestamp // AUTO_PAUSE_SPEED_EVIDENCE_LOW_MOTION
''',
    '''                    if TrackerAutoPauseStabilityPolicy.speedSampleIsReliableForMovementVeto( // AUTO_PAUSE_RELIABLE_LOW_MOTION_SPEED_STAMP
                        nativeSpeedMps: location.speed,
                        speedAccuracyMps: location.speedAccuracy,
                        deltaMeters: delta,
                        previousHorizontalAccuracyMeters: previous.horizontalAccuracy,
                        horizontalAccuracyMeters: location.horizontalAccuracy
                    ) {
                        lastAutoPauseSpeedEvidenceAt = location.timestamp
                    }
''',
    "// AUTO_PAUSE_RELIABLE_LOW_MOTION_SPEED_STAMP",
    "watch reliable low-motion speed freshness",
)

watch = replace_once_or_present(
    watch,
    '''    private func stageAutoPauseIfNeeded() {
''',
    '''    private func autoPauseEvaluationReason(
        fusedStillness: Bool,
        speedFresh: Bool,
        cadenceSPM: Double
    ) -> String { // AUTO_PAUSE_EVALUATION_REASON
        guard TrackerAutoPauseStabilityPolicy.supports(displayActivity) else {
            return "unsupported_activity"
        }
        guard fusedStillness else {
            return "stillness_missing"
        }

        let speed = max(0, currentSpeedMps)
        let cadence = max(0, cadenceSPM)

        switch displayActivity {
        case .walking, .hiking:
            if speedFresh, speed > 0.35 { return "fresh_speed_veto" }
            if cadence >= 10 { return "cadence_veto" }
        case .running, .trackAndField:
            if speedFresh, speed > 0.45 { return "fresh_speed_veto" }
            if cadence >= 25 { return "cadence_veto" }
        case .cycling, .handCycling:
            if speedFresh, speed > 0.40 { return "fresh_speed_veto" }
        default:
            return "unsupported_activity"
        }

        return "candidate_allowed"
    }

    private func sendAutoPauseEvaluationIfNeeded(
        fusedStillness: Bool,
        shouldStage: Bool,
        reason: String,
        force: Bool = false
    ) { // AUTO_PAUSE_EVALUATION_SAMPLE
        let now = Date()
        guard force || now.timeIntervalSince(lastAutoPauseEvaluationSend) >= 2 else {
            return
        }
        lastAutoPauseEvaluationSend = now

        let cadenceAge = now.timeIntervalSince(lastCadenceEvidenceAt)
        let motionObservationAge =
            now.timeIntervalSince(lastAutoPauseMotionObservationAt)
        let inertialAge = now.timeIntervalSince(lastInertialAutoPauseSampleAt)
        let candidateAge = autoPauseCandidateSince.map {
            now.timeIntervalSince($0)
        } ?? -1

        sendSensorSample(
            kind: "auto_pause_evaluation",
            payload: [
                "activity": displayActivity.rawValue,
                "should_stage": shouldStage,
                "decision_reason": reason,
                "candidate_pending": autoPauseCandidateSince != nil,
                "candidate_age_s": candidateAge,
                "speed_mps": currentSpeedMps,
                "speed_fresh": autoPauseSpeedEvidenceFresh,
                "speed_age_s":
                    autoPauseSpeedEvidenceAge.isFinite
                        ? autoPauseSpeedEvidenceAge
                        : -1,
                "cadence_spm": freshCadenceSPM,
                "cadence_age_s":
                    cadenceAge.isFinite
                        ? cadenceAge
                        : -1,
                "fused_stillness": fusedStillness,
                "motion_stationary": freshAutoPauseMotionWasStationary,
                "motion_observation_age_s":
                    motionObservationAge.isFinite
                        ? motionObservationAge
                        : -1,
                "inertial_still": freshInertialAutoPauseStill,
                "inertial_quiet_fraction": inertialAutoPauseQuietFraction,
                "inertial_sample_age_s":
                    inertialAge.isFinite
                        ? inertialAge
                        : -1,
                "horizontal_accuracy_m": horizontalAccuracy,
            ],
            reliable: false
        )
    }

    private func stageAutoPauseIfNeeded() {
''',
    "// AUTO_PAUSE_EVALUATION_REASON",
    "watch auto-pause evaluation helpers",
)

watch = replace_once_or_present(
    watch,
    '''        guard WatchAutoPolicy.shouldStagePause(
            activity: displayActivity,
            stationary: freshAutoPauseMotionWasStationary || freshInertialAutoPauseStill, // AUTO_PAUSE_FUSED_STILLNESS_STAGE
            speedMps: currentSpeedMps,
            speedFresh: autoPauseSpeedEvidenceFresh,
            cadenceSPM: freshCadenceSPM
        ) else {
            cancelPendingAutoPause()
            return
        }
''',
    '''        let fusedStillness =
            freshAutoPauseMotionWasStationary
            || freshInertialAutoPauseStill
        let cadence = freshCadenceSPM
        let shouldStage = WatchAutoPolicy.shouldStagePause(
            activity: displayActivity,
            stationary: fusedStillness, // AUTO_PAUSE_FIELD_FUSED_STAGE
            speedMps: currentSpeedMps,
            speedFresh: autoPauseSpeedEvidenceFresh,
            cadenceSPM: cadence
        )
        let decisionReason = autoPauseEvaluationReason(
            fusedStillness: fusedStillness,
            speedFresh: autoPauseSpeedEvidenceFresh,
            cadenceSPM: cadence
        )
        sendAutoPauseEvaluationIfNeeded(
            fusedStillness: fusedStillness,
            shouldStage: shouldStage,
            reason: decisionReason
        )

        guard shouldStage else {
            if let candidateSince = autoPauseCandidateSince {
                sendEvent("auto_pause_cancelled", payload: [
                    "decision_reason": decisionReason,
                    "candidate_age_s": Date().timeIntervalSince(candidateSince),
                    "speed_mps": currentSpeedMps,
                    "speed_fresh": autoPauseSpeedEvidenceFresh,
                    "speed_age_s":
                        autoPauseSpeedEvidenceAge.isFinite
                            ? autoPauseSpeedEvidenceAge
                            : -1,
                    "cadence_spm": cadence,
                    "motion_stationary": freshAutoPauseMotionWasStationary,
                    "inertial_still": freshInertialAutoPauseStill,
                    "inertial_quiet_fraction": inertialAutoPauseQuietFraction,
                    "horizontal_accuracy_m": horizontalAccuracy,
                ])
            }
            cancelPendingAutoPause()
            return
        }
''',
    "// AUTO_PAUSE_FIELD_FUSED_STAGE",
    "watch field-proven fused pause stage",
)

watch = replace_once_or_present(
    watch,
    '''        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.phase == .active, self.autoPauseEnabled,
                  self.autoPauseToken == token,
                  WatchAutoPolicy.shouldStagePause(
                    activity: self.displayActivity,
                    stationary: self.freshAutoPauseMotionWasStationary || self.freshInertialAutoPauseStill, // AUTO_PAUSE_FUSED_STILLNESS_CONFIRM
                    speedMps: self.currentSpeedMps,
                    speedFresh: self.autoPauseSpeedEvidenceFresh,
                    cadenceSPM: self.freshCadenceSPM
                  ) else { return }
            self.autoPauseCandidateSince = nil
''',
    '''        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self,
                  self.phase == .active,
                  self.autoPauseEnabled,
                  self.autoPauseToken == token else {
                return
            }

            let fusedStillness =
                self.freshAutoPauseMotionWasStationary
                || self.freshInertialAutoPauseStill
            let cadence = self.freshCadenceSPM
            let confirmed = WatchAutoPolicy.shouldStagePause(
                activity: self.displayActivity,
                stationary: fusedStillness, // AUTO_PAUSE_FIELD_FUSED_CONFIRM
                speedMps: self.currentSpeedMps,
                speedFresh: self.autoPauseSpeedEvidenceFresh,
                cadenceSPM: cadence
            )
            let decisionReason = self.autoPauseEvaluationReason(
                fusedStillness: fusedStillness,
                speedFresh: self.autoPauseSpeedEvidenceFresh,
                cadenceSPM: cadence
            )
            self.sendAutoPauseEvaluationIfNeeded(
                fusedStillness: fusedStillness,
                shouldStage: confirmed,
                reason: decisionReason,
                force: true
            )

            guard confirmed else {
                self.sendEvent("auto_pause_confirmation_failed", payload: [
                    "decision_reason": decisionReason,
                    "speed_mps": self.currentSpeedMps,
                    "speed_fresh": self.autoPauseSpeedEvidenceFresh,
                    "speed_age_s":
                        self.autoPauseSpeedEvidenceAge.isFinite
                            ? self.autoPauseSpeedEvidenceAge
                            : -1,
                    "cadence_spm": cadence,
                    "motion_stationary":
                        self.freshAutoPauseMotionWasStationary,
                    "inertial_still":
                        self.freshInertialAutoPauseStill,
                    "inertial_quiet_fraction":
                        self.inertialAutoPauseQuietFraction,
                    "horizontal_accuracy_m":
                        self.horizontalAccuracy,
                ])
                self.cancelPendingAutoPause()
                return
            }

            self.autoPauseCandidateSince = nil
''',
    "// AUTO_PAUSE_FIELD_FUSED_CONFIRM",
    "watch field-proven fused pause confirmation",
)

# ---------------------------------------------------------------------------
# iPhone durable session telemetry: preserve Watch packet time rather than
# rewriting every record to iPhone receive time.
# ---------------------------------------------------------------------------
store = replace_once_or_present(
    store,
    '''    func appendSample(source: String, kind: String, payload: [String: Any], quality: [String: Any] = [:]) {
        guard fileHandle != nil else { return }
        append([
            "record": "sample",
            "schema": Self.currentSchema,
            "session_id": sessionID,
            "timestamp": Date().timeIntervalSince1970,
            "source": source,
            "kind": kind,
            "payload": payload,
            "quality": quality,
        ])
    }

    func appendEvent(_ name: String, source: String, payload: [String: Any] = [:]) {
        guard fileHandle != nil else { return }
        append([
            "record": "event",
            "schema": Self.currentSchema,
            "session_id": sessionID,
            "timestamp": Date().timeIntervalSince1970,
            "source": source,
            "event": name,
            "payload": payload,
        ])
    }
''',
    '''    func appendSample(
        source: String,
        kind: String,
        payload: [String: Any],
        quality: [String: Any] = [:],
        timestamp: TimeInterval? = nil
    ) { // SESSION_RAW_SOURCE_TIMESTAMP
        guard fileHandle != nil else { return }
        let receivedTimestamp = Date().timeIntervalSince1970
        var record: [String: Any] = [
            "record": "sample",
            "schema": Self.currentSchema,
            "session_id": sessionID,
            "timestamp": timestamp ?? receivedTimestamp,
            "source": source,
            "kind": kind,
            "payload": payload,
            "quality": quality,
        ]
        if let timestamp {
            record["received_timestamp"] = receivedTimestamp
            record["transport_latency_s"] =
                max(0, receivedTimestamp - timestamp)
        }
        append(record)
    }

    func appendEvent(
        _ name: String,
        source: String,
        payload: [String: Any] = [:],
        timestamp: TimeInterval? = nil
    ) {
        guard fileHandle != nil else { return }
        let receivedTimestamp = Date().timeIntervalSince1970
        var record: [String: Any] = [
            "record": "event",
            "schema": Self.currentSchema,
            "session_id": sessionID,
            "timestamp": timestamp ?? receivedTimestamp,
            "source": source,
            "event": name,
            "payload": payload,
        ]
        if let timestamp {
            record["received_timestamp"] = receivedTimestamp
            record["transport_latency_s"] =
                max(0, receivedTimestamp - timestamp)
        }
        append(record)
    }
''',
    "// SESSION_RAW_SOURCE_TIMESTAMP",
    "session store source timestamp preservation",
)

store = replace_once_or_present(
    store,
    '''    func finish(summary: TrackerSummary) {
''',
    '''    func diagnosticRecords( // SESSION_RAW_DIAGNOSTIC_READER
        sessionID targetSessionID: String,
        limit: Int,
        kind: String? = nil
    ) -> [[String: Any]] {
        guard !targetSessionID.isEmpty else { return [] }

        if targetSessionID == sessionID {
            fileHandle?.synchronizeFile()
        }

        guard let root = try? sessionsRoot(create: false) else {
            return []
        }
        let url = root
            .appendingPathComponent(targetSessionID, isDirectory: true)
            .appendingPathComponent("samples.jsonl")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        let formatter = ISO8601DateFormatter()
        var records: [[String: Any]] = []

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = String(line).data(using: .utf8),
                  let raw = try? JSONSerialization.jsonObject(with: data)
                    as? [String: Any],
                  let recordType = raw["record"] as? String else {
                continue
            }

            let source = raw["source"] as? String ?? "iphone"
            let sampleKind = raw["kind"] as? String
            let eventName = raw["event"] as? String

            if let kind {
                let matches =
                    kind == recordType
                    || kind == sampleKind
                    || kind == eventName
                if !matches { continue }
            } else if recordType == "sample", sampleKind == "motion" {
                continue
            }

            let timestamp =
                (raw["timestamp"] as? NSNumber)?.doubleValue
                ?? Date().timeIntervalSince1970
            var fields =
                raw["payload"] as? [String: Any]
                ?? raw["metadata"] as? [String: Any]
                ?? raw["summary"] as? [String: Any]
                ?? [:]

            if let received =
                (raw["received_timestamp"] as? NSNumber)?.doubleValue {
                fields["received_timestamp"] = received
            }
            if let latency =
                (raw["transport_latency_s"] as? NSNumber)?.doubleValue {
                fields["transport_latency_s"] = latency
            }

            records.append([
                "timestamp": formatter.string(
                    from: Date(timeIntervalSince1970: timestamp)
                ),
                "platform": source,
                "kind": recordType == "event" ? "event" : "sample",
                "name": eventName ?? sampleKind ?? recordType,
                "screen": NSNull(),
                "fields": fields,
            ])
        }

        let safeLimit = min(200, max(1, limit))
        return Array(records.suffix(safeLimit).reversed())
    }

    func finish(summary: TrackerSummary) {
''',
    "// SESSION_RAW_DIAGNOSTIC_READER",
    "session store diagnostic raw reader",
)

iphone = replace_once_or_present(
    iphone,
    '''    private func requestControl(
''',
    '''    func diagnosticSessionRecords(
        sessionID: String,
        limit: Int,
        kind: String?
    ) -> [[String: Any]] { // SESSION_RAW_DIAGNOSTIC_BRIDGE
        store.diagnosticRecords(
            sessionID: sessionID,
            limit: limit,
            kind: kind
        )
    }

    private func requestControl(
''',
    "// SESSION_RAW_DIAGNOSTIC_BRIDGE",
    "tracker session raw diagnostic bridge",
)

iphone = replace_once_or_present(
    iphone,
    '''        if payload["type"] as? String == "sensor_sample",
           let source = payload["source"] as? String,
           let kind = payload["kind"] as? String,
           let sample = payload["payload"] as? [String: Any] {

            DispatchQueue.main.async { [weak self] in
''',
    '''        if payload["type"] as? String == "sensor_sample",
           let source = payload["source"] as? String,
           let kind = payload["kind"] as? String,
           let sample = payload["payload"] as? [String: Any] {

            let sourceTimestamp =
                (payload["timestamp"] as? NSNumber)?.doubleValue // WATCH_PACKET_SOURCE_TIMESTAMP

            DispatchQueue.main.async { [weak self] in
''',
    "// WATCH_PACKET_SOURCE_TIMESTAMP",
    "iphone capture Watch packet source timestamp",
)

iphone = replace_once_or_present(
    iphone,
    '''                    self.store.appendEvent(
                        name,
                        source: source,
                        payload: eventPayload
                    )
                } else {
                    self.store.appendSample(
                        source: source,
                        kind: kind,
                        payload: sample
                    )
''',
    '''                    self.store.appendEvent(
                        name,
                        source: source,
                        payload: eventPayload,
                        timestamp: sourceTimestamp // WATCH_EVENT_SOURCE_TIMESTAMP
                    )
                } else {
                    self.store.appendSample(
                        source: source,
                        kind: kind,
                        payload: sample,
                        timestamp: sourceTimestamp // WATCH_SAMPLE_SOURCE_TIMESTAMP
                    )
''',
    "// WATCH_EVENT_SOURCE_TIMESTAMP",
    "iphone persist Watch source timestamp",
)

diag = replace_once_or_present(
    diag,
    '''        case "logs":
            let kind = request["kind"] as? String
            return envelope(
                ok: true,
                command: command,
                data: [
                    "records": recentTelemetry(limit: limit, kind: kind),
                    "limit": limit,
                    "kind": kind.map { $0 as Any } ?? NSNull(),
                ]
            )
''',
    '''        case "logs":
            let kind = request["kind"] as? String

            if let sessionID = request["session_id"] as? String,
               !sessionID.isEmpty {
                guard let tracker else {
                    return envelope(
                        ok: false,
                        command: command,
                        error: "tracker_not_ready"
                    )
                }

                return envelope(
                    ok: true,
                    command: command,
                    data: [
                        "records": tracker.diagnosticSessionRecords(
                            sessionID: sessionID,
                            limit: limit,
                            kind: kind
                        ),
                        "limit": limit,
                        "kind": kind.map { $0 as Any } ?? NSNull(),
                        "session_id": sessionID,
                        "source": "session_raw", // DIAGNOSTIC_SESSION_RAW_LOGS
                        "source_timestamp_preserved": true,
                        "motion_excluded_by_default": kind == nil,
                    ]
                )
            }

            return envelope(
                ok: true,
                command: command,
                data: [
                    "records": recentTelemetry(limit: limit, kind: kind),
                    "limit": limit,
                    "kind": kind.map { $0 as Any } ?? NSNull(),
                    "source": "app_telemetry",
                ]
            )
''',
    "// DIAGNOSTIC_SESSION_RAW_LOGS",
    "diagnostic logs must honor session_id",
)

tests = replace_once_or_present(
    tests,
    '''    func testAutomaticHealthKitPlaceholderIsWalkingNotMixedCardio() {
''',
    '''    func testInertialStillnessHysteresisPreventsBoundaryFlapping() { // FIELD_1789494751175_INERTIAL_HYSTERESIS
        XCTAssertTrue(
            TrackerInertialStillnessPolicy.nextStillState(
                previouslyStill: false,
                windowCoverage: 2.8,
                quietSamples: 12,
                totalSamples: 14
            )
        )
        XCTAssertTrue(
            TrackerInertialStillnessPolicy.nextStillState(
                previouslyStill: true,
                windowCoverage: 2.8,
                quietSamples: 9,
                totalSamples: 14
            )
        )
        XCTAssertFalse(
            TrackerInertialStillnessPolicy.nextStillState(
                previouslyStill: false,
                windowCoverage: 2.8,
                quietSamples: 9,
                totalSamples: 14
            )
        )
        XCTAssertFalse(
            TrackerInertialStillnessPolicy.nextStillState(
                previouslyStill: true,
                windowCoverage: 2.8,
                quietSamples: 8,
                totalSamples: 14
            )
        )
    }

    func testFieldStoppedPoorAccuracyDerivedGPSDoesNotRefreshMovementVeto() {
        XCTAssertFalse(
            TrackerAutoPauseStabilityPolicy.speedSampleIsReliableForMovementVeto(
                nativeSpeedMps: -1,
                speedAccuracyMps: -1,
                deltaMeters: 4.878073063048958,
                previousHorizontalAccuracyMeters: 21.80178731265691,
                horizontalAccuracyMeters: 20.28836092707818
            )
        )
    }

    func testReliableNativeSpeedStillRefreshesMovementVeto() {
        XCTAssertTrue(
            TrackerAutoPauseStabilityPolicy.speedSampleIsReliableForMovementVeto(
                nativeSpeedMps: 1.2,
                speedAccuracyMps: 0.4,
                deltaMeters: 2,
                previousHorizontalAccuracyMeters: 20,
                horizontalAccuracyMeters: 20
            )
        )
    }

    func testLargeDerivedDisplacementCanStillRefreshMovementVeto() {
        XCTAssertTrue(
            TrackerAutoPauseStabilityPolicy.speedSampleIsReliableForMovementVeto(
                nativeSpeedMps: -1,
                speedAccuracyMps: -1,
                deltaMeters: 30,
                previousHorizontalAccuracyMeters: 20,
                horizontalAccuracyMeters: 20
            )
        )
    }

    func testAutomaticHealthKitPlaceholderIsWalkingNotMixedCardio() {
''',
    "// FIELD_1789494751175_INERTIAL_HYSTERESIS",
    "field auto-pause regression tests",
)

files = {
    "watch": watch,
    "policy": policy,
    "iphone": iphone,
    "store": store,
    "diag": diag,
    "tests": tests,
}

markers = {
    "watch": [
        "// AUTO_PAUSE_EVALUATION_TELEMETRY_STATE",
        "// AUTO_PAUSE_RESET_EVALUATION_TELEMETRY",
        "// AUTO_PAUSE_INERTIAL_HYSTERESIS_RUNTIME",
        "// AUTO_PAUSE_SINGLE_FUSED_DECISION_OWNER",
        "// AUTO_PAUSE_RELIABLE_MOVING_SPEED_STAMP",
        "// AUTO_PAUSE_RELIABLE_LOW_MOTION_SPEED_STAMP",
        "// AUTO_PAUSE_EVALUATION_REASON",
        "// AUTO_PAUSE_EVALUATION_SAMPLE",
        "// AUTO_PAUSE_FIELD_FUSED_STAGE",
        "// AUTO_PAUSE_FIELD_FUSED_CONFIRM",
    ],
    "policy": [
        "// AUTO_PAUSE_INERTIAL_HYSTERESIS_POLICY",
        "// AUTO_PAUSE_INERTIAL_HYSTERESIS_TRANSITION",
        "// AUTO_PAUSE_RELIABLE_SPEED_POLICY",
    ],
    "iphone": [
        "// SESSION_RAW_DIAGNOSTIC_BRIDGE",
        "// WATCH_PACKET_SOURCE_TIMESTAMP",
        "// WATCH_EVENT_SOURCE_TIMESTAMP",
        "// WATCH_SAMPLE_SOURCE_TIMESTAMP",
    ],
    "store": [
        "// SESSION_RAW_SOURCE_TIMESTAMP",
        "// SESSION_RAW_DIAGNOSTIC_READER",
    ],
    "diag": [
        "// DIAGNOSTIC_SESSION_RAW_LOGS",
    ],
    "tests": [
        "// FIELD_1789494751175_INERTIAL_HYSTERESIS",
    ],
}

for name, required in markers.items():
    text = files[name]
    for marker in required:
        count = text.count(marker)
        if count != 1:
            raise SystemExit(
                f"{name}: expected marker exactly once: {marker!r}, got {count}"
            )

POLICY.write_text(policy, encoding="utf-8")
WATCH.write_text(watch, encoding="utf-8")
IPHONE.write_text(iphone, encoding="utf-8")
STORE.write_text(store, encoding="utf-8")
DIAG.write_text(diag, encoding="utf-8")
TESTS.write_text(tests, encoding="utf-8")

print("AUTO PAUSE FIELD FIX + SESSION RAW DIAGNOSTICS PATCH: OK")
