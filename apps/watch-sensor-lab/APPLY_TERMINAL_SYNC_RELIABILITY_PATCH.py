#!/usr/bin/env python3
"""Build-time reliability patch for Watch -> iPhone terminal workout state.

The Watch is the session authority. A terminal `ended` state is therefore not a
best-effort UI update: it must survive temporary WatchConnectivity loss. The
patch keeps the existing immediate/application-context transports and adds a
queued `transferUserInfo` delivery specifically for terminal authority. The
phone consumes that durable delivery through the same idempotent wire decoder.

This is temporary integration debt while the session-sync candidate is under
hardware validation. Fold the generated Swift into source and remove this
helper once the candidate is accepted.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
IPHONE = ROOT / "iphone/Sources/TrackerModel.swift"
WATCH = ROOT / "watch/Sources/SensorModel.swift"


def replace_once_or_present(text: str, old: str, new: str, marker: str, label: str) -> str:
    if marker in text:
        return text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, got {count}")
    return text.replace(old, new, 1)


iphone = IPHONE.read_text(encoding="utf-8")
watch = WATCH.read_text(encoding="utf-8")

# Watch: terminal authority is sent by all three appropriate transports:
# - mirrored workout session (while it still exists),
# - application context (latest-state convergence),
# - transferUserInfo (durable queued terminal event).
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

        // Latest-state convergence if either app was temporarily unavailable.
        try? session.updateApplicationContext(payload)

        // Terminal state is an event as well as state. Queue it durably even if
        // the counterpart is reachable right now; duplicate delivery is safe
        // because the iPhone finalizer is session-idempotent.
        if reliable, session.activationState == .activated {
            session.transferUserInfo(payload)
        }

        if session.activationState == .activated, session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }
''',
    "sendWC(message, reliable: phaseOverride == \"ended\")",
    "watch durable terminal authority",
)

# iPhone: receive queued WatchConnectivity user-info payloads through exactly
# the same decoder as immediate messages/application context.
iphone = replace_once_or_present(
    iphone,
    '''    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { receiveWC(message) }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { receiveWC(applicationContext) }
''',
    '''    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { receiveWC(message) }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { receiveWC(applicationContext) }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { receiveWC(userInfo) }
''',
    "didReceiveUserInfo userInfo",
    "iphone durable user-info receiver",
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
            // Duplicate durable delivery after an already-finalized session.
            if message.sessionID == lastEndedSessionID { return }

            // transferUserInfo may legitimately arrive late. It is forbidden
            // to let an old terminal packet stop a newer active session.
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
for token in [
    'sendWC(message, reliable: phaseOverride == "ended")',
    "session.transferUserInfo(payload)",
]:
    if token not in watch_after:
        raise SystemExit(f"watch terminal reliability token missing: {token}")
for token in [
    "didReceiveUserInfo userInfo",
    "foreign_terminal_authority_ignored",
]:
    if token not in iphone_after:
        raise SystemExit(f"iphone terminal reliability token missing: {token}")

print("TERMINAL SYNC RELIABILITY BUILD PATCH: OK")
