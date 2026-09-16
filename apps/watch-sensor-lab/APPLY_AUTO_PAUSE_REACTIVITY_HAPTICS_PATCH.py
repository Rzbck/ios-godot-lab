#!/usr/bin/env python3
"""Field-driven Watch auto-pause reactivity + haptic feedback patch.

Based on physical session 1789537681642 from build
37fe5226d3eea6f5c8a4efa9b9878bb3a4b8cdbb.

Goals:
- use fresh step progression as movement evidence for foot locomotion so slow
  walking cannot be paused merely because currentCadence temporarily disappears;
- reject delayed CMPedometer callbacks whose native endDate belongs to the
  pre-pause active phase;
- allow a sustained post-pause step progression to resume walking/running/neutral
  Auto without waiting for currentCadence, while never using step evidence as a
  cycling cadence signal;
- reduce neutral/walking pause dwell from 6 s to 4 s after adding the new step
  veto; cycling/running already use a 4 s dwell;
- play local Watch haptics only after a confirmed automatic pause/resume.

The patch runs after the existing fusion/field/neutral-start patches and is
idempotent/fail-closed.
"""
from pathlib import Path


ROOT = Path(__file__).resolve().parent
POLICY = ROOT / "Shared/TrackerAutoPolicy.swift"
STABILITY = ROOT / "Shared/TrackerAutoPauseStabilityPolicy.swift"
WATCH = ROOT / "watch/Sources/SensorModel.swift"
AUTO_TESTS = ROOT / "Tests/TrackerAutoPolicyTests.swift"
STABILITY_TESTS = ROOT / "Tests/TrackerAutoPauseStabilityPolicyTests.swift"


def replace_once_or_present(text: str, old: str, new: str, marker: str, label: str) -> str:
    if marker in text:
        return text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, got {count}")
    return text.replace(old, new, 1)


policy = POLICY.read_text(encoding="utf-8")
stability = STABILITY.read_text(encoding="utf-8")
watch = WATCH.read_text(encoding="utf-8")
auto_tests = AUTO_TESTS.read_text(encoding="utf-8")
stability_tests = STABILITY_TESTS.read_text(encoding="utf-8")

# ---------------------------------------------------------------------------
# Shared deterministic policy: foot-step evidence is valid for Auto/walk/run,
# never as a bicycle cadence signal.
# ---------------------------------------------------------------------------
policy = replace_once_or_present(
    policy,
    '''enum TrackerAutoPolicy {\n    static func decision(\n''',
    '''enum TrackerAutoPolicy {\n    static let footStepPauseFreshness: TimeInterval = 3.0 // AUTO_PAUSE_FOOT_STEP_POLICY\n    static let footStepResumeFreshness: TimeInterval = 2.5\n    static let footStepResumeProgressions = 2\n\n    static func usesFootStepEvidence(_ activity: ActivityKind) -> Bool {\n        switch activity {\n        case .automatic, .walking, .hiking, .running, .trackAndField:\n            return true\n        case .cycling, .handCycling:\n            return false\n        default:\n            return false\n        }\n    }\n\n    static func freshStepMovementEvidence(\n        activity: ActivityKind,\n        ageSeconds: TimeInterval\n    ) -> Bool {\n        guard usesFootStepEvidence(activity), ageSeconds >= 0 else { return false }\n        return ageSeconds <= footStepPauseFreshness\n    }\n\n    static func canResumeFromSustainedStepProgression(\n        activity: ActivityKind,\n        ageSeconds: TimeInterval,\n        progressionCount: Int\n    ) -> Bool {\n        guard usesFootStepEvidence(activity), ageSeconds >= 0 else { return false }\n        return ageSeconds <= footStepResumeFreshness\n            && progressionCount >= footStepResumeProgressions\n    }\n\n    static func decision(\n''',
    "// AUTO_PAUSE_FOOT_STEP_POLICY",
    "foot-step movement policy",
)

# After a fresh-step veto exists, neutral Auto/walking can use the same 4 s dwell
# already used by running and cycling.
stability = replace_once_or_present(
    stability,
    '''    static func pauseDwell(for activity: ActivityKind) -> TimeInterval {\n        switch activity {\n        case .automatic, .walking, .hiking:\n            return 6.0\n''',
    '''    static func pauseDwell(for activity: ActivityKind) -> TimeInterval {\n        switch activity {\n        case .automatic, .walking, .hiking:\n            return 4.0 // AUTO_PAUSE_REACTIVE_FOOT_DWELL\n''',
    "// AUTO_PAUSE_REACTIVE_FOOT_DWELL",
    "reactive neutral/walking dwell",
)

