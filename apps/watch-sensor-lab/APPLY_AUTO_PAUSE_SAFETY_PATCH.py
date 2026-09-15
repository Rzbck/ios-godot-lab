#!/usr/bin/env python3
"""Deterministic build-time safety patch for the 2026-09-13 auto-pause incident.

The patch is intentionally fail-closed and idempotent. It keeps auto-paused GPS
alive only as a read-only resume probe, prevents zero-speed startup auto-pause,
and records paused iPhone GPS samples for forensic recovery without changing
canonical route/distance while paused.

This helper is temporary integration debt: once hardware validation is green,
the exact generated Swift changes should be folded into the source files and
this helper removed.
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


def replace_block_or_present(
    text: str,
    start: str,
    end: str,
    replacement: str,
    marker: str,
    label: str,
) -> str:
    if marker in text:
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

# ---------------------------------------------------------------------------
# Watch: keep a read-only GPS probe alive during AUTO pause.
# ---------------------------------------------------------------------------
watch = replace_once_or_present(
    watch,
    "    private var autoResumeCandidateSince: Date?\n",
    "    private var autoResumeCandidateSince: Date?\n"
    "    private var autoPauseMovementObserved = false\n"
    "    private var autoPauseMotionObserved = false\n"
    "    private var autoResumeProbe = TrackerAutoResumeProbe()\n"
    "    private var autoResumeProbeLocation: CLLocation?\n",
    "private var autoPauseMotionObserved = false",
    "watch auto-resume probe state",
)

watch = replace_once_or_present(
    watch,
    '''        currentSpeedMps = 0
        locationManager.stopUpdatingLocation()
        stopPedometer()
        stopAltitude()
        workoutSession?.pause()
''',
    '''        currentSpeedMps = 0
        autoResumeProbe.reset()
        autoResumeProbeLocation = nil

        // Clear every pre-pause signal. A cadence or motion callback from the
        // active phase cannot be evidence for a later auto-resume.
        if reason == "auto" {
            cadenceSPM = 0
            lastCadenceEvidenceAt = .distantPast
            lastMotionWasStationary = false
            lastMotionCandidate = nil
            lastMotionEvidenceAt = .distantPast
        }

        if reason == "auto" {
            // Keep GPS alive strictly as resume evidence. `accept(location:)`
            // is never called while paused, so canonical route/distance and
            // HealthKit route data cannot be mutated by the probe.
            stopPedometer()
            stopAltitude()
        } else {
            locationManager.stopUpdatingLocation()
            stopPedometer()
            stopAltitude()
        }
        workoutSession?.pause()
''',
    "Clear every pre-pause signal.",
    "watch auto pause must retain GPS probe",
)

watch = replace_once_or_present(
    watch,
    '''        previousLocation = nil
        previousAltitudeLocation = nil
        phase = .active
''',
    '''        previousLocation = nil
        previousAltitudeLocation = nil
        autoResumeProbe.reset()
        autoResumeProbeLocation = nil
        phase = .active
''',
    "autoResumeProbeLocation = nil\n        phase = .active",
    "watch reset probe on resume",
)

watch = replace_once_or_present(
    watch,
    "        autoResumeCandidateSince = nil\n        lastMotionWasStationary = false\n",
    "        autoResumeCandidateSince = nil\n"
    "        autoPauseMovementObserved = false\n"
    "        autoPauseMotionObserved = false\n"
    "        autoResumeProbe.reset()\n"
    "        autoResumeProbeLocation = nil\n"
    "        lastMotionWasStationary = false\n",
    "autoPauseMovementObserved = false\n        autoPauseMotionObserved = false",
    "watch reset probe on new session",
)

watch = replace_once_or_present(
    watch,
    "    private func stageAutoPauseIfNeeded() {\n        guard autoPauseEnabled, phase == .active else { return }\n",
    '''    private func stageAutoPauseIfNeeded() {
        guard autoPauseEnabled, phase == .active else { return }
        guard TrackerAutoPolicy.canArmPause(
            activity: displayActivity,
            elapsedSeconds: elapsedSeconds,
            horizontalAccuracy: horizontalAccuracy,
            movementObserved: autoPauseMovementObserved,
            motionMovementObserved: autoPauseMotionObserved,
            stationaryEvidence: freshMotionWasStationary
        ) else {
            cancelPendingAutoPause()
            return
        }
''',
    "stationaryEvidence: freshMotionWasStationary",
    "watch auto pause arming guard",
)

watch = replace_block_or_present(
    watch,
    "    private func stageAutoResumeIfNeeded() {\n",
    "    private func cancelPendingAutoResume()",
    '''    private func stageAutoResumeIfNeeded() {
        guard autoPauseEnabled, phase == .paused, autoPaused else { return }

        let resumeSpeed = autoResumeProbe.confirmedRecentSpeedMps(
            now: Date().timeIntervalSince1970
        )

        guard WatchAutoPolicy.shouldStageResume(
            activity: displayActivity,
            stationary: freshMotionWasStationary,
            speedMps: resumeSpeed,
            cadenceSPM: freshCadenceSPM,
            motionCandidate: freshMotionCandidate,
            gpsEvidenceConfirmed: resumeSpeed > 0,
            motionEvidenceFresh: freshMotionCandidate != nil || freshMotionWasStationary,
            cadenceEvidenceFresh: freshCadenceSPM > 0
        ) else {
            cancelPendingAutoResume()
            return
        }

        guard autoResumeCandidateSince == nil else { return }
        autoResumeCandidateSince = Date()
        autoResumeToken = UUID()
        let token = autoResumeToken
        let delay = WatchAutoPolicy.resumeDwell(for: displayActivity)
        sendEvent("auto_resume_candidate", payload: [
            "activity": displayActivity.rawValue,
            "dwell_s": delay,
            "motion_candidate": freshMotionCandidate?.rawValue ?? "none",
            "probe_speed_mps": resumeSpeed,
        ])

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard
                let self,
                self.phase == .paused,
                self.autoPaused,
                self.autoPauseEnabled,
                self.autoResumeToken == token
            else { return }

            let confirmedSpeed = self.autoResumeProbe.confirmedRecentSpeedMps(
                now: Date().timeIntervalSince1970
            )

            guard WatchAutoPolicy.shouldStageResume(
                activity: self.displayActivity,
                stationary: self.freshMotionWasStationary,
                speedMps: confirmedSpeed,
                cadenceSPM: self.freshCadenceSPM,
                motionCandidate: self.freshMotionCandidate,
                gpsEvidenceConfirmed: confirmedSpeed > 0,
                motionEvidenceFresh: self.freshMotionCandidate != nil || self.freshMotionWasStationary,
                cadenceEvidenceFresh: self.freshCadenceSPM > 0
            ) else {
                self.cancelPendingAutoResume()
                return
            }

            self.autoResumeCandidateSince = nil
            self.authorityRevision += 1
            self.resumeCore(reason: "auto")
            self.autoPaused = false
            self.sendAuthority(force: true)
        }
    }

''',
    "gpsEvidenceConfirmed: resumeSpeed > 0",
    "watch auto resume uses GPS probe",
)

watch = replace_once_or_present(
    watch,
    "            self.lastMotionCandidate = rawMotionCandidate\n\n            if activity.stationary {\n",
    "            self.lastMotionCandidate = rawMotionCandidate\n"
    "            if rawMotionCandidate != nil { autoPauseMotionObserved = true }\n\n"
    "            if activity.stationary {\n",
    "if rawMotionCandidate != nil { autoPauseMotionObserved = true }",
    "watch arm auto pause after motion evidence",
)

watch = replace_once_or_present(
    watch,
    '''            if accuracyOK, plausible {
                acceptedForDistance = true
                distanceMeters += delta
''',
    '''            if accuracyOK, plausible {
                acceptedForDistance = true
                autoPauseMovementObserved = true
                distanceMeters += delta
''',
    "autoPauseMovementObserved = true",
    "watch arm auto pause after movement",
)

watch = replace_once_or_present(
    watch,
    "    private func sendMotionIfNeeded() {\n",
    '''    private func observeAutoResumeLocation(_ location: CLLocation) {
        guard phase == .paused, autoPaused else { return }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 35 else { return }
        guard abs(location.timestamp.timeIntervalSinceNow) < 10 else { return }

        var derivedSpeed = 0.0
        if let previous = autoResumeProbeLocation {
            let dt = location.timestamp.timeIntervalSince(previous.timestamp)
            if dt > 0.15, dt < 12 {
                derivedSpeed = location.distance(from: previous) / dt
            }
        }
        autoResumeProbeLocation = location

        guard let probeSpeed = autoResumeProbe.observe(
            sampleTimestamp: location.timestamp.timeIntervalSince1970,
            now: Date().timeIntervalSince1970,
            horizontalAccuracy: location.horizontalAccuracy,
            nativeSpeedMps: location.speed,
            derivedSpeedMps: derivedSpeed,
            plausibleMaxSpeedMps: displayActivity.plausibleMaxSpeedMps,
            speedAccuracyMps: location.speedAccuracy
        ) else { return }

        // Presentation may show current position/accuracy, but the paused probe
        // never appends to route, healthRouteLocations, or distanceMeters.
        horizontalAccuracy = location.horizontalAccuracy
        currentCoordinate = location.coordinate

        sendSensorSample(kind: "auto_resume_probe_location", payload: [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "altitude_m": location.altitude,
            "native_speed_mps": location.speed,
            "derived_speed_mps": derivedSpeed,
            "probe_speed_mps": probeSpeed,
            "horizontal_accuracy_m": location.horizontalAccuracy,
            "selected_activity": selectedActivity.rawValue,
            "effective_activity": effectiveActivity.rawValue,
            "canonical_distance_unchanged": true,
        ], reliable: false)

        stageAutoResumeIfNeeded()
    }

    private func sendMotionIfNeeded() {
''',
    "private func observeAutoResumeLocation(_ location: CLLocation)",
    "watch paused GPS observer",
)

watch = replace_once_or_present(
    watch,
    '''        currentSpeedMps = 0
        lastEndedSessionID = sessionID
''',
    '''        currentSpeedMps = 0
        autoResumeProbe.reset()
        autoResumeProbeLocation = nil
        lastEndedSessionID = sessionID
''',
    "autoResumeProbe.reset()\n        autoResumeProbeLocation = nil\n        lastEndedSessionID",
    "watch reset probe on stop",
)

watch = replace_once_or_present(
    watch,
    '''        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            if phase == .active { manager.startUpdatingLocation() }
        }
''',
    '''        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            if phase == .active || (phase == .paused && autoPaused) {
                manager.startUpdatingLocation()
            }
        }
''',
    "phase == .paused && autoPaused",
    "watch authorization keeps auto-resume GPS alive",
)

watch = replace_once_or_present(
    watch,
    '''    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async { [weak self] in self?.accept(location: location) }
    }
''',
    '''    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.phase == .active {
                self.accept(location: location)
            } else if self.phase == .paused, self.autoPaused {
                self.observeAutoResumeLocation(location)
            }
        }
    }
''',
    "self.observeAutoResumeLocation(location)",
    "watch route paused GPS to resume probe",
)

# ---------------------------------------------------------------------------
# iPhone: retain raw paused GPS as a forensic safety net without mutating live
# route/distance. This means a future Watch auto-pause fault does not erase the
# only phone-side track evidence.
# ---------------------------------------------------------------------------
iphone = replace_once_or_present(
    iphone,
    "    private var lastGPSRejectionLog = Date.distantPast\n",
    "    private var lastGPSRejectionLog = Date.distantPast\n"
    "    private var lastPausedLocationProbeSend = Date.distantPast\n",
    "private var lastPausedLocationProbeSend = Date.distantPast",
    "iphone paused GPS probe state",
)

iphone = replace_once_or_present(
    iphone,
    "        lastGPSRejectionLog = .distantPast\n        cadenceAccumulator = 0\n",
    "        lastGPSRejectionLog = .distantPast\n"
    "        lastPausedLocationProbeSend = .distantPast\n"
    "        cadenceAccumulator = 0\n",
    "lastPausedLocationProbeSend = .distantPast",
    "iphone reset paused GPS probe",
)

iphone = replace_once_or_present(
    iphone,
    "    private func captureWeather(at location: CLLocation, force: Bool = false) {\n",
    '''    private func recordPausedLocationProbe(_ location: CLLocation) {
        guard phase == .paused else { return }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 35 else { return }
        guard abs(location.timestamp.timeIntervalSinceNow) < 10 else { return }

        let now = Date()
        guard now.timeIntervalSince(lastPausedLocationProbeSend) >= 1 else { return }
        lastPausedLocationProbeSend = now

        store.appendSample(
            source: "iphone",
            kind: "paused_location_probe",
            payload: [
                "latitude": location.coordinate.latitude,
                "longitude": location.coordinate.longitude,
                "altitude_m": location.altitude,
                "native_speed_mps": location.speed,
                "canonical_distance_unchanged": true,
            ],
            quality: [
                "horizontal_accuracy_m": location.horizontalAccuracy,
                "vertical_accuracy_m": location.verticalAccuracy,
                "native_speed_accuracy_mps": location.speedAccuracy,
            ]
        )
    }

    private func captureWeather(at location: CLLocation, force: Bool = false) {
''',
    "private func recordPausedLocationProbe(_ location: CLLocation)",
    "iphone paused GPS recorder",
)

iphone = replace_once_or_present(
    iphone,
    '''    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async { [weak self] in self?.accept(location: location) }
    }
''',
    '''    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.phase == .active {
                self.accept(location: location)
            } else if self.phase == .paused {
                self.recordPausedLocationProbe(location)
            }
        }
    }
''',
    "self.recordPausedLocationProbe(location)",
    "iphone route paused GPS to forensic probe",
)

IPHONE.write_text(iphone, encoding="utf-8")
WATCH.write_text(watch, encoding="utf-8")

# Fail closed: the build must contain every safety primitive, otherwise the
# candidate is rejected before Swift compilation.
watch_after = WATCH.read_text(encoding="utf-8")
iphone_after = IPHONE.read_text(encoding="utf-8")
for token in [
    "autoPauseMovementObserved",
    "autoPauseMotionObserved",
    "TrackerAutoPolicy.canArmPause(",
    "autoResumeProbe.confirmedRecentSpeedMps(",
    "cadenceSPM: freshCadenceSPM",
    "motionCandidate: freshMotionCandidate",
    "observeAutoResumeLocation(_ location: CLLocation)",
    "canonical_distance_unchanged",
]:
    if token not in watch_after:
        raise SystemExit(f"watch safety token missing after patch: {token}")

for token in [
    "recordPausedLocationProbe(_ location: CLLocation)",
    'kind: "paused_location_probe"',
    "self.recordPausedLocationProbe(location)",
]:
    if token not in iphone_after:
        raise SystemExit(f"iphone safety token missing after patch: {token}")

print("AUTO PAUSE SAFETY BUILD PATCH: OK")
