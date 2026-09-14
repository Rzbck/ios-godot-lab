#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys

"""Idempotent entry point for the historical-correction patch.

SESSION_SYNC_PATCH.py applies APPLY_HISTORICAL_CORRECTION_DISTANCE_PATCH.py during
CI before Xcode generation. The Xcode projects also run the historical patch as a
pre-build safety gate. Between those two invocations SESSION_SYNC_PATCH normalizes
some generated Swift literals, so the original patch script's strict textual
"already applied" check can become false even though the semantic patch is fully
present. A second direct invocation then tries to patch an already-patched source
and fails before compilation.

This wrapper detects the semantic final state across every file touched by the
historical patch. If that state is complete, it exits successfully. Otherwise it
runs the original patch exactly once, preserving the safety gate for direct Xcode
builds that did not go through SESSION_SYNC_PATCH first.
"""

root = Path(__file__).resolve().parent
watch_file = root / "watch" / "Sources" / "WatchAutoHealthReconciler.swift"
core_file = root / "iphone" / "Sources" / "HistoricalHealthKitRepairV4.swift"
create_file = root / "iphone" / "Sources" / "HistoricalHealthKitRepairV4HealthCreate.swift"
verify_file = root / "iphone" / "Sources" / "HistoricalHealthKitRepairV4HealthVerify.swift"
full_fidelity_file = root / "iphone" / "Sources" / "HistoricalHealthKitFullFidelity.swift"
original_patch = root / "APPLY_HISTORICAL_CORRECTION_DISTANCE_PATCH.py"

required_files = [
    watch_file,
    core_file,
    create_file,
    verify_file,
    full_fidelity_file,
    original_patch,
]
missing = [str(path) for path in required_files if not path.exists()]
if missing:
    print("[historical-correction-distance-runner] missing required file(s):")
    for path in missing:
        print(f"  - {path}")
    raise SystemExit(2)

watch_text = watch_file.read_text(encoding="utf-8")
core_text = core_file.read_text(encoding="utf-8")
create_text = create_file.read_text(encoding="utf-8")
verify_text = verify_file.read_text(encoding="utf-8")
full_fidelity_text = full_fidelity_file.read_text(encoding="utf-8")

semantic_final_state = all(
    [
        "func historicalCorrectionDistanceAuthority(" in watch_text,
        "correction_distance_m" in watch_text,
        "restoreDistanceIdentifier(for: targetActivity)" in watch_text,
        "func replacementCandidateSourceState(" in core_text,
        "func creationPreflight(" in core_text,
        "func finalizationPreflight(" in core_text,
        "func finalizeNormalSourceCorrection(" in core_text,
        "func normalSourceCount(" in core_text,
        "func replaceGeneratedCandidate(" in core_text,
        "created.replacementCandidate.normalUUIDs" in create_text,
        "source.expectedNormalUUIDs" in create_text,
        "source.expectedGeneratedUUIDs" in create_text,
        "normal_workout_count" in verify_text,
        "func startIndependentWatchRoute(" in full_fidelity_text,
    ]
)

if semantic_final_state:
    print("[historical-correction-distance-runner] semantic final state already present; skip duplicate patch")
    raise SystemExit(0)

print("[historical-correction-distance-runner] semantic final state incomplete; applying original patch")
completed = subprocess.run(
    [sys.executable, str(original_patch)],
    cwd=str(root),
    check=False,
)
raise SystemExit(completed.returncode)