# ---------------------------------------------------------------------------
# Watch runtime state and local haptics.
# ---------------------------------------------------------------------------
watch = replace_once_or_present(
    watch,
    "import WatchConnectivity\n",
    "import WatchConnectivity\nimport WatchKit // AUTO_PAUSE_LOCAL_HAPTICS_IMPORT\n",
    "// AUTO_PAUSE_LOCAL_HAPTICS_IMPORT",
    "WatchKit import for local haptics",
)

watch = replace_once_or_present(
    watch,
    '''    private var lastAutoResumeAt = Date.distantPast // AUTO_RESUME_REPAUSE_HYSTERESIS_STATE\n''',
    '''    private var lastAutoResumeAt = Date.distantPast // AUTO_RESUME_REPAUSE_HYSTERESIS_STATE\n    private var lastAutoPauseConfirmedAt = Date.distantPast // AUTO_PAUSE_STEP_BOUNDARY_STATE\n    private var lastStepMovementEvidenceAt = Date.distantPast\n    private var autoResumeProbeLastStepCount: Int?\n    private var autoResumeProbeStepProgressions = 0\n    private var lastAutoResumeStepEvidenceAt = Date.distantPast\n''',
    "// AUTO_PAUSE_STEP_BOUNDARY_STATE",
    "step/haptic runtime state",
)

watch = replace_once_or_present(
    watch,
    '''            lastAutoResumeAt = .distantPast // AUTO_RESUME_RESET_REPAUSE_HYSTERESIS\n''',
    '''            lastAutoResumeAt = .distantPast // AUTO_RESUME_RESET_REPAUSE_HYSTERESIS\n            lastAutoPauseConfirmedAt = .distantPast // AUTO_PAUSE_RESET_STEP_BOUNDARY\n            lastStepMovementEvidenceAt = .distantPast\n            autoResumeProbeLastStepCount = nil\n            autoResumeProbeStepProgressions = 0\n            lastAutoResumeStepEvidenceAt = .distantPast\n''',
    "// AUTO_PAUSE_RESET_STEP_BOUNDARY",
    "reset step evidence per workout",
)

watch = replace_once_or_present(
    watch,
    '''    private var freshCadenceSPM: Double {\n        Date().timeIntervalSince(lastCadenceEvidenceAt) <= autoEvidenceFreshness ? cadenceSPM : 0\n    }\n''',
    '''    private var freshCadenceSPM: Double {\n        Date().timeIntervalSince(lastCadenceEvidenceAt) <= autoEvidenceFreshness ? cadenceSPM : 0\n    }\n\n    private var freshStepMovementEvidence: Bool { // AUTO_PAUSE_FRESH_STEP_EVIDENCE\n        let age = Date().timeIntervalSince(lastStepMovementEvidenceAt)\n        return TrackerAutoPolicy.freshStepMovementEvidence(\n            activity: displayActivity,\n            ageSeconds: age\n        )\n    }\n\n    private var autoResumeStepEvidenceAge: TimeInterval {\n        Date().timeIntervalSince(lastAutoResumeStepEvidenceAt)\n    }\n\n    private var autoResumeStepEvidenceReady: Bool {\n        TrackerAutoPolicy.canResumeFromSustainedStepProgression(\n            activity: displayActivity,\n            ageSeconds: autoResumeStepEvidenceAge,\n            progressionCount: autoResumeProbeStepProgressions\n        )\n    }\n''',
    "// AUTO_PAUSE_FRESH_STEP_EVIDENCE",
    "computed fresh step evidence",
)

watch = replace_once_or_present(
    watch,
    '''    private func pauseCore(reason: String) {\n''',
    '''    private func playAutoTransitionHaptic(\n        _ type: WKHapticType,\n        transition: String\n    ) { // AUTO_PAUSE_CONFIRMED_HAPTICS\n        WKInterfaceDevice.current().play(type)\n        sendEvent("auto_transition_haptic", payload: [\n            "transition": transition,\n            "haptic": transition == "pause" ? "stop" : "start",\n            "confirmed": true,\n        ])\n    }\n\n    private func pauseCore(reason: String) {\n''',
    "// AUTO_PAUSE_CONFIRMED_HAPTICS",
    "confirmed auto-transition haptic helper",
)

