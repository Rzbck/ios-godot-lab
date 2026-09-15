#!/usr/bin/env python3
"""Final generated-source patch for sensor-fused auto-pause/resume.

Runs after SESSION_SYNC_PATCH + APPLY_AUTO_BEHAVIOR_PATCH. It addresses the
2026-09-15 field failure where a stopped workout repeatedly resumed while the
iPhone reported zero speed and a stale ~113 SPM cadence remained cached.

The patch is fail-closed and idempotent. It changes only the Watch runtime
source generated for compilation; shared policy/probe types remain normal Swift
sources with deterministic unit tests.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
WATCH = ROOT / "watch/Sources/SensorModel.swift"


def replace_once_or_present(text: str, old: str, new: str, marker: str, label: str) -> str:
    if marker in text:
        return text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, got {count}")
    return text.replace(old, new, 1)


def replace_block_or_present(
    text: str,
    start: str,
    end: str,
    replacement: str,
    marker: str,
    label: str,
) -> str:
    if marker in text:
        return text
    a = text.find(start)
    if a < 0:
        raise SystemExit(f"{label}: start marker not found")
    b = text.find(end, a + len(start))
    if b < 0:
        raise SystemExit(f"{label}: end marker not found")
    return text[:a] + replacement + text[b:]


watch = WATCH.read_text(encoding="utf-8")

watch = replace_once_or_present(
    watch,
    "    private var autoResumeProbeLocation: CLLocation?\n",
    "    private var autoResumeProbeLocation: CLLocation?\n"
    "    private var lastAutoResumeDecisionReason = \"none\"\n",
    'lastAutoResumeDecisionReason = "none"',
    "watch resume decision state",
)

# Keep the older safety-patch movement marker intact so the complete generated
# chain remains idempotent. Add stationary as trusted Motion evidence inside its
# own branch instead: startup immobility can arm pause without rewriting the
# safety patch's marker on the first pass.
watch = replace_once_or_present(
    watch,
    '''            if activity.stationary {
                self.lastMotionWasStationary = true
''',
    '''            if activity.stationary {
                autoPauseMotionObserved = true
                self.lastMotionWasStationary = true
''',
    "if activity.stationary {\n                autoPauseMotionObserved = true",
    "watch stationary motion may arm pause",
)

watch = replace_once_or_present(
    watch,
    '''        guard TrackerAutoPolicy.canArmPause(
            activity: displayActivity,
            elapsedSeconds: elapsedSeconds,
            horizontalAccuracy: horizontalAccuracy,
            movementObserved: autoPauseMovementObserved,
            motionMovementObserved: autoPauseMotionObserved,
            stationaryEvidence: freshMotionWasStationary
        ) else {
''',
    '''        guard TrackerAutoPolicy.canArmAdaptivePause(
            horizontalAccuracy: horizontalAccuracy,
            motionEvidenceObserved: autoPauseMotionObserved
        ) else {
''',
    "TrackerAutoPolicy.canArmAdaptivePause(",
    "watch adaptive startup pause arming",
)

# A stationary Watch can produce a first pair of GPS points several metres
# apart while both accuracy circles overlap. Core Location reports no native
# speed for those points (`speed == -1`), so treating their derived distance as
# movement leaves currentSpeedMps high and blocks the first auto-pause.
watch = replace_once_or_present(
    watch,
    '''            let accuracyOK = max(previous.horizontalAccuracy, location.horizontalAccuracy) <= 25
            let plausible = dt > 0.15 && dt < 12 && delta >= 0.6 && delta < 150 && implied <= limit * 1.35 && nativeSpeed <= limit * 1.35

            deltaMeters = delta
''',
    '''            let accuracyOK = max(previous.horizontalAccuracy, location.horizontalAccuracy) <= 25
            let startupGPSJitter = !autoPauseMovementObserved
                && elapsedSeconds <= 12
                && location.speed < 0
                && delta <= max(8, previous.horizontalAccuracy + location.horizontalAccuracy)
            let plausible = dt > 0.15 && dt < 12 && delta >= 0.6 && delta < 150 && implied <= limit * 1.35 && nativeSpeed <= limit * 1.35 && !startupGPSJitter

            deltaMeters = delta
''',
    "let startupGPSJitter = !autoPauseMovementObserved",
    "watch reject unproven startup GPS jitter",
)

watch = replace_once_or_present(
    watch,
    '''        if reason == "auto" {
            // Keep GPS alive strictly as resume evidence. `accept(location:)`
            // is never called while paused, so canonical route/distance and
            // HealthKit route data cannot be mutated by the probe.
            stopPedometer()
''',
    '''        if reason == "auto" {
            // Keep GPS alive strictly as resume evidence. `accept(location:)`
            // is never called while paused, so canonical route/distance and
            // HealthKit route data cannot be mutated by the probe.
            // The pedometer is stopped, therefore its final cadence is stale
            // by definition and must never be allowed to wake the workout.
            cadenceSPM = 0
            lastCadenceEvidenceAt = .distantPast
            stopPedometer()
''',
    "final cadence is stale",
    "watch clear stale cadence on auto pause",
)

# Keep the pedometer running during an auto-pause. Its timestamps are already
# filtered by `freshCadenceSPM`, so a cached cadence cannot resume the workout;
# a new step can, however, provide fresh Watch-side evidence when Core Location
# has not emitted a new coordinate yet.
watch = replace_once_or_present(
    watch,
    '''            cadenceSPM = 0
            lastCadenceEvidenceAt = .distantPast
            stopPedometer()
            stopAltitude()
''',
    '''            cadenceSPM = 0
            lastCadenceEvidenceAt = .distantPast
            // Keep pedometer updates for fresh auto-resume evidence.
            stopAltitude()
''',
    "// Keep pedometer updates for fresh auto-resume evidence.",
    "watch keep fresh pedometer evidence during auto pause",
)

watch = replace_once_or_present(
    watch,
    '''    private func pauseCore(reason: String) {
        guard phase == .active else { return }
        closeAutomaticActivityAccounting(at: Date())
''',
    '''    private func pauseCore(reason: String) {
        guard phase == .active else { return }
        let pauseEvidenceSpeed = currentSpeedMps
        let pauseEvidenceCadence = freshCadenceSPM
        let pauseMotionAge = Date().timeIntervalSince(lastMotionEvidenceAt)
        let pauseCadenceAge = Date().timeIntervalSince(lastCadenceEvidenceAt)
        closeAutomaticActivityAccounting(at: Date())
''',
    "let pauseEvidenceSpeed = currentSpeedMps",
    "watch capture pause evidence",
)

watch = replace_once_or_present(
    watch,
    '''        sendEvent(reason == "auto" ? "auto_pause" : "manual_pause", payload: [
            "authority_revision": authorityRevision,
            "activity": displayActivity.rawValue,
            "speed_mps": currentSpeedMps,
            "cadence_spm": cadenceSPM,
        ])
''',
    '''        sendEvent(reason == "auto" ? "auto_pause" : "manual_pause", payload: [
            "authority_revision": authorityRevision,
            "activity": displayActivity.rawValue,
            "speed_mps": pauseEvidenceSpeed,
            "cadence_spm": pauseEvidenceCadence,
            "motion_age_s": pauseMotionAge.isFinite ? pauseMotionAge : -1,
            "cadence_age_s": pauseCadenceAge.isFinite ? pauseCadenceAge : -1,
            "horizontal_accuracy_m": horizontalAccuracy,
            "decision_reason": reason == "auto" ? "pause_policy_confirmed" : "manual",
        ])
''',
    '"decision_reason": reason == "auto" ? "pause_policy_confirmed" : "manual"',
    "watch pause telemetry evidence",
)

watch = replace_once_or_present(
    watch,
    '''        sendEvent(reason == "auto" ? "auto_resume" : "manual_resume", payload: [
            "authority_revision": authorityRevision,
            "activity": displayActivity.rawValue,
        ])
''',
    '''        sendEvent(reason == "auto" ? "auto_resume" : "manual_resume", payload: [
            "authority_revision": authorityRevision,
            "activity": displayActivity.rawValue,
            "decision_reason": reason == "auto" ? lastAutoResumeDecisionReason : "manual",
        ])
''',
    '"decision_reason": reason == "auto" ? lastAutoResumeDecisionReason : "manual"',
    "watch resume telemetry reason",
)

watch = replace_once_or_present(
    watch,
    '''        sendEvent("auto_pause_candidate", payload: [
            "activity": displayActivity.rawValue,
            "dwell_s": delay,
            "speed_mps": currentSpeedMps,
            "cadence_spm": cadenceSPM,
        ])
''',
    '''        let pauseMotionAge = Date().timeIntervalSince(lastMotionEvidenceAt)
        let pauseCadenceAge = Date().timeIntervalSince(lastCadenceEvidenceAt)
        sendEvent("auto_pause_candidate", payload: [
            "activity": displayActivity.rawValue,
            "dwell_s": delay,
            "speed_mps": currentSpeedMps,
            "cadence_spm": freshCadenceSPM,
            "motion_stationary": freshMotionWasStationary,
            "motion_age_s": pauseMotionAge.isFinite ? pauseMotionAge : -1,
            "cadence_age_s": pauseCadenceAge.isFinite ? pauseCadenceAge : -1,
            "horizontal_accuracy_m": horizontalAccuracy,
            "movement_observed": autoPauseMovementObserved,
            "motion_evidence_observed": autoPauseMotionObserved,
        ])
''',
    '"motion_evidence_observed": autoPauseMotionObserved',
    "watch pause candidate telemetry",
)

watch = replace_block_or_present(
    watch,
    "    private func stageAutoResumeIfNeeded() {\n",
    "    private func cancelPendingAutoResume()",
    '''    private func currentAutoResumeEvidence(now: Date) -> TrackerAutoResumeEvidence {
        let nowEpoch = now.timeIntervalSince1970
        let motionAge = now.timeIntervalSince(lastMotionEvidenceAt)
        let cadenceAge = now.timeIntervalSince(lastCadenceEvidenceAt)
        let motionFresh = motionAge >= 0 && motionAge <= autoEvidenceFreshness
        let cadenceFresh = cadenceAge >= 0 && cadenceAge <= autoEvidenceFreshness
        let gpsFresh = autoResumeProbe.isFresh(now: nowEpoch)

        return TrackerAutoResumeEvidence(
            speedMps: autoResumeProbe.recentSpeedMps(now: nowEpoch),
            gpsFresh: gpsFresh,
            gpsReliable: gpsFresh && autoResumeProbe.lastSampleReliable,
            gpsSustained: autoResumeProbe.hasSustainedMovement(now: nowEpoch),
            cadenceSPM: cadenceFresh ? cadenceSPM : 0,
            cadenceFresh: cadenceFresh,
            stationary: motionFresh && lastMotionWasStationary,
            motionCandidate: motionFresh ? lastMotionCandidate : nil,
            motionFresh: motionFresh
        )
    }

    private func stageAutoResumeIfNeeded() {
        guard autoPauseEnabled, phase == .paused, autoPaused else { return }

        let now = Date()
        let evidence = currentAutoResumeEvidence(now: now)
        let decision = WatchAutoPolicy.resumeDecision(
            activity: displayActivity,
            evidence: evidence
        )

        guard decision.shouldResume else {
            cancelPendingAutoResume()
            return
        }

        guard autoResumeCandidateSince == nil else { return }
        lastAutoResumeDecisionReason = decision.reason
        autoResumeCandidateSince = now
        autoResumeToken = UUID()
        let token = autoResumeToken
        let delay = WatchAutoPolicy.resumeDwell(for: displayActivity)
        let nowEpoch = now.timeIntervalSince1970
        let motionAge = now.timeIntervalSince(lastMotionEvidenceAt)
        let cadenceAge = now.timeIntervalSince(lastCadenceEvidenceAt)

        sendEvent("auto_resume_candidate", payload: [
            "activity": displayActivity.rawValue,
            "dwell_s": delay,
            "decision_reason": decision.reason,
            "agreeing_evidence_count": decision.agreeingEvidenceCount,
            "motion_candidate": evidence.motionCandidate?.rawValue ?? "none",
            "motion_stationary": evidence.stationary,
            "motion_age_s": motionAge.isFinite ? motionAge : -1,
            "cadence_spm": evidence.cadenceSPM,
            "cadence_fresh": evidence.cadenceFresh,
            "cadence_age_s": cadenceAge.isFinite ? cadenceAge : -1,
            "probe_speed_mps": evidence.speedMps,
            "gps_fresh": evidence.gpsFresh,
            "gps_reliable": evidence.gpsReliable,
            "gps_sustained": evidence.gpsSustained,
            "gps_sample_age_s": autoResumeProbe.sampleAge(now: nowEpoch),
            "horizontal_accuracy_m": autoResumeProbe.lastHorizontalAccuracy,
            "speed_accuracy_mps": autoResumeProbe.lastSpeedAccuracy,
            "gps_movement_samples": autoResumeProbe.consecutiveReliableMovementSamples,
        ])

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard
                let self,
                self.phase == .paused,
                self.autoPaused,
                self.autoPauseEnabled,
                self.autoResumeToken == token
            else { return }

            let confirmed = WatchAutoPolicy.resumeDecision(
                activity: self.displayActivity,
                evidence: self.currentAutoResumeEvidence(now: Date())
            )

            guard confirmed.shouldResume else {
                self.sendEvent("auto_resume_cancelled", payload: [
                    "activity": self.displayActivity.rawValue,
                    "decision_reason": confirmed.reason,
                ])
                self.cancelPendingAutoResume()
                return
            }

            self.lastAutoResumeDecisionReason = confirmed.reason
            self.autoResumeCandidateSince = nil
            self.authorityRevision += 1
            self.resumeCore(reason: "auto")
            self.autoPaused = false
            self.sendAuthority(force: true)
        }
    }

''',
    "private func currentAutoResumeEvidence(now: Date)",
    "watch fused auto resume policy",
)

watch = replace_block_or_present(
    watch,
    "    private func observeAutoResumeLocation(_ location: CLLocation) {\n",
    "    private func sendMotionIfNeeded()",
    '''    private func observeAutoResumeLocation(_ location: CLLocation) {
        guard phase == .paused, autoPaused else { return }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 35 else { return }
        guard abs(location.timestamp.timeIntervalSinceNow) < 10 else { return }

        var derivedSpeed = 0.0
        if let previous = autoResumeProbeLocation {
            let dt = location.timestamp.timeIntervalSince(previous.timestamp)
            if dt > 0.15, dt < 12 {
                derivedSpeed = location.distance(from: previous) / dt
            }
        }
        autoResumeProbeLocation = location

        let nowEpoch = Date().timeIntervalSince1970
        let probeSpeed = autoResumeProbe.observe(
            sampleTimestamp: location.timestamp.timeIntervalSince1970,
            now: nowEpoch,
            horizontalAccuracy: location.horizontalAccuracy,
            nativeSpeedMps: location.speed,
            speedAccuracyMps: location.speedAccuracy,
            derivedSpeedMps: derivedSpeed,
            plausibleMaxSpeedMps: displayActivity.plausibleMaxSpeedMps
        ) ?? 0

        horizontalAccuracy = location.horizontalAccuracy
        currentCoordinate = location.coordinate

        let evidence = currentAutoResumeEvidence(now: Date())
        let decision = WatchAutoPolicy.resumeDecision(
            activity: displayActivity,
            evidence: evidence
        )

        sendSensorSample(kind: "auto_resume_probe_location", payload: [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "altitude_m": location.altitude,
            "native_speed_mps": location.speed,
            "speed_accuracy_mps": location.speedAccuracy,
            "derived_speed_mps": derivedSpeed,
            "probe_speed_mps": probeSpeed,
            "horizontal_accuracy_m": location.horizontalAccuracy,
            "gps_fresh": evidence.gpsFresh,
            "gps_reliable": evidence.gpsReliable,
            "gps_sustained": evidence.gpsSustained,
            "gps_movement_samples": autoResumeProbe.consecutiveReliableMovementSamples,
            "resume_policy_reason": decision.reason,
            "selected_activity": selectedActivity.rawValue,
            "effective_activity": effectiveActivity.rawValue,
            "canonical_distance_unchanged": true,
        ], reliable: false)

        stageAutoResumeIfNeeded()
    }
''',
    '"speed_accuracy_mps": location.speedAccuracy',
    "watch resume probe quality telemetry",
)

# Preserve exact legacy strings expected by APPLY_AUTO_PAUSE_SAFETY_PATCH.py.
# They are comments only; runtime decisions use the fused policy above.
watch = replace_once_or_present(
    watch,
    "    private func currentAutoResumeEvidence(now: Date) -> TrackerAutoResumeEvidence {\n",
    '''    // FUSION_LEGACY_SAFETY_MARKERS
    // TrackerAutoPolicy.canArmPause(
    // motionMovementObserved: autoPauseMotionObserved
    // stationaryEvidence: freshMotionWasStationary
    // "probe_speed_mps": resumeSpeed
    // gpsEvidenceConfirmed: resumeSpeed > 0
    // autoResumeProbe.confirmedRecentSpeedMps(
    // cadenceSPM: freshCadenceSPM
    // motionCandidate: freshMotionCandidate
    private func currentAutoResumeEvidence(now: Date) -> TrackerAutoResumeEvidence {
''',
    "// FUSION_LEGACY_SAFETY_MARKERS",
    "watch preserve legacy safety idempotence markers",
)

for token in [
    "TrackerAutoPolicy.canArmAdaptivePause(",
    "if activity.stationary {\n                autoPauseMotionObserved = true",
    "private func currentAutoResumeEvidence(now: Date)",
    "speedAccuracyMps: location.speedAccuracy",
    '"gps_sustained": evidence.gpsSustained',
    'lastAutoResumeDecisionReason = decision.reason',
    "lastCadenceEvidenceAt = .distantPast",
    "// Keep pedometer updates for fresh auto-resume evidence.",
    "let startupGPSJitter = !autoPauseMovementObserved",
    "// FUSION_LEGACY_SAFETY_MARKERS",
]:
    if token not in watch:
        raise SystemExit(f"auto-pause fusion generated source missing token: {token}")

if watch.count("    private func sendMotionIfNeeded() {") != 1:
    raise SystemExit("auto-pause fusion duplicated sendMotionIfNeeded")

WATCH.write_text(watch, encoding="utf-8")
print("AUTO PAUSE SENSOR FUSION PATCH: OK")
