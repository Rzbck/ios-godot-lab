#!/usr/bin/env python3
"""Run the reactivity/haptics patch with deterministic test-expectation repair.

The underlying patch intentionally requires exact source matches. The stability
test file contains two identical historical `pauseDwell(.walking) == 6.0`
assertions, so a one-match helper cannot distinguish them. Repair that generator
boundary in-memory, then execute the resulting patch. Runtime/source changes are
unchanged.
"""
from pathlib import Path


ROOT = Path(__file__).resolve().parent
PATCH = ROOT / "APPLY_AUTO_PAUSE_REACTIVITY_HAPTICS_PATCH.py"

if not PATCH.is_file():
    raise SystemExit(f"reactivity/haptics patch missing: {PATCH}")

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
print("AUTO PAUSE REACTIVITY + HAPTICS RUNNER: OK")
