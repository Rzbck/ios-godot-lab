#!/usr/bin/env python3
"""Deterministic candidate patch for reactive Auto sport + neutral Auto startup.

This runs after the existing session-sync and auto-pause safety patches. It is
fail-closed and idempotent so the exact candidate can be exercised in CI and on
hardware before the generated Swift changes are folded into the sources.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
IPHONE = ROOT / "iphone/Sources/TrackerModel.swift"
WATCH = ROOT / "watch/Sources/SensorModel.swift"
RECONCILER = ROOT / "watch/Sources/WatchAutoHealthReconciler.swift"


def replace_once_or_present(text: str, old: str, new: str, marker: str, label: str) -> str:
    if marker in text:
        return text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, got {count}")
    return text.replace(old, new, 1)


iphone = IPHONE.read_text(encoding="utf-8")
watch = WATCH.read_text(encoding="utf-8")
reconciler = RECONCILER.read_text(encoding="utf-8")

# ---------------------------------------------------------------------------
# Auto starts NEUTRAL, not as walking. The provisional HealthKit container is
# therefore mixedCardio until a concrete sport is detected/confirmed.
# ---------------------------------------------------------------------------
iphone = replace_once_or_present(
    iphone,
    "    @Published private(set) var effectiveActivity: ActivityKind = .walking\n",
    "    @Published private(set) var effectiveActivity: ActivityKind = .automatic\n",
    "effectiveActivity: ActivityKind = .automatic",
    "iphone neutral auto startup",
)
iphone = replace_once_or_present(
    iphone,
    "    @Published private(set) var suggestedFinalActivity: ActivityKind = .walking\n",
    "    @Published private(set) var suggestedFinalActivity: ActivityKind = .other\n",
    "suggestedFinalActivity: ActivityKind = .other",
    "iphone neutral finish suggestion",
)
iphone = replace_once_or_present(
    iphone,
    "    private var lastEffectiveActivity: ActivityKind = .walking\n",
    "    private var lastEffectiveActivity: ActivityKind = .automatic\n",
    "lastEffectiveActivity: ActivityKind = .automatic",
    "iphone neutral last activity",
)
iphone = replace_once_or_present(
    iphone,
    "        effectiveActivity = activity.isAutomatic ? .walking : activity\n",
    "        effectiveActivity = activity.isAutomatic ? .automatic : activity\n",
    "effectiveActivity = activity.isAutomatic ? .automatic : activity",
    "iphone auto selection must stay neutral",
)
iphone = replace_once_or_present(
    iphone,
    '''        if !keepActivity {
            selectedActivity = .automatic
            effectiveActivity = .walking
        }
''',
    '''        if !keepActivity {
            selectedActivity = .automatic
            effectiveActivity = .automatic
        }
''',
    "selectedActivity = .automatic\n            effectiveActivity = .automatic",
    "iphone reset must stay neutral",
)

watch = replace_once_or_present(
    watch,
    "    @Published private(set) var effectiveActivity: ActivityKind = .walking\n",
    "    @Published private(set) var effectiveActivity: ActivityKind = .automatic\n",
    "effectiveActivity: ActivityKind = .automatic",
    "watch neutral auto startup",
)
watch = replace_once_or_present(
    watch,
    "        return activity.isAutomatic ? .walking : activity\n",
    "        return activity.isAutomatic ? .automatic : activity\n",
    "return activity.isAutomatic ? .automatic : activity",
    "watch automatic initial activity",
)
watch = replace_once_or_present(
    watch,
    '''            if selectedActivity.isAutomatic {
                automaticActivityStartedAt = startedAt ?? Date()
            }
''',
    '''            if selectedActivity.isAutomatic {
                // Do not count provisional startup time as walking (or any
                // concrete sport). Accounting starts with the first real Auto
                // decision below.
                automaticActivityStartedAt = nil
                automaticActivitySeconds = [:]
            }
''',
    "Do not count provisional startup time as walking",
    "watch remove initial walking accounting",
)
watch = replace_once_or_present(
    watch,
    '''               let decision = WatchAutoPolicy.decision(
                    from: activity,
                    elapsedSeconds: self.elapsedSeconds,
                    distanceMeters: self.distanceMeters,
                    elevationGainMeters: self.elevationGainMeters,
                    elevationLossMeters: self.elevationLossMeters
               ) {
''',
    '''               let decision = WatchAutoPolicy.decision(
                    from: activity,
                    elapsedSeconds: self.elapsedSeconds,
                    distanceMeters: self.distanceMeters,
                    elevationGainMeters: self.elevationGainMeters,
                    elevationLossMeters: self.elevationLossMeters,
                    speedMps: self.currentSpeedMps,
                    cadenceSPM: self.cadenceSPM
               ) {
''',
    "speedMps: self.currentSpeedMps,\n                    cadenceSPM: self.cadenceSPM",
    "watch feed GPS/cadence to auto sport",
)
watch = replace_once_or_present(
    watch,
    "        let dwell = Swift.max(decision.dwellSeconds, 10)\n",
    "        let dwell = Swift.max(decision.dwellSeconds, 1.5)\n",
    "Swift.max(decision.dwellSeconds, 1.5)",
    "watch responsive auto sport dwell",
)
watch = replace_once_or_present(
    watch,
    '''        else {
            return effectiveActivity
        }

        return activity
''',
    '''        else {
            return effectiveActivity.isAutomatic ? .other : effectiveActivity
        }

        return activity
''',
    "return effectiveActivity.isAutomatic ? .other : effectiveActivity",
    "watch neutral finish fallback",
)

# ---------------------------------------------------------------------------
# HealthKit reconciliation must not invent an initial walking/Auto segment.
# It begins only when the Watch has a concrete detected activity.
# ---------------------------------------------------------------------------
reconciler = replace_once_or_present(
    reconciler,
    '''                activePlan = Plan(
                    sessionID: snapshot.sessionID,
                    segments: [Segment(activity: snapshot.effectiveActivity, startedAt: now, endedAt: nil)],
                    stoppedAt: nil,
                    routeExpected: false
                )
''',
    '''                activePlan = Plan(
                    sessionID: snapshot.sessionID,
                    segments: snapshot.effectiveActivity.isAutomatic
                        ? []
                        : [Segment(activity: snapshot.effectiveActivity, startedAt: now, endedAt: nil)],
                    stoppedAt: nil,
                    routeExpected: false
                )
''',
    "segments: snapshot.effectiveActivity.isAutomatic",
    "reconciler neutral initial segment",
)
reconciler = replace_once_or_present(
    reconciler,
    '''            } else if snapshot.phase == .active,
                      previous?.effectiveActivity != snapshot.effectiveActivity,
                      activePlan?.segments.last?.activity != snapshot.effectiveActivity {
                closeCurrentSegment(at: now)
                activePlan?.segments.append(
                    Segment(activity: snapshot.effectiveActivity, startedAt: now, endedAt: nil)
                )
            }
''',
    '''            } else if snapshot.phase == .active,
                      !snapshot.effectiveActivity.isAutomatic,
                      previous?.effectiveActivity != snapshot.effectiveActivity,
                      activePlan?.segments.last?.activity != snapshot.effectiveActivity {
                closeCurrentSegment(at: now)
                activePlan?.segments.append(
                    Segment(activity: snapshot.effectiveActivity, startedAt: now, endedAt: nil)
                )
            }
''',
    "!snapshot.effectiveActivity.isAutomatic,\n                      previous?.effectiveActivity",
    "reconciler concrete transitions only",
)

IPHONE.write_text(iphone, encoding="utf-8")
WATCH.write_text(watch, encoding="utf-8")
RECONCILER.write_text(reconciler, encoding="utf-8")

# Fail closed. These tokens describe the product behavior we are validating.
for token in [
    "effectiveActivity: ActivityKind = .automatic",
    "effectiveActivity = activity.isAutomatic ? .automatic : activity",
    "suggestedFinalActivity: ActivityKind = .other",
]:
    if token not in iphone:
        raise SystemExit(f"iphone auto behavior token missing: {token}")

for token in [
    "return activity.isAutomatic ? .automatic : activity",
    "Do not count provisional startup time as walking",
    "speedMps: self.currentSpeedMps",
    "cadenceSPM: self.cadenceSPM",
    "Swift.max(decision.dwellSeconds, 1.5)",
]:
    if token not in watch:
        raise SystemExit(f"watch auto behavior token missing: {token}")

for token in [
    "segments: snapshot.effectiveActivity.isAutomatic",
    "!snapshot.effectiveActivity.isAutomatic",
]:
    if token not in reconciler:
        raise SystemExit(f"reconciler auto behavior token missing: {token}")

print("AUTO BEHAVIOR BUILD PATCH: OK")
