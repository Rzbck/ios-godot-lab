#!/usr/bin/env python3
"""Final runtime wake-up and anti-oscillation patch for Watch auto-resume.

Runs after the existing auto-pause fusion patch. It fixes two hardware failures:
1. auto-pause succeeds but never resumes because fresh paused pedometer evidence
   is recorded without re-evaluating the resume policy;
2. a confirmed resume immediately re-enters auto-pause before active-state
   Core Motion / cadence evidence has repopulated, causing pause/resume thrash.

The patch is fail-closed and idempotent. During an automatic pause, sensor
updates are resume evidence only: canonical route, distance, elevation and step
count must remain unchanged until the workout has actually resumed.
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


watch = WATCH.read_text(encoding="utf-8")

# Remember the last confirmed automatic resume so pause detection has real
# hysteresis instead of immediately re-arming on temporarily empty sensor data.
watch = replace_once_or_present(
    watch,
    '    private var lastAutoResumeDecisionReason = "none"\n',
    '    private var lastAutoResumeDecisionReason = "none"\n'
    '    private var lastAutoResumeAt = Date.distantPast // AUTO_RESUME_REPAUSE_HYSTERESIS_STATE\n',
    "// AUTO_RESUME_REPAUSE_HYSTERESIS_STATE",
    "watch repause hysteresis state",
)

# A new workout must never inherit the cooldown of a previous session.
watch = replace_once_or_present(
    watch,
    '''            startedAt = Date()
            pausedAt = nil
            pausedDuration = 0
            resetPresentationData(keepActivity: true)
''',
    '''            startedAt = Date()
            pausedAt = nil
            pausedDuration = 0
            lastAutoResumeAt = .distantPast // AUTO_RESUME_RESET_REPAUSE_HYSTERESIS
            resetPresentationData(keepActivity: true)
''',
    "// AUTO_RESUME_RESET_REPAUSE_HYSTERESIS",
    "watch reset repause hysteresis per session",
)

# Resume policy must keep being evaluated while an automatic pause is active.
# This makes fresh pedometer/Core Motion evidence actionable even when GPS has
# not produced a new coordinate callback at that exact moment.
watch = replace_once_or_present(
    watch,
    '''                if self.autoPauseEnabled, self.phase == .active {
                    self.stageAutoPauseIfNeeded()
                }

                self.sendAuthority()
''',
    '''                if self.autoPauseEnabled {
                    if self.phase == .active {
                        self.stageAutoPauseIfNeeded()
                    } else if self.phase == .paused, self.autoPaused {
                        // AUTO_RESUME_RUNTIME_TIMER
                        self.stageAutoResumeIfNeeded()
                    }
                }

                self.sendAuthority()
''',
    "// AUTO_RESUME_RUNTIME_TIMER",
    "watch timer must evaluate auto resume while paused",
)

# Keep CMPedometer alive as a read-only resume probe during auto-pause. Do not
# fold probe steps into the canonical workout counter. A fresh cadence update
# immediately re-evaluates the fused resume policy.
watch = replace_once_or_present(
    watch,
    '''                guard let data else { return }
                self.steps = self.pedometerBaseSteps + data.numberOfSteps.intValue
                self.cadenceSPM = max(0, (data.currentCadence?.doubleValue ?? 0) * 60)
                // A delayed CMPedometer callback must not make an old cadence
                // look fresh after an auto-pause.
                self.lastCadenceEvidenceAt = data.endDate
                var payload: [String: Any] = ["steps": self.steps]
                if self.cadenceSPM > 0 { payload["cadence_spm"] = self.cadenceSPM }
                if let pace = data.currentPace?.doubleValue { payload["pace_s_per_m"] = pace }
                self.reevaluateAutomaticActivityFromLiveSensors()
                self.sendSensorSample(kind: "pedometer", payload: payload, reliable: false)
''',
    '''                guard let data else { return }
                let sampleCadenceSPM = max(0, (data.currentCadence?.doubleValue ?? 0) * 60)

                if self.phase == .paused, self.autoPaused {
                    // AUTO_RESUME_PEDOMETER_PROBE_ONLY
                    self.cadenceSPM = sampleCadenceSPM
                    self.lastCadenceEvidenceAt = data.endDate
                    var payload: [String: Any] = [
                        "probe_steps": data.numberOfSteps.intValue,
                        "canonical_steps": self.steps,
                        "canonical_steps_unchanged": true,
                    ]
                    if sampleCadenceSPM > 0 { payload["cadence_spm"] = sampleCadenceSPM }
                    if let pace = data.currentPace?.doubleValue { payload["pace_s_per_m"] = pace }
                    self.sendSensorSample(
                        kind: "auto_resume_probe_pedometer",
                        payload: payload,
                        reliable: false
                    )
                    self.stageAutoResumeIfNeeded()
                    return
                }

                self.steps = self.pedometerBaseSteps + data.numberOfSteps.intValue
                self.cadenceSPM = sampleCadenceSPM
                // A delayed CMPedometer callback must not make an old cadence
                // look fresh after an auto-pause.
                self.lastCadenceEvidenceAt = data.endDate
                var payload: [String: Any] = ["steps": self.steps]
                if self.cadenceSPM > 0 { payload["cadence_spm"] = self.cadenceSPM }
                if let pace = data.currentPace?.doubleValue { payload["pace_s_per_m"] = pace }
                self.reevaluateAutomaticActivityFromLiveSensors()
                self.sendSensorSample(kind: "pedometer", payload: payload, reliable: false)
''',
    "// AUTO_RESUME_PEDOMETER_PROBE_ONLY",
    "watch pedometer must trigger resume without counting paused steps",
)

# Reset CMPedometer's counting baseline at every resume. In particular, an
# automatic pause may have received probe-only steps; restarting from Date()
# prevents those paused steps from being added to the workout afterwards.
watch = replace_once_or_present(
    watch,
    '''        workoutSession?.resume()
        locationManager.startUpdatingLocation()
        startPedometer()
        startAltitude()
''',
    '''        workoutSession?.resume()
        locationManager.startUpdatingLocation()
        // AUTO_RESUME_RESET_PEDOMETER_BASELINE
        stopPedometer()
        startPedometer()
        startAltitude()
''',
    "// AUTO_RESUME_RESET_PEDOMETER_BASELINE",
    "watch resume must reset pedometer baseline",
)

# Production stop detection must not re-arm immediately after an automatic
# resume. Match only the stable function prologue because the fusion patch adds
# adaptive arming between this prologue and the final pause-policy evaluation.
watch = replace_once_or_present(
    watch,
    '''    private func stageAutoPauseIfNeeded() {
        guard autoPauseEnabled, phase == .active else { return }
''',
    '''    private func stageAutoPauseIfNeeded() {
        guard autoPauseEnabled, phase == .active else { return }
        let timeSinceAutoResume = Date().timeIntervalSince(lastAutoResumeAt)
        let repauseCooldown = WatchAutoPauseSettings.repauseCooldown(for: displayActivity)
        if timeSinceAutoResume >= 0, timeSinceAutoResume < repauseCooldown {
            // AUTO_RESUME_REPAUSE_COOLDOWN
            cancelPendingAutoPause()
            return
        }
''',
    "// AUTO_RESUME_REPAUSE_COOLDOWN",
    "watch auto pause must respect post-resume hysteresis",
)

# Stamp the cooldown only after the fused resume evidence is confirmed at the
# end of its dwell. Candidate/cancelled resumes never suppress future pauses.
watch = replace_once_or_present(
    watch,
    '''            self.lastAutoResumeDecisionReason = confirmed.reason
            self.autoResumeCandidateSince = nil
            self.authorityRevision += 1
            self.resumeCore(reason: "auto")
''',
    '''            self.lastAutoResumeDecisionReason = confirmed.reason
            self.autoResumeCandidateSince = nil
            self.lastAutoResumeAt = Date() // AUTO_RESUME_STAMP_REPAUSE_HYSTERESIS
            self.authorityRevision += 1
            self.resumeCore(reason: "auto")
''',
    "// AUTO_RESUME_STAMP_REPAUSE_HYSTERESIS",
    "watch confirmed auto resume must stamp repause hysteresis",
)

for token in [
    "// AUTO_RESUME_REPAUSE_HYSTERESIS_STATE",
    "// AUTO_RESUME_RESET_REPAUSE_HYSTERESIS",
    "// AUTO_RESUME_RUNTIME_TIMER",
    "// AUTO_RESUME_PEDOMETER_PROBE_ONLY",
    'kind: "auto_resume_probe_pedometer"',
    '"canonical_steps_unchanged": true',
    "self.stageAutoResumeIfNeeded()",
    "// AUTO_RESUME_RESET_PEDOMETER_BASELINE",
    "// AUTO_RESUME_REPAUSE_COOLDOWN",
    "WatchAutoPauseSettings.repauseCooldown(for: displayActivity)",
    "// AUTO_RESUME_STAMP_REPAUSE_HYSTERESIS",
]:
    if token not in watch:
        raise SystemExit(f"auto-resume runtime generated source missing token: {token}")

for marker in [
    "// AUTO_RESUME_REPAUSE_HYSTERESIS_STATE",
    "// AUTO_RESUME_RESET_REPAUSE_HYSTERESIS",
    "// AUTO_RESUME_RUNTIME_TIMER",
    "// AUTO_RESUME_PEDOMETER_PROBE_ONLY",
    "// AUTO_RESUME_RESET_PEDOMETER_BASELINE",
    "// AUTO_RESUME_REPAUSE_COOLDOWN",
    "// AUTO_RESUME_STAMP_REPAUSE_HYSTERESIS",
]:
    if watch.count(marker) != 1:
        raise SystemExit(f"auto-resume runtime duplicated integration marker: {marker}")

WATCH.write_text(watch, encoding="utf-8")
print("AUTO RESUME RUNTIME + ANTI-OSCILLATION PATCH: OK")
