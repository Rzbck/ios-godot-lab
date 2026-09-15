#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(__file__).resolve().parent
repository_root = root.parents[1]

shared = (
    root / "Shared/TrackerShared.swift"
).read_text(encoding="utf-8")

session_control = (
    root / "Shared/TrackerSessionControl.swift"
).read_text(encoding="utf-8")

auto_policy = (
    root / "Shared/TrackerAutoPolicy.swift"
).read_text(encoding="utf-8")

iphone_model = (
    root / "iphone/Sources/TrackerModel.swift"
).read_text(encoding="utf-8")

watch_model = (
    root / "watch/Sources/SensorModel.swift"
).read_text(encoding="utf-8")

watch_auto_policy = (
    root / "watch/Sources/WatchAutoPolicy.swift"
).read_text(encoding="utf-8")

iphone_settings = (
    root / "iphone/Sources/TrackerSettingsView.swift"
).read_text(encoding="utf-8")

watch_auto_pause_settings = (
    root / "watch/Sources/WatchAutoPauseSettings.swift"
).read_text(encoding="utf-8")

codeowners_path = repository_root / ".github/CODEOWNERS"

selftest_service = (
    root / "iphone/Sources/AutomationSelfTestService.swift"
).read_text(encoding="utf-8")

tracker_app = (
    root / "iphone/Sources/TrackerApp.swift"
).read_text(encoding="utf-8")

iphone_project = (
    root / "iphone/project.yml"
).read_text(encoding="utf-8")

