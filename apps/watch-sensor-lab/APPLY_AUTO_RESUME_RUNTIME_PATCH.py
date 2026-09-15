#!/usr/bin/env python3
"""Final runtime wake-up patch for Watch auto-resume.

Runs after the existing auto-pause fusion patch. It fixes the hardware failure
where auto-pause succeeds but the workout never resumes because fresh paused
pedometer evidence is recorded without re-evaluating the resume policy.

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

for token in [
    "// AUTO_RESUME_RUNTIME_TIMER",
    "// AUTO_RESUME_PEDOMETER_PROBE_ONLY",
    'kind: "auto_resume_probe_pedometer"',
    '"canonical_steps_unchanged": true',
    "self.stageAutoResumeIfNeeded()",
    "// AUTO_RESUME_RESET_PEDOMETER_BASELINE",
]:
    if token not in watch:
        raise SystemExit(f"auto-resume runtime generated source missing token: {token}")

if watch.count("// AUTO_RESUME_RUNTIME_TIMER") != 1:
    raise SystemExit("auto-resume runtime duplicated timer integration")
if watch.count("// AUTO_RESUME_PEDOMETER_PROBE_ONLY") != 1:
    raise SystemExit("auto-resume runtime duplicated pedometer probe integration")
if watch.count("// AUTO_RESUME_RESET_PEDOMETER_BASELINE") != 1:
    raise SystemExit("auto-resume runtime duplicated pedometer baseline reset")

WATCH.write_text(watch, encoding="utf-8")
print("AUTO RESUME RUNTIME PATCH: OK")
