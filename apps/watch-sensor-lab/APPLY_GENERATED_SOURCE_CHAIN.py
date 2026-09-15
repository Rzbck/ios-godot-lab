#!/usr/bin/env python3
"""Apply the complete Watch Sensor Lab generated-source chain.

This is the only entry point CI should call before checking or compiling the
application. Individual patch scripts remain available to Xcode as local
pre-build safety gates, so every operation in this chain must be idempotent.
"""

from pathlib import Path
import runpy


ROOT = Path(__file__).resolve().parent


def apply(script: str) -> None:
    path = ROOT / script
    if not path.is_file():
        raise SystemExit(f"generated-source chain missing required script: {path}")
    print(f"[generated-source-chain] {script}")
    runpy.run_path(str(path), run_name="__main__")


# SESSION_SYNC_PATCH owns the established dependency order for auto-pause,
# terminal/runtime integrity, and historical correction. Reactive Auto behavior
# comes next, then sensor fusion, runtime wake-up/anti-oscillation, and finally
# pause evidence freshness. Every stage remains idempotent because CI and Xcode
# may apply the chain twice.
apply("SESSION_SYNC_PATCH.py")
apply("APPLY_AUTO_BEHAVIOR_PATCH.py")
apply("APPLY_AUTO_PAUSE_FUSION_PATCH.py")
apply("APPLY_AUTO_RESUME_RUNTIME_PATCH.py")
apply("APPLY_AUTO_PAUSE_EVIDENCE_FRESHNESS_PATCH.py")

print("WATCH SENSOR LAB GENERATED SOURCE CHAIN: OK")