watch = replace_once_or_present(
    watch,
    '''    private func pauseCore(reason: String) {\n        guard phase == .active else { return }\n''',
    '''    private func pauseCore(reason: String) {\n        guard phase == .active else { return }\n        if reason == "auto" { // AUTO_PAUSE_STAMP_NATIVE_BOUNDARY\n            lastAutoPauseConfirmedAt = Date()\n            autoResumeProbeLastStepCount = nil\n            autoResumeProbeStepProgressions = 0\n            lastAutoResumeStepEvidenceAt = .distantPast\n        }\n''',
    "// AUTO_PAUSE_STAMP_NATIVE_BOUNDARY",
    "stamp native pause boundary",
)

watch = replace_once_or_present(
    watch,
    '''            "decision_reason": reason == "auto" ? "pause_policy_confirmed" : "manual",\n        ])\n''',
    '''            "decision_reason": reason == "auto" ? "pause_policy_confirmed" : "manual",\n        ])\n        if reason == "auto" {\n            playAutoTransitionHaptic(.stop, transition: "pause") // AUTO_PAUSE_STOP_HAPTIC\n        }\n''',
    "// AUTO_PAUSE_STOP_HAPTIC",
    "auto pause haptic",
)

watch = replace_once_or_present(
    watch,
    '''            "decision_reason": reason == "auto" ? lastAutoResumeDecisionReason : "manual",\n        ])\n''',
    '''            "decision_reason": reason == "auto" ? lastAutoResumeDecisionReason : "manual",\n        ])\n        if reason == "auto" {\n            playAutoTransitionHaptic(.start, transition: "resume") // AUTO_RESUME_START_HAPTIC\n            autoResumeProbeLastStepCount = nil\n            autoResumeProbeStepProgressions = 0\n            lastAutoResumeStepEvidenceAt = .distantPast\n        }\n''',
    "// AUTO_RESUME_START_HAPTIC",
    "auto resume haptic",
)

