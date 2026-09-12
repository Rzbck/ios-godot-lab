#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(__file__).resolve().parent

shared = (
    root / "Shared/TrackerShared.swift"
).read_text(encoding="utf-8")

iphone_model = (
    root / "iphone/Sources/TrackerModel.swift"
).read_text(encoding="utf-8")

watch_model = (
    root / "watch/Sources/SensorModel.swift"
).read_text(encoding="utf-8")


def ui_source(folder: Path) -> str:
    parts = []

    for path in sorted(folder.rglob("*.swift")):
        text = path.read_text(encoding="utf-8")

        if "import SwiftUI" in text:
            parts.append(
                f"\n// FILE: {path.name}\n{text}"
            )

    return "\n".join(parts)


iphone_ui = ui_source(root / "iphone/Sources")
watch_ui = ui_source(root / "watch/Sources")

errors = []

# Cross-device parity is intentionally limited to the LIVE workout workflow.
# Historical HealthKit mutation is no longer a shared iPhone/Watch capability:
# it has one active product surface on iPhone only. The legacy protocol member
# may remain temporarily while the migration is hardware-validated, but no UI
# is required (or allowed by CHECK_PRODUCT_INVARIANTS.py) to expose it.
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
        errors.append(
            f"Shared capability absente: {capability}"
        )

if "protocol TrackerSharedWorkflowSurface" not in shared:
    errors.append(
        "TrackerSharedWorkflowSurface absent"
    )

if (
    "extension TrackerModel: "
    "TrackerSharedWorkflowSurface"
    not in iphone_model
):
    errors.append(
        "TrackerModel iPhone hors workflow partagé"
    )

if (
    "extension SensorModel: "
    "TrackerSharedWorkflowSurface"
    not in watch_model
):
    errors.append(
        "SensorModel Watch hors workflow partagé"
    )

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
        errors.append(
            f"iPhone UI sans capacité: {token}"
        )

    if token not in watch_ui:
        errors.append(
            f"Watch UI sans capacité: {token}"
        )

iphone_forbidden = [
    "tracker.startFromPhone()",
    "tracker.pauseFromPhone()",
    "tracker.resumeFromPhone()",
    "tracker.stopFromPhone(",
    "tracker.setAutoPauseEnabled(",
    "tracker.selectActivity(",
]

watch_forbidden = [
    "model.start()",
    "model.pause()",
    "model.resume()",
    "model.stop()",
    "model.finish(",
    "model.setAutoPauseEnabled(",
    "model.selectActivity(",
]

for forbidden in iphone_forbidden:
    if forbidden in iphone_ui:
        errors.append(
            "iPhone UI contourne le workflow partagé: "
            + forbidden
        )

for forbidden in watch_forbidden:
    if forbidden in watch_ui:
        errors.append(
            "Watch UI contourne le workflow partagé: "
            + forbidden
        )

if errors:
    print(
        "TRACKER WORKFLOW PARITY: FAIL",
        file=sys.stderr
    )

    for error in errors:
        print(f" - {error}", file=sys.stderr)

    sys.exit(1)

print("TRACKER WORKFLOW PARITY: OK")
print("Shared LIVE capabilities:")

for capability in required_capabilities:
    print(f" - {capability}")

print("Historical HealthKit mutation: iPhone-only product surface")
