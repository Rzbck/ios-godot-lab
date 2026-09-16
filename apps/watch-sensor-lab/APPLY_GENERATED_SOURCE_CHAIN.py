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
# comes next, then sensor fusion, runtime wake-up/anti-oscillation, evidence
# freshness, raw Watch inertial stillness + HealthKit Auto typing, the
# field-proven single-owner pause decision + durable diagnostics repair,
# neutral-Auto startup support, then the physical-run reactivity/haptics repair
# and complete forensic export added from session 1789537681642. The final
# follow-up patch applies field findings from combined session 1789561072024:
# brisk-walk classification, paused finish timing, and OSM product integration.
# Every repair preserves earlier integration markers so the complete chain
# remains safe to execute repeatedly in CI and Xcode builds.
apply("SESSION_SYNC_PATCH.py")
apply("APPLY_AUTO_BEHAVIOR_PATCH.py")
apply("APPLY_AUTO_PAUSE_FUSION_PATCH.py")
apply("APPLY_AUTO_RESUME_RUNTIME_PATCH.py")
apply("APPLY_AUTO_PAUSE_EVIDENCE_FRESHNESS_PATCH.py")
watch_path = ROOT / "watch/Sources/SensorModel.swift"
watch_text = watch_path.read_text(encoding="utf-8") if watch_path.is_file() else ""

field_fix_applied = (
    "AUTO_PAUSE_FIELD_FUSED_STAGE" in watch_text
    and "AUTO_PAUSE_FIELD_FUSED_CONFIRM" in watch_text
)

if field_fix_applied:
    print(
        "[generated-source-chain] "
        "APPLY_AUTO_PAUSE_INERTIAL_HEALTHKIT_PATCH.py "
        "(covered by field fix)"
    )
else:
    apply("APPLY_AUTO_PAUSE_INERTIAL_HEALTHKIT_PATCH.py")
apply("RUN_AUTO_PAUSE_FIELD_FIX_PATCH.py")
apply("APPLY_AUTO_PAUSE_NEUTRAL_START_PATCH.py")
apply("RUN_AUTO_PAUSE_REACTIVITY_HAPTICS_PATCH.py")
apply("APPLY_DIAGNOSTIC_COMPLETE_EXPORT_PATCH.py")
apply("APPLY_FIELD_FOLLOWUP_20260916_PATCH.py")

# FIELD_FOLLOWUP_1789561072024: generated runtime + UI regression gate.
print("WATCH SENSOR LAB GENERATED SOURCE CHAIN: OK")