# ---------------------------------------------------------------------------
# CMPedometer native timestamps + sustained step progression.
# ---------------------------------------------------------------------------
watch = replace_once_or_present(
    watch,
    '''                guard let data else { return }\n                let sampleCadenceSPM = max(0, (data.currentCadence?.doubleValue ?? 0) * 60)\n\n                if self.phase == .paused, self.autoPaused {\n                    // AUTO_RESUME_PEDOMETER_PROBE_ONLY\n                    self.cadenceSPM = sampleCadenceSPM\n                    self.lastCadenceEvidenceAt = data.endDate\n                    var payload: [String: Any] = [\n                        "probe_steps": data.numberOfSteps.intValue,\n                        "canonical_steps": self.steps,\n                        "canonical_steps_unchanged": true,\n                    ]\n                    if sampleCadenceSPM > 0 { payload["cadence_spm"] = sampleCadenceSPM }\n                    if let pace = data.currentPace?.doubleValue { payload["pace_s_per_m"] = pace }\n                    self.sendSensorSample(\n                        kind: "auto_resume_probe_pedometer",\n                        payload: payload,\n                        reliable: false\n                    )\n                    self.stageAutoResumeIfNeeded()\n                    return\n                }\n\n                self.steps = self.pedometerBaseSteps + data.numberOfSteps.intValue\n                self.cadenceSPM = sampleCadenceSPM\n                // A delayed CMPedometer callback must not make an old cadence\n                // look fresh after an auto-pause.\n                self.lastCadenceEvidenceAt = data.endDate\n                var payload: [String: Any] = ["steps": self.steps]\n                if self.cadenceSPM > 0 { payload["cadence_spm"] = self.cadenceSPM }\n                if let pace = data.currentPace?.doubleValue { payload["pace_s_per_m"] = pace }\n                self.reevaluateAutomaticActivityFromLiveSensors()\n                self.sendSensorSample(kind: "pedometer", payload: payload, reliable: false)\n''',
    '''                guard let data else { return }\n                let sampleCadenceSPM = max(0, (data.currentCadence?.doubleValue ?? 0) * 60)\n                let sampleEndDate = data.endDate\n\n                if self.phase == .paused, self.autoPaused {\n                    // Never let a delayed active-phase sample wake the paused workout.\n                    guard sampleEndDate > self.lastAutoPauseConfirmedAt else {\n                        self.sendSensorSample(\n                            kind: "auto_resume_probe_pedometer_rejected", // AUTO_RESUME_REJECT_PREPAUSE_PEDOMETER\n                            payload: [\n                                "reason": "pre_pause_sample",\n                                "sample_end_timestamp": sampleEndDate.timeIntervalSince1970,\n                                "pause_boundary_timestamp": self.lastAutoPauseConfirmedAt.timeIntervalSince1970,\n                                "probe_steps": data.numberOfSteps.intValue,\n                                "cadence_spm": sampleCadenceSPM,\n                            ],\n                            reliable: false\n                        )\n                        return\n                    }\n\n                    let rawProbeSteps = data.numberOfSteps.intValue\n                    if let previous = self.autoResumeProbeLastStepCount {\n                        if rawProbeSteps > previous {\n                            self.autoResumeProbeStepProgressions += 1\n                            self.lastAutoResumeStepEvidenceAt = sampleEndDate\n                        } else if rawProbeSteps < previous {\n                            self.autoResumeProbeStepProgressions = 0\n                            self.lastAutoResumeStepEvidenceAt = .distantPast\n                        }\n                    }\n                    self.autoResumeProbeLastStepCount = rawProbeSteps\n\n                    self.cadenceSPM = sampleCadenceSPM\n                    self.lastCadenceEvidenceAt = sampleEndDate\n                    var payload: [String: Any] = [\n                        "probe_steps": rawProbeSteps,\n                        "canonical_steps": self.steps,\n                        "canonical_steps_unchanged": true,\n                        "step_progressions": self.autoResumeProbeStepProgressions,\n                        "step_resume_ready": self.autoResumeStepEvidenceReady,\n                        "sample_end_timestamp": sampleEndDate.timeIntervalSince1970,\n                    ]\n                    if sampleCadenceSPM > 0 { payload["cadence_spm"] = sampleCadenceSPM }\n                    if let pace = data.currentPace?.doubleValue { payload["pace_s_per_m"] = pace }\n                    self.sendSensorSample(\n                        kind: "auto_resume_probe_pedometer",\n                        payload: payload,\n                        reliable: false\n                    )\n                    self.stageAutoResumeIfNeeded()\n                    return\n                }\n\n                let nextSteps = self.pedometerBaseSteps + data.numberOfSteps.intValue\n                let advanced = nextSteps > self.steps\n                self.steps = nextSteps\n                if advanced, TrackerAutoPolicy.usesFootStepEvidence(self.displayActivity) {\n                    self.lastStepMovementEvidenceAt = sampleEndDate\n                    self.cancelPendingAutoPause() // AUTO_PAUSE_NATIVE_STEP_VETO\n                }\n                self.cadenceSPM = sampleCadenceSPM\n                // A delayed CMPedometer callback must not make an old cadence\n                // look fresh after an auto-pause.\n                self.lastCadenceEvidenceAt = sampleEndDate\n                var payload: [String: Any] = [\n                    "steps": self.steps,\n                    "step_advanced": advanced,\n                    "step_evidence_fresh": self.freshStepMovementEvidence,\n                    "sample_end_timestamp": sampleEndDate.timeIntervalSince1970,\n                ]\n                if self.cadenceSPM > 0 { payload["cadence_spm"] = self.cadenceSPM }\n                if let pace = data.currentPace?.doubleValue { payload["pace_s_per_m"] = pace }\n                self.reevaluateAutomaticActivityFromLiveSensors()\n                self.sendSensorSample(kind: "pedometer", payload: payload, reliable: false)\n''',
    "// AUTO_RESUME_REJECT_PREPAUSE_PEDOMETER",
    "native step/callback boundary integration",
)