watch_project = (
    root / "watch/project.yml"
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
    errors.append("TrackerSharedWorkflowSurface absent")

if "extension TrackerModel: TrackerSharedWorkflowSurface" not in iphone_model:
    errors.append("TrackerModel iPhone hors workflow partagé")

if "extension SensorModel: TrackerSharedWorkflowSurface" not in watch_model:
    errors.append("SensorModel Watch hors workflow partagé")

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
        errors.append(f"iPhone UI sans capacité: {token}")
    if token not in watch_ui:
        errors.append(f"Watch UI sans capacité: {token}")

finish_surface_tokens = {
    "iPhone": (
        iphone_ui,
        [
            "PhoneFinishActivityReview",
            "workflowFinishReview.required",
            "Conserver les segments détectés",
            'Picker("Activité", selection: $selection)',
            "Enregistrer comme \\(selection.label)",
            "disposition: .preserveDetectedSegments",
            "disposition: .forceSingleActivity",
            "showFinishReview = false",
        ],
    ),
    "Watch": (
        watch_ui,
        [
            "WatchFinishActivityReview",
            "workflowFinishReview.required",
            "Conserver la détection Auto",
            'Picker("Activité", selection: $selection)',
            "Forcer · \\(selection.label)",
            "disposition: .preserveDetectedSegments",
            "disposition: .forceSingleActivity",
            "showFinishReview = false",
        ],
    ),
}

for surface, (source, tokens) in finish_surface_tokens.items():
    for token in tokens:
        if token not in source:
            errors.append(
                f"{surface} UI de fin incomplète: {token}"
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
        errors.append("iPhone UI contourne le workflow partagé: " + forbidden)
for forbidden in watch_forbidden:
    if forbidden in watch_ui:
        errors.append("Watch UI contourne le workflow partagé: " + forbidden)

for token in [
    "pendingControlToken",
    "makeControlCommand(",
    "parseControlAcknowledgement(",
    "ack.token == pendingControlToken",
]:
    if token not in iphone_model:
        errors.append(f"iPhone sans sérialisation de commande: {token}")

for token in [
    "lastControlToken",
    "parseControlCommand(",
    "message.revision == authorityRevision",
    'result: "stale_revision"',
    'result: "expired"',
]:
    if token not in watch_model:
        errors.append(f"Watch sans garde autoritaire de commande: {token}")

for forbidden in [
    "message.revision > pendingCommandAtRevision",
    "message.revision > previousRevision",
]:
    if forbidden in iphone_model:
        errors.append("Ancien ACK implicite par révision encore présent: " + forbidden)

# Pure cores stay portable: simulator, synthetic replay and device self-test
# execute the same rules without importing hardware/UI frameworks.
for name, source in [
    ("TrackerSessionControl", session_control),
    ("TrackerAutoPolicy", auto_policy),
]:
    for forbidden_import in [
        "import HealthKit",
        "import WatchConnectivity",
        "import CoreLocation",
        "import CoreMotion",
        "import SwiftUI",
    ]:
        if forbidden_import in source:
            errors.append(
                f"{name} dépend d'un framework matériel/UI: {forbidden_import}"
            )

for token in [
    "TrackerControlPolicy",
    "TrackerControlCodec",
    "staleRevision",
    "sessionMismatch",
    "invalidFinishActivity",
]:
    if token not in session_control:
        errors.append(f"Noyau contrôle déterministe incomplet: {token}")

for token in [
    "TrackerMotionEvidence",
    "TrackerAutoPolicy",
    "shouldStagePause",
    "shouldStageResume",
]:
    if token not in auto_policy:
        errors.append(f"Noyau Auto déterministe incomplet: {token}")

for token in [
    "TrackerAutoPolicy.decision",
    "TrackerAutoPolicy.shouldStagePause",
    "TrackerAutoPolicy.shouldStageResume",
]:
    if token not in watch_auto_policy:
        errors.append(
            f"WatchAutoPolicy ne délègue pas au noyau testable: {token}"
        )

# The product has one Auto-Pause toggle. Its short internal dwell is
# stabilization, never a duration the person configures. Check the actual
# settings surfaces so a refactor cannot bring back per-sport sliders.
for surface, source in [
    ("iPhone", iphone_settings),
    ("Watch", watch_auto_pause_settings),
]:
    if "Pause automatique" not in source and "Pause auto adaptative" not in source:
        errors.append(f"{surface} sans contrôle maître de pause automatique")
    if "Aucun délai à régler" not in source:
        errors.append(f"{surface} réintroduit une configuration de délai Auto")

iphone_settings_body = iphone_settings.split("struct TrackerSettingsView", 1)[-1]
watch_settings_body = watch_auto_pause_settings.split("struct WatchAutoPauseSettingsView", 1)[-1]
for surface, source in [
    ("iPhone", iphone_settings_body),
    ("Watch", watch_settings_body),
]:
    for forbidden in ["Slider(", "Stepper(", "pauseDwell", "resumeDwell"]:
        if forbidden in source:
            errors.append(
                f"{surface} expose encore un réglage de délai Auto: {forbidden}"
            )

# GitHub review routing remains app-only: this file must not depend on a
# repository-wide main branch policy which would affect unrelated apps.
if not codeowners_path.is_file():
    errors.append("CODEOWNERS Watch Sensor Lab absent")
else:
    codeowners = codeowners_path.read_text(encoding="utf-8")
    for token in [
        "/apps/watch-sensor-lab/** @Rzbck",
        "/.github/workflows/watch-sensor-lab-*.yml @Rzbck",
    ]:
        if token not in codeowners:
            errors.append(f"CODEOWNERS Watch Sensor Lab incomplet: {token}")

required_test_files = [
    root / "Tests/TrackerWorkflowContractTests.swift",
    root / "Tests/TrackerSessionControlTests.swift",
    root / "Tests/TrackerAutoPolicyTests.swift",
    root / "Tests/Support/TrackerAutomationScenario.swift",
    root / "Tests/TrackerAutomationScenarioTests.swift",
]
for path in required_test_files:
    if not path.is_file():
        errors.append(f"Suite déterministe absente: {path.relative_to(root)}")

# On-device self-test must remain a distinct, read-only USB surface.
for token in [
    'static let protocolName = "wsl_selftest_v1"',
    "static let devicePort: UInt16 = 37992",
    '"read_only": true',
    '"healthkit_mutation": false',
    '"workout_mutation": false',
    "TrackerControlPolicy.evaluate",
    "TrackerAutoPolicy.decision",
]:
    if token not in selftest_service:
        errors.append(f"Self-test USB incomplet: {token}")

for forbidden in [
    "import HealthKit",
    "import WatchConnectivity",
    "HKHealthStore(",
    "HKWorkoutSession(",
    "WCSession.",
    "NativeSessionStore(",
    "deleteAllSessions(",
    "startFromPhone(",
    "stopFromPhone(",
    "workflowStart(",
    "workflowFinish(",
]:
    if forbidden in selftest_service:
        errors.append(f"Self-test USB peut muter l'état réel: {forbidden}")

for token in [
    "AutomationSelfTestService.shared.start()",
    "AutomationSelfTestService.shared.stop()",
]:
    if token not in tracker_app:
        errors.append(f"Lifecycle self-test USB non câblé: {token}")

if iphone_project.count("../Shared/TrackerAutoPolicy.swift") < 2:
    errors.append("TrackerAutoPolicy absent de l'app iPhone ou de ses tests")
if "../Shared/TrackerAutoPolicy.swift" not in watch_project:
    errors.append("TrackerAutoPolicy absent de la target Watch")

selftest_client = root / "WSL_SELFTEST.ps1"
if not selftest_client.is_file():
    errors.append("Client USB WSL_SELFTEST.ps1 absent")

# Finish-review UI automation compiles the real production views against fake
# models that have no physical dependencies. This prevents accidental workout
# or HealthKit mutations while still exercising the actual SwiftUI surfaces.
ui_harness_files = [
    root / "UITestHarness/iPhone/FakeTrackerModel.swift",
    root / "UITestHarness/iPhone/FinishHarnessApp.swift",
    root / "UITestHarness/watch/FakeSensorModel.swift",
    root / "UITestHarness/watch/FinishHarnessApp.swift",
    root / "UITests/iPhoneFinishFlowUITests.swift",
    root / "UITests/WatchFinishFlowUITests.swift",
]
for path in ui_harness_files:
    if not path.is_file():
        errors.append(f"UI automation absente: {path.relative_to(root)}")

for path in [
    root / "UITestHarness/iPhone/FakeTrackerModel.swift",
    root / "UITestHarness/watch/FakeSensorModel.swift",
]:
    if path.is_file():
        text = path.read_text(encoding="utf-8")
        for forbidden in [
            "import HealthKit",
            "import WatchConnectivity",
            "import CoreMotion",
            "HKHealthStore(",
            "HKWorkoutSession(",
            "WCSession.",
            "NativeSessionStore(",
        ]:
            if forbidden in text:
                errors.append(
                    f"Harness UI non isolé ({path.name}): {forbidden}"
                )

for token in [
    "WatchSensorLabFinishUIHarness",
    "WatchSensorLabFinishUITests",
    "Sources/ActivityExperienceView.swift",
    "UITestHarness/iPhone/FakeTrackerModel.swift",
]:
    if token not in iphone_project:
        errors.append(f"Target UI iPhone incomplet: {token}")

for token in [
    "WatchSensorLabWatchFinishUIHarness",
    "WatchSensorLabWatchFinishUITests",
    "Sources/WatchActiveWorkoutView.swift",
    "UITestHarness/watch/FakeSensorModel.swift",
]:
    if token not in watch_project:
        errors.append(f"Target UI Watch incomplet: {token}")

if errors:
    print("TRACKER WORKFLOW PARITY: FAIL", file=sys.stderr)
    for error in errors:
        print(f" - {error}", file=sys.stderr)
    sys.exit(1)

print("TRACKER WORKFLOW PARITY: OK")
print("Shared LIVE capabilities:")
for capability in required_capabilities:
    print(f" - {capability}")
print("Finish review UI: iPhone + Watch preserve/choose/confirm surfaces present")
print("Session control: exact-token ACK + Watch revision guard")
print("Deterministic cores: session-control + Auto policy are platform independent")
print("Synthetic replay: versioned virtual-time scenarios present")
print("USB self-test: read-only, no HealthKit/workout/session-store mutation")
print("Finish UI automation: real production SwiftUI views + sensor-free fake models")
print("Historical HealthKit mutation: iPhone-only product surface")
