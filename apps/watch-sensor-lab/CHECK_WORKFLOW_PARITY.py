#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(__file__).resolve().parent

shared = (root / "Shared/TrackerShared.swift").read_text(encoding="utf-8")
iphone_model = (root / "iphone/Sources/TrackerModel.swift").read_text(encoding="utf-8")
watch_model = (root / "watch/Sources/SensorModel.swift").read_text(encoding="utf-8")

iphone_ui = (
    (root / "iphone/Sources/ActivityExperienceView.swift").read_text(encoding="utf-8")
)

watch_ui = "\n".join([
    (root / "watch/Sources/WatchSensorLabApp.swift").read_text(encoding="utf-8"),
    (root / "watch/Sources/WatchActiveWorkoutView.swift").read_text(encoding="utf-8"),
])

errors = []

required_capabilities = [
    "activitySelection",
    "start",
    "autoPauseToggle",
    "pause",
    "resume",
    "finishReview",
    "finishDisposition",
    "purge",
]

for capability in required_capabilities:
    if f"case {capability}" not in shared:
        errors.append(f"Shared capability absente: {capability}")

if "protocol TrackerSharedWorkflowSurface" not in shared:
    errors.append("TrackerSharedWorkflowSurface absent du code partagé")

if "extension TrackerModel: TrackerSharedWorkflowSurface" not in iphone_model:
    errors.append("TrackerModel iPhone ne respecte pas le workflow partagé")

if "extension SensorModel: TrackerSharedWorkflowSurface" not in watch_model:
    errors.append("SensorModel Watch ne respecte pas le workflow partagé")

required_ui_tokens = [
    "workflowStart",
    "workflowSelectActivity",
    "workflowSetAutoPauseEnabled",
    "workflowPause",
    "workflowResume",
    "workflowFinish",
    "workflowFinishReview",
]

for token in required_ui_tokens:
    if token not in iphone_ui:
        errors.append(f"iPhone UI n'expose pas le workflow commun: {token}")

    if token not in watch_ui:
        errors.append(f"Watch UI n'expose pas le workflow commun: {token}")

for forbidden in [
    "tracker.startFromPhone()",
    "tracker.pauseFromPhone()",
    "tracker.resumeFromPhone()",
    "tracker.stopFromPhone(",
]:
    if forbidden in iphone_ui:
        errors.append(f"iPhone UI contourne le workflow partagé: {forbidden}")

for forbidden in [
    "model.start()",
    "model.pause()",
    "model.resume()",
    "model.finish(",
]:
    if forbidden in watch_ui:
        errors.append(f"Watch UI contourne le workflow partagé: {forbidden}")

if errors:
    print("TRACKER WORKFLOW PARITY: FAIL", file=sys.stderr)
    for error in errors:
        print(f" - {error}", file=sys.stderr)
    sys.exit(1)

print("TRACKER WORKFLOW PARITY: OK")
print("Shared capabilities:")
for capability in required_capabilities:
    print(f" - {capability}")