# ---------------------------------------------------------------------------
# Pause decision: recent native step progress blocks foot-locomotion pause.
# Cycling never consumes that veto.
# ---------------------------------------------------------------------------
watch = replace_once_or_present(
    watch,
    '''        let cadence = freshCadenceSPM\n        let shouldStage = WatchAutoPolicy.shouldStagePause(\n            activity: displayActivity,\n            stationary: fusedStillness, // AUTO_PAUSE_FIELD_FUSED_STAGE\n            speedMps: currentSpeedMps,\n            speedFresh: autoPauseSpeedEvidenceFresh,\n            cadenceSPM: cadence\n        )\n        let decisionReason = autoPauseEvaluationReason(\n            fusedStillness: fusedStillness,\n            speedFresh: autoPauseSpeedEvidenceFresh,\n            cadenceSPM: cadence\n        )\n''',
    '''        let cadence = freshCadenceSPM\n        let stepMovementFresh = freshStepMovementEvidence // AUTO_PAUSE_STEP_VETO_STAGE\n        let shouldStage = !stepMovementFresh && WatchAutoPolicy.shouldStagePause(\n            activity: displayActivity,\n            stationary: fusedStillness, // AUTO_PAUSE_FIELD_FUSED_STAGE\n            speedMps: currentSpeedMps,\n            speedFresh: autoPauseSpeedEvidenceFresh,\n            cadenceSPM: cadence\n        )\n        let decisionReason = stepMovementFresh\n            ? "fresh_step_veto"\n            : autoPauseEvaluationReason(\n                fusedStillness: fusedStillness,\n                speedFresh: autoPauseSpeedEvidenceFresh,\n                cadenceSPM: cadence\n            )\n''',
    "// AUTO_PAUSE_STEP_VETO_STAGE",
    "step veto in pause staging",
)

watch = replace_once_or_present(
    watch,
    '''            let cadence = self.freshCadenceSPM\n            let confirmed = WatchAutoPolicy.shouldStagePause(\n                activity: self.displayActivity,\n                stationary: fusedStillness, // AUTO_PAUSE_FIELD_FUSED_CONFIRM\n                speedMps: self.currentSpeedMps,\n                speedFresh: self.autoPauseSpeedEvidenceFresh,\n                cadenceSPM: cadence\n            )\n            let decisionReason = self.autoPauseEvaluationReason(\n                fusedStillness: fusedStillness,\n                speedFresh: self.autoPauseSpeedEvidenceFresh,\n                cadenceSPM: cadence\n            )\n''',
    '''            let cadence = self.freshCadenceSPM\n            let stepMovementFresh = self.freshStepMovementEvidence // AUTO_PAUSE_STEP_VETO_CONFIRM\n            let confirmed = !stepMovementFresh && WatchAutoPolicy.shouldStagePause(\n                activity: self.displayActivity,\n                stationary: fusedStillness, // AUTO_PAUSE_FIELD_FUSED_CONFIRM\n                speedMps: self.currentSpeedMps,\n                speedFresh: self.autoPauseSpeedEvidenceFresh,\n                cadenceSPM: cadence\n            )\n            let decisionReason = stepMovementFresh\n                ? "fresh_step_veto"\n                : self.autoPauseEvaluationReason(\n                    fusedStillness: fusedStillness,\n                    speedFresh: self.autoPauseSpeedEvidenceFresh,\n                    cadenceSPM: cadence\n                )\n''',
    "// AUTO_PAUSE_STEP_VETO_CONFIRM",
    "step veto in pause confirmation",
)

# Add step freshness to the periodic pause diagnostic sample.
watch = replace_once_or_present(
    watch,
    '''                "cadence_age_s":\n                    cadenceAge.isFinite\n                        ? cadenceAge\n                        : -1,\n                "fused_stillness": fusedStillness,\n''',
    '''                "cadence_age_s":\n                    cadenceAge.isFinite\n                        ? cadenceAge\n                        : -1,\n                "step_evidence_fresh": freshStepMovementEvidence, // AUTO_PAUSE_STEP_DIAGNOSTICS\n                "step_age_s": Date().timeIntervalSince(lastStepMovementEvidenceAt),\n                "fused_stillness": fusedStillness,\n''',
    "// AUTO_PAUSE_STEP_DIAGNOSTICS",
    "step evidence pause diagnostics",
)

