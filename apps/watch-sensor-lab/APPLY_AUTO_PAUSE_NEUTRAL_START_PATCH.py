#!/usr/bin/env python3
"""Allow neutral Auto startup to use the conservative auto-pause profile.

Field session 1789535250518 on build 6884591568c8f71cc9e4246c10ff0bf1045d2102 proved that the Watch had
corroborated stillness, zero cadence and stale GPS speed, but pause evaluation
failed closed only because the neutral Auto placeholder (`.automatic`) was not
listed as a supported auto-pause activity.

Keep Auto neutral for sport identification.  This patch changes only the pause
control profile while no concrete sport has been detected yet: `.automatic`
uses the conservative walking thresholds/dwells.  Generic unsupported sports
remain fail-closed.
"""
from pathlib import Path


ROOT = Path(__file__).resolve().parent
POLICY = ROOT / "Shared/TrackerAutoPauseStabilityPolicy.swift"
WATCH = ROOT / "watch/Sources/SensorModel.swift"
TESTS = ROOT / "Tests/TrackerAutoPauseStabilityPolicyTests.swift"


def replace_once_or_present(
    text: str,
    old: str,
    new: str,
    marker: str,
    label: str,
) -> str:
    if marker in text:
        return text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, got {count}")
    return text.replace(old, new, 1)


policy = POLICY.read_text(encoding="utf-8")
watch = WATCH.read_text(encoding="utf-8")
tests = TESTS.read_text(encoding="utf-8")

# ---------------------------------------------------------------------------
# Shared pause profile: `.automatic` is not a detected sport, but while Auto is
# still neutral it must be allowed to pause from corroborated stillness.  Reuse
# the conservative walking profile without changing Auto sport classification.
# ---------------------------------------------------------------------------
marker = "// AUTO_PAUSE_NEUTRAL_AUTO_PROFILE"
if marker not in policy:
    enum_anchor = "enum TrackerAutoPauseStabilityPolicy {\n"
    if policy.count(enum_anchor) != 1:
        raise SystemExit("neutral Auto policy marker: enum anchor mismatch")
    policy = policy.replace(
        enum_anchor,
        enum_anchor
        + "    // AUTO_PAUSE_NEUTRAL_AUTO_PROFILE: neutral Auto uses the conservative walking pause profile.\n",
        1,
    )

    broad = (
        "        case .walking, .hiking, .running, .trackAndField, .cycling, .handCycling:\n"
    )
    broad_count = policy.count(broad)
    if broad_count != 2:
        raise SystemExit(
            "neutral Auto broad profile: expected 2 locomotor case lists, "
            f"got {broad_count}"
        )
    policy = policy.replace(
        broad,
        "        case .automatic, .walking, .hiking, .running, .trackAndField, .cycling, .handCycling:\n",
    )

    walking_profile = "        case .walking, .hiking:\n"
    walking_count = policy.count(walking_profile)
    if walking_count != 5:
        raise SystemExit(
            "neutral Auto walking profile: expected 5 walking case lists, "
            f"got {walking_count}"
        )
    policy = policy.replace(
        walking_profile,
        "        case .automatic, .walking, .hiking:\n",
    )

# Keep decision telemetry consistent with the shared policy.  The candidate
# must report `candidate_allowed`, not `unsupported_activity`, for neutral Auto.
watch = replace_once_or_present(
    watch,
    '''        switch displayActivity {
        case .walking, .hiking:
            if speedFresh, speed > 0.35 { return "fresh_speed_veto" }
            if cadence >= 10 { return "cadence_veto" }
''',
    '''        switch displayActivity {
        case .automatic, .walking, .hiking: // AUTO_PAUSE_NEUTRAL_AUTO_EVALUATION
            if speedFresh, speed > 0.35 { return "fresh_speed_veto" }
            if cadence >= 10 { return "cadence_veto" }
''',
    "// AUTO_PAUSE_NEUTRAL_AUTO_EVALUATION",
    "neutral Auto evaluation reason",
)

# Replace the old regression that deliberately rejected `.automatic` with the
# field-proven behavior from session 1789535250518.  Unsupported real sports
# still fail closed.  This regression intentionally does not pin the exact
# pause dwell: later policy layers may tune timing while preserving the neutral
# Auto capability validated here.
tests = replace_once_or_present(
    tests,
    '''    func testAutomaticPlaceholderAndGenericSportsFailClosed() {
        for activity in [ActivityKind.automatic, .soccer, .yoga, .other] {
            XCTAssertFalse(TrackerAutoPauseStabilityPolicy.supports(activity))
            XCTAssertFalse(
                TrackerAutoPauseStabilityPolicy.shouldStagePause(
                    activity: activity,
                    enabled: true,
                    stationary: true,
                    speedMps: 0,
                    cadenceSPM: 0
                )
            )
        }
    }
''',
    '''    func testFieldSession1789535250518NeutralAutomaticCanPauseAfterFusedStillness() { // FIELD_1789535250518_NEUTRAL_AUTO_PAUSE
        XCTAssertTrue(TrackerAutoPauseStabilityPolicy.supports(.automatic))

        XCTAssertTrue(
            TrackerAutoPauseStabilityPolicy.shouldStagePause(
                activity: .automatic,
                enabled: true,
                stationary: true,
                speedMps: 0.4306655806345419,
                speedFresh: false,
                cadenceSPM: 0
            )
        )

        XCTAssertFalse(
            TrackerAutoPauseStabilityPolicy.shouldStagePause(
                activity: .automatic,
                enabled: true,
                stationary: true,
                speedMps: 0.4306655806345419,
                speedFresh: true,
                cadenceSPM: 0
            )
        )
    }

    func testNeutralAutomaticStillRequiresCorroboratedStillness() {
        XCTAssertFalse(
            TrackerAutoPauseStabilityPolicy.shouldStagePause(
                activity: .automatic,
                enabled: true,
                stationary: false,
                speedMps: 0,
                speedFresh: false,
                cadenceSPM: 0
            )
        )
    }

    func testGenericUnsupportedSportsStillFailClosed() {
        for activity in [ActivityKind.soccer, .yoga, .other] {
            XCTAssertFalse(TrackerAutoPauseStabilityPolicy.supports(activity))
            XCTAssertFalse(
                TrackerAutoPauseStabilityPolicy.shouldStagePause(
                    activity: activity,
                    enabled: true,
                    stationary: true,
                    speedMps: 0,
                    cadenceSPM: 0
                )
            )
        }
    }
''',
    "// FIELD_1789535250518_NEUTRAL_AUTO_PAUSE",
    "neutral Auto field regression",
)

for name, text, required in [
    (
        "policy",
        policy,
        [
            "// AUTO_PAUSE_NEUTRAL_AUTO_PROFILE",
            "case .automatic, .walking, .hiking:",
            "case .automatic, .walking, .hiking, .running, .trackAndField, .cycling, .handCycling:",
        ],
    ),
    (
        "watch",
        watch,
        ["// AUTO_PAUSE_NEUTRAL_AUTO_EVALUATION"],
    ),
    (
        "tests",
        tests,
        ["// FIELD_1789535250518_NEUTRAL_AUTO_PAUSE"],
    ),
]:
    for token in required:
        if token not in text:
            raise SystemExit(f"{name}: neutral Auto pause token missing: {token}")

POLICY.write_text(policy, encoding="utf-8")
WATCH.write_text(watch, encoding="utf-8")
TESTS.write_text(tests, encoding="utf-8")

# DEVICE_CANDIDATE_TRIGGER_20260916: no runtime effect; forces exact-SHA artifact build.
print("AUTO PAUSE NEUTRAL START PATCH: OK")
