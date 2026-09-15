#!/usr/bin/env python3
"""Build-time deterministic iPhone/Watch session-control patch.

Temporary candidate patch for hardware validation. GitHub Actions applies this
script to the checked-out Swift sources before parity checks and compilation.
Once validated on iPhone + Apple Watch, fold the exact changes into the Swift
sources and remove this helper.
"""
from pathlib import Path
import runpy

ROOT = Path(__file__).resolve().parent
IPHONE = ROOT / "iphone/Sources/TrackerModel.swift"
WATCH = ROOT / "watch/Sources/SensorModel.swift"


def run_child_patch(name: str) -> None:
    """Run an idempotent child patch without letting a successful early exit
    prevent the rest of the generated-source chain from being verified."""
    try:
        runpy.run_path(str(ROOT / name), run_name="__main__")
    except SystemExit as error:
        if error.code not in (0, None):
            raise


def replace_once(text: str, old: str, new: str, label: str) -> str:
    # Candidate scripts may be invoked by CI and again by Xcode pre-build.
    # Treat their exact replacement as the idempotence marker instead of
    # requiring the pre-patch text on every pass.
    if old not in text:
        return text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, got {count}")
    return text.replace(old, new, 1)


def replace_block(text: str, start: str, end: str, replacement: str, label: str) -> str:
    if replacement in text or start not in text:
        return text
    a = text.find(start)
    if a < 0:
        raise SystemExit(f"{label}: start marker not found")
    b = text.find(end, a + len(start))
    if b < 0:
        raise SystemExit(f"{label}: end marker not found")
    return text[:a] + replacement + text[b:]


iphone = IPHONE.read_text(encoding="utf-8")
watch = WATCH.read_text(encoding="utf-8")

iphone = replace_once(
    iphone,
    "    private var pendingCommandAtRevision: Int64 = -1\n",
    "    private var pendingCommandAtRevision: Int64 = -1\n"
    "    private var pendingControlToken: String?\n",
    "iphone pending control token",
)

iphone = replace_block(
    iphone,
    "    private func requestControl(\n",
    "    private func configureLocation()",
    '''    private func requestControl(
        _ command: String,
        allowed: Bool,
        finishDisposition: TrackerFinishDisposition? = nil,
        finalActivity: ActivityKind? = nil
    ) {
        guard allowed, pendingCommand == nil else { return }

        let token = UUID().uuidString
        let baseRevision = lastAuthorityRevision
        pendingCommand = command
        pendingCommandAtRevision = baseRevision
        pendingControlToken = token

        store.appendEvent("control_requested", source: "iphone", payload: [
            "command": command,
            "control_token": token,
            "authority_revision": baseRevision,
            "finish_disposition": finishDisposition?.rawValue ?? "none",
            "final_activity": finalActivity?.rawValue ?? "none",
        ])

        statusMessage = "Commande \\(command) envoyée à la Watch…"

        var request = makeMessage(kind: .request)
        request.command = Self.makeControlCommand(command, token: token)
        request.revision = baseRevision
        request.timestamp = Date().timeIntervalSince1970
        request.finishDisposition = finishDisposition?.rawValue
        request.finalActivityOverride = finalActivity?.rawValue

        sendToWatch(request)

        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard
                let self,
                self.pendingCommand == command,
                self.pendingControlToken == token
            else { return }

            self.store.appendEvent("control_timeout", source: "iphone", payload: [
                "command": command,
                "control_token": token,
                "base_revision": baseRevision,
                "authority_revision": self.lastAuthorityRevision,
            ])
            self.pendingCommand = nil
            self.pendingCommandAtRevision = -1
            self.pendingControlToken = nil
            self.statusMessage = "Commande \\(command) expirée · état Watch conservé"
        }
    }

''',
    "iphone requestControl",
)

iphone = replace_once(
    iphone,
    "    private func applyAuthority(_ message: TrackerWireMessage) {\n",
    '''    private static func makeControlCommand(_ command: String, token: String) -> String {
        "control:\\(command):\\(token)"
    }

    private static func parseControlAcknowledgement(
        _ raw: String?
    ) -> (token: String, result: String)? {
        guard let raw, raw.hasPrefix("ack:") else { return nil }
        let parts = raw.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[1].isEmpty else { return nil }
        return (String(parts[1]), String(parts[2]))
    }

    private func applyAuthority(_ message: TrackerWireMessage) {
''',
    "iphone helpers",
)

iphone = replace_once(
    iphone,
    "        let previousRevision = lastAuthorityRevision\n        lastAuthorityRevision = message.revision\n",
    "        lastAuthorityRevision = message.revision\n",
    "iphone previous revision",
)