# ---------------------------------------------------------------------------
# Resume decision: two fresh native step progressions can resume foot movement.
# Cycling continues to require GPS/motion evidence and cannot consume this path.
# ---------------------------------------------------------------------------
watch = replace_once_or_present(
    watch,
    '''        let decision = WatchAutoPolicy.resumeDecision(\n            activity: displayActivity,\n            evidence: evidence\n        )\n\n        guard decision.shouldResume else {\n''',
    '''        var decision = WatchAutoPolicy.resumeDecision(\n            activity: displayActivity,\n            evidence: evidence\n        )\n        if !decision.shouldResume, autoResumeStepEvidenceReady { // AUTO_RESUME_SUSTAINED_STEPS_STAGE\n            decision = TrackerAutoResumeDecision(\n                shouldResume: true,\n                reason: "sustained_step_progression",\n                agreeingEvidenceCount: 1\n            )\n        }\n\n        guard decision.shouldResume else {\n''',
    "// AUTO_RESUME_SUSTAINED_STEPS_STAGE",
    "step progression resume staging",
)

watch = replace_once_or_present(
    watch,
    '''            let confirmed = WatchAutoPolicy.resumeDecision(\n                activity: self.displayActivity,\n                evidence: self.currentAutoResumeEvidence(now: Date())\n            )\n\n            guard confirmed.shouldResume else {\n''',
    '''            var confirmed = WatchAutoPolicy.resumeDecision(\n                activity: self.displayActivity,\n                evidence: self.currentAutoResumeEvidence(now: Date())\n            )\n            if !confirmed.shouldResume, self.autoResumeStepEvidenceReady { // AUTO_RESUME_SUSTAINED_STEPS_CONFIRM\n                confirmed = TrackerAutoResumeDecision(\n                    shouldResume: true,\n                    reason: "sustained_step_progression",\n                    agreeingEvidenceCount: 1\n                )\n            }\n\n            guard confirmed.shouldResume else {\n''',
    "// AUTO_RESUME_SUSTAINED_STEPS_CONFIRM",
    "step progression resume confirmation",
)

watch = replace_once_or_present(
    watch,
    '''            "cadence_age_s": cadenceAge.isFinite ? cadenceAge : -1,\n            "probe_speed_mps": evidence.speedMps,\n''',
    '''            "cadence_age_s": cadenceAge.isFinite ? cadenceAge : -1,\n            "step_progressions": autoResumeProbeStepProgressions, // AUTO_RESUME_STEP_DIAGNOSTICS\n            "step_evidence_fresh": autoResumeStepEvidenceAge >= 0\n                && autoResumeStepEvidenceAge <= TrackerAutoPolicy.footStepResumeFreshness,\n            "step_age_s": autoResumeStepEvidenceAge.isFinite ? autoResumeStepEvidenceAge : -1,\n            "probe_speed_mps": evidence.speedMps,\n''',
    "// AUTO_RESUME_STEP_DIAGNOSTICS",
    "step evidence resume diagnostics",
)

# ---------------------------------------------------------------------------
# Regression tests: the physical walk run, stale pre-pause callbacks, and cycling
# separation are encoded in deterministic policy tests.
# ---------------------------------------------------------------------------
auto_tests = replace_once_or_present(
    auto_tests,
    '''    func testSyntheticWalkRunCycleReplayProducesExpectedCandidates() {\n''',
    '''    func testFootStepEvidenceNeverActsAsCyclingCadence() { // FIELD_1789537681642_STEP_POLICY\n        XCTAssertTrue(TrackerAutoPolicy.usesFootStepEvidence(.automatic))\n        XCTAssertTrue(TrackerAutoPolicy.usesFootStepEvidence(.walking))\n        XCTAssertTrue(TrackerAutoPolicy.usesFootStepEvidence(.running))\n        XCTAssertFalse(TrackerAutoPolicy.usesFootStepEvidence(.cycling))\n\n        XCTAssertTrue(\n            TrackerAutoPolicy.canResumeFromSustainedStepProgression(\n                activity: .automatic,\n                ageSeconds: 0.5,\n                progressionCount: 2\n            )\n        )\n        XCTAssertFalse(\n            TrackerAutoPolicy.canResumeFromSustainedStepProgression(\n                activity: .cycling,\n                ageSeconds: 0.5,\n                progressionCount: 99\n            )\n        )\n    }\n\n    func testFreshStepsVetoPauseButExpireQuickly() {\n        XCTAssertTrue(\n            TrackerAutoPolicy.freshStepMovementEvidence(\n                activity: .walking,\n                ageSeconds: 2.5\n            )\n        )\n        XCTAssertFalse(\n            TrackerAutoPolicy.freshStepMovementEvidence(\n                activity: .walking,\n                ageSeconds: 3.1\n            )\n        )\n    }\n\n    func testCyclingResumeStillUsesSustainedGPSNotPedometer() {\n        let decision = TrackerAutoPolicy.resumeDecision(\n            activity: .cycling,\n            enabled: true,\n            evidence: TrackerAutoResumeEvidence(\n                speedMps: 3.2,\n                gpsFresh: true,\n                gpsReliable: true,\n                gpsSustained: true,\n                cadenceSPM: 0,\n                cadenceFresh: false,\n                stationary: true,\n                motionCandidate: nil,\n                motionFresh: false\n            )\n        )\n        XCTAssertTrue(decision.shouldResume)\n        XCTAssertEqual(decision.reason, "strong_sustained_gps")\n    }\n\n    func testSyntheticWalkRunCycleReplayProducesExpectedCandidates() {\n''',
    "// FIELD_1789537681642_STEP_POLICY",
    "field step/cycling policy tests",
)

