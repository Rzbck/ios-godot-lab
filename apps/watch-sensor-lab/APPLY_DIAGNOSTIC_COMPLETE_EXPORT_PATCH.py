#!/usr/bin/env python3
"""Expose complete per-session raw telemetry through the existing USB API.

The previous diagnostic reader intentionally returned at most 200 records and
excluded motion samples by default. That is convenient for quick inspection but
insufficient for physical-run forensics. This patch adds one explicit reserved
kind, `__complete__`, which returns the entire persisted session JSONL in
chronological order, including motion samples, with metadata that states the
export is complete.

No new transport is introduced: Windows continues to use WSL.ps1 -> usbmux ->
read-only DiagnosticService.
"""
from pathlib import Path


ROOT = Path(__file__).resolve().parent
STORE = ROOT / "iphone/Sources/SessionStore.swift"
DIAG = ROOT / "iphone/Sources/DiagnosticService.swift"


def replace_once_or_present(text: str, old: str, new: str, marker: str, label: str) -> str:
    if marker in text:
        return text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, got {count}")
    return text.replace(old, new, 1)


store = STORE.read_text(encoding="utf-8")
diag = DIAG.read_text(encoding="utf-8")

# The field-fix reader already parses every line of samples.jsonl before taking
# its 200-record tail. Preserve that implementation, but make the complete mode
# explicitly bypass kind filtering, motion suppression and the tail limit.
store = replace_once_or_present(
    store,
    '''        let formatter = ISO8601DateFormatter()\n        var records: [[String: Any]] = []\n\n        for line in text.split(separator: "\\n", omittingEmptySubsequences: true) {\n''',
    '''        let formatter = ISO8601DateFormatter()\n        let completeExport = kind == "__complete__" // DIAGNOSTIC_COMPLETE_SESSION_EXPORT\n        var records: [[String: Any]] = []\n\n        for line in text.split(separator: "\\n", omittingEmptySubsequences: true) {\n''',
    "// DIAGNOSTIC_COMPLETE_SESSION_EXPORT",
    "complete session export marker",
)

store = replace_once_or_present(
    store,
    '''            if let kind {\n                let matches =\n                    kind == recordType\n                    || kind == sampleKind\n                    || kind == eventName\n                if !matches { continue }\n            } else if recordType == "sample", sampleKind == "motion" {\n                continue\n            }\n''',
    '''            if let kind, !completeExport {\n                let matches =\n                    kind == recordType\n                    || kind == sampleKind\n                    || kind == eventName\n                if !matches { continue }\n            } else if !completeExport, recordType == "sample", sampleKind == "motion" {\n                continue\n            }\n''',
    "if let kind, !completeExport",
    "complete export must include motion and all kinds",
)

store = replace_once_or_present(
    store,
    '''        let safeLimit = min(200, max(1, limit))\n        return Array(records.suffix(safeLimit).reversed())\n''',
    '''        if completeExport { // DIAGNOSTIC_COMPLETE_CHRONOLOGICAL_RETURN\n            return records\n        }\n\n        let safeLimit = min(200, max(1, limit))\n        return Array(records.suffix(safeLimit).reversed())\n''',
    "// DIAGNOSTIC_COMPLETE_CHRONOLOGICAL_RETURN",
    "complete export must bypass 200-record truncation",
)

# Make the API response self-describing so a future AI/user can verify that the
# file is exhaustive rather than accidentally analysing another 200-record tail.
diag = replace_once_or_present(
    diag,
    '''                return envelope(\n                    ok: true,\n                    command: command,\n                    data: [\n                        "records": tracker.diagnosticSessionRecords(\n                            sessionID: sessionID,\n                            limit: limit,\n                            kind: kind\n                        ),\n                        "limit": limit,\n                        "kind": kind.map { $0 as Any } ?? NSNull(),\n                        "session_id": sessionID,\n                        "source": "session_raw", // DIAGNOSTIC_SESSION_RAW_LOGS\n                        "source_timestamp_preserved": true,\n                        "motion_excluded_by_default": kind == nil,\n                    ]\n                )\n''',
    '''                let completeExport = kind == "__complete__"\n                let records = tracker.diagnosticSessionRecords(\n                    sessionID: sessionID,\n                    limit: limit,\n                    kind: kind\n                )\n\n                return envelope(\n                    ok: true,\n                    command: command,\n                    data: [\n                        "records": records,\n                        "limit": completeExport ? records.count : limit,\n                        "kind": kind.map { $0 as Any } ?? NSNull(),\n                        "session_id": sessionID,\n                        "source": "session_raw", // DIAGNOSTIC_SESSION_RAW_LOGS\n                        "source_timestamp_preserved": true,\n                        "motion_excluded_by_default": !completeExport && kind == nil,\n                        "complete": completeExport, // DIAGNOSTIC_COMPLETE_EXPORT_METADATA\n                        "record_count": records.count,\n                        "motion_included": completeExport,\n                        "order": completeExport ? "chronological" : "newest_first",\n                    ]\n                )\n''',
    "// DIAGNOSTIC_COMPLETE_EXPORT_METADATA",
    "complete export response metadata",
)

for name, text, tokens in [
    (
        "store",
        store,
        [
            "// DIAGNOSTIC_COMPLETE_SESSION_EXPORT",
            "// DIAGNOSTIC_COMPLETE_CHRONOLOGICAL_RETURN",
            'kind == "__complete__"',
        ],
    ),
    (
        "diag",
        diag,
        [
            "// DIAGNOSTIC_COMPLETE_EXPORT_METADATA",
            '"motion_included": completeExport',
            '"order": completeExport ? "chronological" : "newest_first"',
        ],
    ),
]:
    for token in tokens:
        if token not in text:
            raise SystemExit(f"{name}: required complete-export token missing: {token}")

STORE.write_text(store, encoding="utf-8")
DIAG.write_text(diag, encoding="utf-8")

print("DIAGNOSTIC COMPLETE SESSION EXPORT PATCH: OK")
