#!/usr/bin/env python3
"""Run the reactivity/haptics patch with deterministic compatibility repairs.

The underlying patch intentionally requires exact source matches. The stability
test file contains two identical historical `pauseDwell(.walking) == 6.0`
assertions, so a one-match helper cannot distinguish them. Repair that generator
boundary in-memory, then execute the resulting patch.

The new pedometer block supersedes the older auto-resume probe block, but must
retain that older integration marker so the complete generated-source chain is
safe to execute a second time. Runtime behavior is unchanged by that marker.
"""
from pathlib import Path


ROOT = Path(__file__).resolve().parent
PATCH = ROOT / "APPLY_AUTO_PAUSE_REACTIVITY_HAPTICS_PATCH.py"
WATCH = ROOT / "watch/Sources/SensorModel.swift"

if not PATCH.is_file():
    raise SystemExit(f"reactivity/haptics patch missing: {PATCH}")
if not WATCH.is_file():
    raise SystemExit(f"Watch SensorModel missing: {WATCH}")

source = PATCH.read_text(encoding="utf-8")
start_marker = "stability_tests = replace_once_or_present(\n    stability_tests,\n"
end_marker = "\n\nfor name, text, required in ["
start = source.find(start_marker)
end = source.find(end_marker, start)
if start < 0 or end < 0:
    raise SystemExit("reactivity/haptics runner: stability-test repair block not found")

replacement = r'''if "// FIELD_1789537681642_REACTIVE_DWELL" not in stability_tests:
    old_dwell = "        XCTAssertEqual(TrackerAutoPauseStabilityPolicy.pauseDwell(for: .walking), 6.0)\n"
    if stability_tests.count(old_dwell) != 2:
        raise SystemExit(
            "walking dwell regressions: expected exactly two 6 s assertions, "
            f"got {stability_tests.count(old_dwell)}"
        )
    stability_tests = stability_tests.replace(
        old_dwell,
        "        XCTAssertEqual(TrackerAutoPauseStabilityPolicy.pauseDwell(for: .walking), 4.0) // FIELD_1789537681642_REACTIVE_DWELL\n",
        1,
    )
    stability_tests = stability_tests.replace(
        old_dwell,
        "        XCTAssertEqual(TrackerAutoPauseStabilityPolicy.pauseDwell(for: .walking), 4.0) // FIELD_1789537681642_SECOND_DWELL\n",
        1,
    )'''

source = source[:start] + replacement + source[end:]
namespace = {
    "__name__": "__main__",
    "__file__": str(PATCH),
}
exec(compile(source, str(PATCH), "exec"), namespace, namespace)

# Preserve the integration marker owned by APPLY_AUTO_RESUME_RUNTIME_PATCH.py.
# The reactivity patch replaces that whole callback block, so without this
# harmless marker the second generated-chain pass tries to apply the old block
# again and fails closed.
watch = WATCH.read_text(encoding="utf-8")
legacy_marker = "// AUTO_RESUME_PEDOMETER_PROBE_ONLY"
new_marker = "// AUTO_RESUME_REJECT_PREPAUSE_PEDOMETER"
if legacy_marker not in watch:
    if watch.count(new_marker) != 1:
        raise SystemExit(
            "reactivity/haptics compatibility: expected one new pedometer marker, "
            f"got {watch.count(new_marker)}"
        )
    watch = watch.replace(
        new_marker,
        legacy_marker + "\n                            " + new_marker,
        1,
    )
    WATCH.write_text(watch, encoding="utf-8")

verified = WATCH.read_text(encoding="utf-8")
for marker in [legacy_marker, new_marker]:
    if verified.count(marker) != 1:
        raise SystemExit(
            f"reactivity/haptics compatibility marker count invalid: {marker}"
        )

print("AUTO PAUSE REACTIVITY + HAPTICS RUNNER: OK")