stability_tests = replace_once_or_present(
    stability_tests,
    '''        XCTAssertEqual(TrackerAutoPauseStabilityPolicy.pauseDwell(for: .walking), 6.0)\n''',
    '''        XCTAssertEqual(TrackerAutoPauseStabilityPolicy.pauseDwell(for: .walking), 4.0) // FIELD_1789537681642_REACTIVE_DWELL\n''',
    "// FIELD_1789537681642_REACTIVE_DWELL",
    "first walking dwell regression",
)

# One more 6.0 expectation remains in the second timing test.
if "// FIELD_1789537681642_SECOND_DWELL" not in stability_tests:
    old = '        XCTAssertEqual(TrackerAutoPauseStabilityPolicy.pauseDwell(for: .walking), 6.0)\n'
    if stability_tests.count(old) != 1:
        raise SystemExit(
            "second walking dwell regression: expected exactly one remaining 6 s assertion, "
            f"got {stability_tests.count(old)}"
        )
    stability_tests = stability_tests.replace(
        old,
        '        XCTAssertEqual(TrackerAutoPauseStabilityPolicy.pauseDwell(for: .walking), 4.0) // FIELD_1789537681642_SECOND_DWELL\n',
        1,
    )

for name, text, required in [
    (
        "policy",
        policy,
        [
            "// AUTO_PAUSE_FOOT_STEP_POLICY",
            "canResumeFromSustainedStepProgression(",
            "case .cycling, .handCycling:",
        ],
    ),
    (
        "stability",
        stability,
        ["// AUTO_PAUSE_REACTIVE_FOOT_DWELL"],
    ),
    (
        "watch",
        watch,
        [
            "// AUTO_PAUSE_CONFIRMED_HAPTICS",
            "// AUTO_PAUSE_STOP_HAPTIC",
            "// AUTO_RESUME_START_HAPTIC",
            "// AUTO_RESUME_REJECT_PREPAUSE_PEDOMETER",
            "// AUTO_PAUSE_NATIVE_STEP_VETO",
            "// AUTO_PAUSE_STEP_VETO_STAGE",
            "// AUTO_PAUSE_STEP_VETO_CONFIRM",
            "// AUTO_RESUME_SUSTAINED_STEPS_STAGE",
            "// AUTO_RESUME_SUSTAINED_STEPS_CONFIRM",
        ],
    ),
    (
        "auto_tests",
        auto_tests,
        ["// FIELD_1789537681642_STEP_POLICY"],
    ),
    (
        "stability_tests",
        stability_tests,
        [
            "// FIELD_1789537681642_REACTIVE_DWELL",
            "// FIELD_1789537681642_SECOND_DWELL",
        ],
    ),
]:
    for token in required:
        if token not in text:
            raise SystemExit(f"{name}: required token missing: {token}")

POLICY.write_text(policy, encoding="utf-8")
STABILITY.write_text(stability, encoding="utf-8")
WATCH.write_text(watch, encoding="utf-8")
AUTO_TESTS.write_text(auto_tests, encoding="utf-8")
STABILITY_TESTS.write_text(stability_tests, encoding="utf-8")

print("AUTO PAUSE REACTIVITY + HAPTICS PATCH: OK")
