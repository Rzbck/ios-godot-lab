#!/usr/bin/env python3
"""Build-time reliability patch for Watch -> iPhone terminal workout state.

The Watch is the session authority. A terminal `ended` state must survive
transient WatchConnectivity loss. The Watch therefore queues terminal
authority through transferUserInfo in addition to the existing mirrored-session
and application-context transports.

The iPhone already owns a single WCSession didReceiveUserInfo callback in
WatchReliableRecovery.swift. Reuse that callback instead of declaring another
one in TrackerModel.swift; it persists sensor recovery packets and forwards all
payloads to the product wire decoder.

Temporary integration debt: after hardware validation, fold these changes into
Swift source and remove this helper.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
IPHONE = ROOT / "iphone/Sources/TrackerModel.swift"
WATCH = ROOT / "watch/Sources/SensorModel.swift"
RELIABLE_RECOVERY = ROOT / "iphone/Sources/WatchReliableRecovery.swift"


def replace_once_or_present(text: str, old: str, new: str, marker: str, label: str) -> str:
    if marker in text:
        return text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, got {count}")
    return text.replace(old, new, 1)


iphone = IPHONE.read_text(encoding="utf-8")
watch = WATCH.read_text(encoding="utf-8")
reliable_recovery = RELIABLE_RECOVERY.read_text(encoding="utf-8")

# Fail closed: there must be one existing durable receiver, and it must forward
# the queued payload into the same product decoder used by immediate messages.
if "func session(_ session: WCSession, didReceiveUserInfo userInfo:" not in reliable_recovery:
    raise SystemExit(
        "iphone durable user-info receiver missing from WatchReliableRecovery.swift"
    )
if "receiveWC(userInfo)" not in reliable_recovery:
    raise SystemExit(
        "durable user-info receiver does not forward to product decoder"
    )

# Watch: terminal authority is delivered through:
# - mirrored workout session while it still exists,
# - application context for latest-state convergence,
# - transferUserInfo as a durable queued terminal event.
watch = replace_once_or_present(
    watch,
    '''        if let phaseOverride { message.phase = phaseOverride }
        if let data = TrackerWireCodec.encode(message), let workoutSession {
            workoutSession.sendToRemoteWorkoutSession(data: data) { _, _ in }
        }
        sendWC(message)
    }

    private func sendWC(_ message: TrackerWireMessage) {
        guard WCSession.isSupported(), let data = TrackerWireCodec.encode(message) else { return }
        let payload: [String: Any] = ["type": "tracker_wire_v3", "data": data]
        let session = WCSession.default
        try? session.updateApplicationContext(payload)
        if session.activationState == .activated, session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }
''',
    '''        if let phaseOverride { message.phase = phaseOverride }
        if let data = TrackerWireCodec.encode(message), let workoutSession {
            workoutSession.sendToRemoteWorkoutSession(data: data) { _, _ in }
        }
        sendWC(message, reliable: phaseOverride == "ended")
    }

    private func sendWC(_ message: TrackerWireMessage, reliable: Bool = false) {
        guard WCSession.isSupported(), let data = TrackerWireCodec.encode(message) else { return }
        let payload: [String: Any] = ["type": "tracker_wire_v3", "data": data]
        let session = WCSession.default

        try? session.updateApplicationContext(payload)

        if reliable, session.activationState == .activated {
            session.transferUserInfo(payload)
        }

        if session.activationState == .activated, session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }
''',
    'sendWC(message, reliable: phaseOverride == "ended")',
    "watch durable terminal authority",
)

# A delayed durable terminal event from an older workout must never terminate a
# newer active workout. Exact same-session terminal authority remains accepted.
iphone = replace_once_or_present(
    iphone,
    '''    private func applyAuthority(_ message: TrackerWireMessage) {
        guard message.kind == .authority else { return }
        guard !message.sessionID.isEmpty else { return }
        guard message.sessionID != lastEndedSessionID else { return }
        guard message.revision >= lastAuthorityRevision else {
''',
    '''    private func applyAuthority(_ message: TrackerWireMessage) {
        guard message.kind == .authority else { return }
        guard !message.sessionID.isEmpty else { return }

        if message.phase == "ended" {
            if message.sessionID == lastEndedSessionID { return }

            if isActive, !sessionID.isEmpty, message.sessionID != sessionID {
                store.appendEvent("foreign_terminal_authority_ignored", source: "watch", payload: [
                    "terminal_session_id": message.sessionID,
                    "active_session_id": sessionID,
                    "terminal_revision": message.revision,
                ])
                return
            }
        }

        guard message.sessionID != lastEndedSessionID else { return }
        guard message.revision >= lastAuthorityRevision else {
''',
    "foreign_terminal_authority_ignored",
    "iphone protect newer session from delayed terminal",
)

IPHONE.write_text(iphone, encoding="utf-8")
WATCH.write_text(watch, encoding="utf-8")

iphone_after = IPHONE.read_text(encoding="utf-8")
watch_after = WATCH.read_text(encoding="utf-8")
reliable_after = RELIABLE_RECOVERY.read_text(encoding="utf-8")

for token in [
    'sendWC(message, reliable: phaseOverride == "ended")',
    "session.transferUserInfo(payload)",
]:
    if token not in watch_after:
        raise SystemExit(f"watch terminal reliability token missing: {token}")

if "foreign_terminal_authority_ignored" not in iphone_after:
    raise SystemExit("iphone delayed-terminal protection missing")

for token in [
    "didReceiveUserInfo userInfo",
    "receiveWC(userInfo)",
]:
    if token not in reliable_after:
        raise SystemExit(f"existing durable receiver token missing: {token}")

print("TERMINAL SYNC RELIABILITY BUILD PATCH: OK")