iphone = replace_once(
    iphone,
    "        let acknowledgedPending = pendingCommand != nil && message.revision > pendingCommandAtRevision\n\n",
    '''        var acknowledgedControl = false
        if
            let pendingControlToken,
            let ack = Self.parseControlAcknowledgement(message.command),
            ack.token == pendingControlToken
        {
            store.appendEvent("control_acknowledged", source: "watch", payload: [
                "command": pendingCommand ?? "unknown",
                "control_token": pendingControlToken,
                "command_result": ack.result,
                "authority_revision": message.revision,
            ])
            let command = pendingCommand ?? "unknown"
            pendingCommand = nil
            pendingCommandAtRevision = -1
            self.pendingControlToken = nil
            acknowledgedControl = true
            if ack.result != "accepted" {
                statusMessage = "Commande \\(command) refusée par la Watch · \\(ack.result)"
            }
        }

        let acknowledgedStart =
            pendingCommand == "start"
            && self.pendingControlToken == nil
            && message.sessionID == sessionID
            && (remotePhase == .active || remotePhase == .paused)

''',
    "iphone exact acknowledgement",
)

iphone = replace_once(
    iphone,
    '''        case .none:
            if message.phase == "ended" {
                if acknowledgedPending || message.revision > previousRevision {
                    pendingCommand = nil
                    pendingCommandAtRevision = -1
                }
                finishLocalSession(reason: "watch")
                return
            }
        }

        if acknowledgedPending {
            store.appendEvent("control_acknowledged", source: "watch", payload: [
                "command": pendingCommand ?? "unknown",
                "authority_revision": message.revision,
            ])
            pendingCommand = nil
            pendingCommandAtRevision = -1
        }
        updateLiveActivity(force: remotePhase != .active)
''',
    '''        case .none:
            if message.phase == "ended" {
                finishLocalSession(reason: "watch")
                return
            }
        }

        if acknowledgedStart {
            store.appendEvent("control_acknowledged", source: "watch", payload: [
                "command": "start",
                "command_result": "authority_started",
                "authority_revision": message.revision,
            ])
            pendingCommand = nil
            pendingCommandAtRevision = -1
            self.pendingControlToken = nil
        }
        _ = acknowledgedControl
        updateLiveActivity(force: remotePhase != .active)
''',
    "iphone remove revision ack",
)

# Existing teardown paths must also drop any pending control token. Use explicit
# self so an optional-binding local named pendingControlToken can never shadow
# the property during compilation.
iphone = iphone.replace(
    "pendingCommand = nil\n            pendingCommandAtRevision = -1\n",
    "pendingCommand = nil\n            pendingCommandAtRevision = -1\n            self.pendingControlToken = nil\n",
)
iphone = iphone.replace(
    "pendingCommand = nil\n        pendingCommandAtRevision = -1\n",
    "pendingCommand = nil\n        pendingCommandAtRevision = -1\n        self.pendingControlToken = nil\n",
)

watch = replace_once(
    watch,
    "    private var selectionRevision: Int64 = 0\n",
    "    private var selectionRevision: Int64 = 0\n"
    "    private var lastControlToken: String?\n"
    "    private var lastControlResult: String?\n",
    "watch control state",
)

watch = replace_once(
    watch,
    "    private func makeMessage(kind: TrackerWireMessage.Kind) -> TrackerWireMessage {\n        TrackerWireMessage(\n",
    "    private func makeMessage(kind: TrackerWireMessage.Kind) -> TrackerWireMessage {\n        var message = TrackerWireMessage(\n",
    "watch mutable message",
)
watch = replace_once(
    watch,
    "            activeEnergyKcal: activeEnergyKcal\n        )\n    }\n\n    private func sendAuthority",
    '''            activeEnergyKcal: activeEnergyKcal
        )
        if let token = lastControlToken, let result = lastControlResult {
            message.command = Self.makeControlAcknowledgement(token: token, result: result)
        }
        return message
    }

    private func sendAuthority''',
    "watch authority ack payload",
)

watch = replace_once(
    watch,
    "    private func handleRequest(_ message: TrackerWireMessage) {\n",
    '''    private static func parseControlCommand(
        _ raw: String?
    ) -> (command: String, token: String)? {
        guard let raw, raw.hasPrefix("control:") else { return nil }
        let parts = raw.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, !parts[1].isEmpty, !parts[2].isEmpty else { return nil }
        return (String(parts[1]), String(parts[2]))
    }

    private static func makeControlAcknowledgement(token: String, result: String) -> String {
        "ack:\\(token):\\(result)"
    }

    private func acknowledgeControl(_ token: String, result: String, ended: Bool = false) {
        lastControlToken = token
        lastControlResult = result
        sendAuthority(force: true, phaseOverride: ended ? "ended" : nil)
    }

    private func handleRequest(_ message: TrackerWireMessage) {
''',
    "watch helpers",
)

