#!/usr/bin/env python3
"""Run the field auto-pause patch and validate generated Swift escaping.

The field patch embeds Swift source in Python triple-quoted strings.  A Swift
separator written as "\\n" in that template is interpreted by Python before it
is written, which can otherwise leave a literal newline between Swift quotes
and make SessionStore.swift fail to parse.

Keep this runner as the generated-source-chain entry point for the field patch:
it repairs that exact generator boundary and fails closed if the expected Swift
form is not present afterwards.
"""

from pathlib import Path
import runpy


ROOT = Path(__file__).resolve().parent
PATCH = ROOT / "APPLY_AUTO_PAUSE_FIELD_FIX_PATCH.py"
STORE = ROOT / "iphone/Sources/SessionStore.swift"


if not PATCH.is_file():
    raise SystemExit(f"field auto-pause patch missing: {PATCH}")
if not STORE.is_file():
    raise SystemExit(f"SessionStore.swift missing: {STORE}")

runpy.run_path(str(PATCH), run_name="__main__")

text = STORE.read_text(encoding="utf-8")
broken = 'text.split(separator: "\n", omittingEmptySubsequences: true)'
fixed = r'text.split(separator: "\n", omittingEmptySubsequences: true)'

broken_count = text.count(broken)
if broken_count > 1:
    raise SystemExit(
        "field auto-pause Swift escape repair: "
        f"expected at most one malformed separator, got {broken_count}"
    )
if broken_count == 1:
    text = text.replace(broken, fixed, 1)
    STORE.write_text(text, encoding="utf-8")

verified = STORE.read_text(encoding="utf-8")
if broken in verified:
    raise SystemExit("field auto-pause Swift escape repair did not remove malformed separator")
if fixed not in verified:
    raise SystemExit("field auto-pause Swift escape repair: expected valid Swift separator missing")

print("AUTO PAUSE FIELD FIX PATCH + SWIFT ESCAPE VALIDATION: OK")