watch = replace_once(
    watch,
    "        guard let command = message.command else { return }\n        if command == \"start\" {\n",
    '''        guard let rawCommand = message.command else { return }

        if let control = Self.parseControlCommand(rawCommand) {
            let command = control.command
            let token = control.token

            if token == lastControlToken {
                acknowledgeControl(token, result: lastControlResult ?? "duplicate", ended: command == "stop" && !running)
                return
            }

            if Date().timeIntervalSince1970 - message.timestamp > 8 {
                acknowledgeControl(token, result: "expired")
                return
            }

            guard running, message.sessionID == sessionID else {
                acknowledgeControl(token, result: "session_mismatch")
                return
            }

            guard message.revision == authorityRevision else {
                acknowledgeControl(token, result: "stale_revision")
                return
            }

            switch command {
            case "pause":
                guard phase == .active else {
                    acknowledgeControl(token, result: "state_mismatch")
                    return
                }
                lastControlToken = token
                lastControlResult = "accepted"
                pause()

            case "resume":
                guard phase == .paused else {
                    acknowledgeControl(token, result: "state_mismatch")
                    return
                }
                lastControlToken = token
                lastControlResult = "accepted"
                resume()

            case "stop":
                let disposition =
                    message.finishDisposition
                        .flatMap(TrackerFinishDisposition.init(rawValue:))
                        ?? .preserveDetectedSegments
                let overrideActivity =
                    message.finalActivityOverride
                        .flatMap(ActivityKind.init(rawValue:))
                if disposition == .forceSingleActivity,
                   overrideActivity == nil || overrideActivity?.isAutomatic == true {
                    acknowledgeControl(token, result: "invalid_finish_activity")
                    return
                }
                lastControlToken = token
                lastControlResult = "accepted"
                finish(disposition, activity: overrideActivity)

            default:
                acknowledgeControl(token, result: "unsupported")
            }
            return
        }

        let command = rawCommand
        if command == "start" {
''',
    "watch deterministic controls",
)

watch = replace_once(
    watch,
    "            self.sessionID = sessionID\n",
    "            self.sessionID = sessionID\n"
    "            lastControlToken = nil\n"
    "            lastControlResult = nil\n",
    "watch reset control ack on start",
)

IPHONE.write_text(iphone, encoding="utf-8")
WATCH.write_text(watch, encoding="utf-8")
print("SESSION SYNC BUILD PATCH: OK")

# Production candidate chain. The workflow deliberately invokes only this
# orchestrator so the runtime-critical patches can never drift apart.
run_child_patch("APPLY_AUTO_PAUSE_SAFETY_PATCH.py")
run_child_patch("APPLY_TERMINAL_SYNC_RELIABILITY_PATCH.py")
run_child_patch("APPLY_HISTORICAL_CORRECTION_DISTANCE_PATCH.py")

# The historical patch inserts Swift through a Python raw string. Normalize only
# the two escape forms that must be single-backslash Swift syntax. This keeps the
# generated source deterministic and makes CI catch the active iPhone v4 path
# before Xcode's per-target pre-build script runs.
historical_core = ROOT / "iphone/Sources/HistoricalHealthKitRepairV4.swift"
historical_text = historical_core.read_text(encoding="utf-8")
historical_text = historical_text.replace(
    r"\\(error.localizedDescription)",
    r"\(error.localizedDescription)",
)
historical_text = historical_text.replace(
    r"map(\\.uuid)",
    r"map(\.uuid)",
)
historical_core.write_text(historical_text, encoding="utf-8")

# `replace_once` deliberately accepts an already generated tree. Re-read the
# two authoritative runtime files so an unrelated source drift still fails
# closed rather than being mistaken for a valid second invocation.
for path, tokens in {
    IPHONE: [
        "pendingControlToken",
        "makeControlCommand(",
        "parseControlAcknowledgement(",
        "ack.token == pendingControlToken",
    ],
    WATCH: [
        "lastControlToken",
        "parseControlCommand(",
        "message.revision == authorityRevision",
        'result: "stale_revision"',
        'result: "expired"',
    ],
}.items():
    content = path.read_text(encoding="utf-8")
    missing = [token for token in tokens if token not in content]
    if missing:
        raise SystemExit(f"session-sync generated source missing {path.name} tokens: {missing}")

print("TRACKER BUILD PATCH CHAIN: OK")
