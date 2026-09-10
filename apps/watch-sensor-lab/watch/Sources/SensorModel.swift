import Combine
import CoreLocation
import CoreMotion
import Foundation
import HealthKit
import WatchConnectivity

final class SensorModel: NSObject, ObservableObject {
    static let shared = SensorModel()

    enum Phase: String { case ready, active, paused }

    @Published private(set) var phase: Phase = .ready
    @Published private(set) var selectedActivity: ActivityKind = .automatic
    @Published private(set) var effectiveActivity: ActivityKind = .walking
    @Published private(set) var sessionID = ""
    @Published private(set) var elapsedSeconds: TimeInterval = 0
    @Published private(set) var distanceMeters = 0.0
    @Published private(set) var currentSpeedMps = 0.0
    @Published private(set) var altitudeMeters = 0.0
    @Published private(set) var elevationGainMeters = 0.0
    @Published private(set) var elevationLossMeters = 0.0
    @Published private(set) var heartRate = 0.0
    @Published private(set) var averageHeartRate = 0.0
    @Published private(set) var activeEnergyKcal = 0.0
    @Published private(set) var cadenceSPM = 0.0
    @Published private(set) var steps = 0
    @Published private(set) var route: [CLLocationCoordinate2D] = []
    @Published private(set) var currentCoordinate: CLLocationCoordinate2D?
    @Published private(set) var horizontalAccuracy = -1.0
    @Published private(set) var phoneReachable = false
    @Published private(set) var healthAuthorized = false
    @Published private(set) var sessionStatus = "Prêt"
    @Published private(set) var autoPauseEnabled = false
    @Published private(set) var autoPaused = false
    @Published private(set) var multisportTransition = false
    @Published private(set) var autoConfidence = "—"
    @Published private(set) var autoProvenance = "En attente"

    @Published private(set) var accelX = 0.0
    @Published private(set) var accelY = 0.0
    @Published private(set) var accelZ = 0.0
    @Published private(set) var gyroX = 0.0
    @Published private(set) var gyroY = 0.0
    @Published private(set) var gyroZ = 0.0
    @Published private(set) var gyroSource = "unavailable"

    var running: Bool { phase == .active || phase == .paused }
    var isPaused: Bool { phase == .paused }
    var displayActivity: ActivityKind { selectedActivity.isAutomatic ? effectiveActivity : selectedActivity }
    var canAdvanceTriathlon: Bool { (selectedActivity == .swimBikeRun && effectiveActivity != .running) || multisportTransition }

    private let healthStore = HKHealthStore()
    private let locationManager = CLLocationManager()
    private let activityManager = CMMotionActivityManager()
    private let pedometer = CMPedometer()
    private let motionSampler = WatchMotionSampler()
    private let altitudeSampler = WatchAltitudeSampler()
    private let defaults = UserDefaults.standard

    private let saveWorkoutToHealth = true
    private static let managedWorkoutMetadataKey = "com.rzbck.watchsensorlab.managed"
    private static let sessionMetadataKey = "com.rzbck.watchsensorlab.session_id"

    private var workoutSession: HKWorkoutSession?
    private var workoutBuilder: HKLiveWorkoutBuilder?
    private var workoutRouteBuilder: HKWorkoutRouteBuilder?
    private var healthRouteLocations: [CLLocation] = []
    private var startedAt: Date?
    private var pausedAt: Date?
    private var pausedDuration: TimeInterval = 0
    private var timer: Timer?
    private var previousLocation: CLLocation?
    private var previousAltitudeLocation: CLLocation?
    private var lastStateSend = Date.distantPast
    private var lastMotionSend = Date.distantPast
    private var lastWatchLocationSend = Date.distantPast
    private var lastGPSRejectionEvent = Date.distantPast
    private var lastMetricSnapshotSend = Date.distantPast
    private var lastReliableMetricSnapshotSend = Date.distantPast
    private var lastAutoEvidenceSend = Date.distantPast
    private var pendingRemoteSessionID: String?
    private var pendingPhoneConfiguration: HKWorkoutConfiguration?
    private var authorityRevision: Int64 = 0
    private var selectionRevision: Int64 = 0
    private var lastEndedSessionID = ""
    private var lastPurgeID = ""
    private var autoCandidate: ActivityKind?
    private var autoCandidateDecision: WatchAutoDecision?
    private var autoCandidateToken = UUID()
    private var autoPauseToken = UUID()
    private var autoResumeToken = UUID()
    private var autoPauseCandidateSince: Date?
    private var autoResumeCandidateSince: Date?
    private var lastMotionWasStationary = false
    private var lastMotionCandidate: ActivityKind?
    private var usingBarometricElevation = false
    private var hasAbsoluteBarometricAltitude = false
    private var pedometerBaseSteps = 0
    private var nextTriathlonActivity: ActivityKind?
    private var triathlonMotionCandidate: ActivityKind?
    private var triathlonMotionToken = UUID()
    private var automaticActivityTransitions = 0

    private override init() {
        super.init()
        lastPurgeID = defaults.string(forKey: "tracker.lastPurgeID") ?? ""
        autoPauseEnabled = defaults.bool(forKey: "tracker.autoPauseEnabled")
        configureLocation()
        configureAltitudeSampler()
        activateSession()
        requestHealthAuthorization()
    }

    func activateSession() {
        guard WCSession.isSupported() else {
            sessionStatus = "iPhone non disponible"
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        phoneReachable = session.isReachable
    }

    func selectActivity(_ activity: ActivityKind) {
        guard !running else { return }
        selectedActivity = activity
        effectiveActivity = initialEffectiveActivity(for: activity)
        selectionRevision = Self.revisionNow()
        autoConfidence = activity.isAutomatic ? "—" : "manuel"
        autoProvenance = activity.isAutomatic ? "En attente" : "Choix utilisateur"
        sessionStatus = activity.isAutomatic ? "Auto · marche/course/vélo/randonnée" : activity.label
        sendWC(makeMessage(kind: .selection))
    }

    func setAutoPauseEnabled(_ enabled: Bool) {
        guard !running else { return }
        autoPauseEnabled = enabled
        defaults.set(enabled, forKey: "tracker.autoPauseEnabled")
        sendEvent("auto_pause_preference", payload: ["enabled": enabled])
    }

    func requestHealthAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        var readTypes = Set<HKObjectType>()
        for identifier in [
            HKQuantityTypeIdentifier.heartRate,
            .activeEnergyBurned,
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
        ] {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) { readTypes.insert(type) }
        }
        let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]

        healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { [weak self] success, error in
            DispatchQueue.main.async {
                self?.healthAuthorized = success
                if let error { self?.sessionStatus = "Santé: \(error.localizedDescription)" }
            }
        }
    }

    func start() {
        guard !running else { return }
        authorityRevision = max(1, authorityRevision + 1)
        lastEndedSessionID = ""
        start(configuration: nil, origin: "watch", sessionID: nil)
    }

    func startFromPhoneConfiguration(_ configuration: HKWorkoutConfiguration) {
        guard !running else { return }
        pendingPhoneConfiguration = configuration
        if selectedActivity != .automatic, let activity = ActivityKind(healthKitType: configuration.activityType) {
            selectedActivity = activity
            effectiveActivity = initialEffectiveActivity(for: activity)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, !self.running, let config = self.pendingPhoneConfiguration else { return }
            self.pendingPhoneConfiguration = nil
            self.authorityRevision = max(1, self.authorityRevision + 1)
            self.start(configuration: config, origin: "iphone", sessionID: self.pendingRemoteSessionID)
        }
    }

    private func start(configuration: HKWorkoutConfiguration?, origin: String, sessionID: String?) {
        guard !running else { return }
        let identifier = sessionID ?? pendingRemoteSessionID ?? Self.makeSessionID()
        pendingRemoteSessionID = nil
        pendingPhoneConfiguration = nil

        let config = configuration ?? {
            let value = HKWorkoutConfiguration()
            if selectedActivity.isAutomatic {
                value.activityType = effectiveActivity.healthKitType
            } else {
                value.activityType = selectedActivity.healthKitType
            }
            value.locationType = .outdoor
            return value
        }()

        if selectedActivity != .automatic, let activity = ActivityKind(healthKitType: config.activityType) {
            selectedActivity = activity
            effectiveActivity = initialEffectiveActivity(for: activity)
        }

        guard healthAuthorized else {
            requestHealthAuthorizationAndStart(config, origin: origin, sessionID: identifier)
            return
        }
        startAuthorized(config, origin: origin, sessionID: identifier)
    }

    private func requestHealthAuthorizationAndStart(_ configuration: HKWorkoutConfiguration, origin: String, sessionID: String) {
        var readTypes = Set<HKObjectType>()
        for identifier in [
            HKQuantityTypeIdentifier.heartRate,
            .activeEnergyBurned,
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
        ] {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) { readTypes.insert(type) }
        }
        let shareTypes: Set<HKSampleType> = [HKObjectType.workoutType(), HKSeriesType.workoutRoute()]

        healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.healthAuthorized = success
                guard success else {
                    self.sessionStatus = error?.localizedDescription ?? "Autorisation Santé requise"
                    return
                }
                self.startAuthorized(configuration, origin: origin, sessionID: sessionID)
            }
        }
    }

    private func startAuthorized(_ configuration: HKWorkoutConfiguration, origin: String, sessionID: String) {
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            let routeBuilder = builder.seriesBuilder(for: HKSeriesType.workoutRoute()) as? HKWorkoutRouteBuilder
            session.delegate = self
            builder.delegate = self
            workoutSession = session
            workoutBuilder = builder
            workoutRouteBuilder = routeBuilder

            self.sessionID = sessionID
            builder.addMetadata([
                Self.managedWorkoutMetadataKey: true,
                Self.sessionMetadataKey: sessionID,
                "com.rzbck.watchsensorlab.selected_activity": selectedActivity.rawValue,
                "com.rzbck.watchsensorlab.algorithm_version": "tracker-v4-20260910",
                "com.rzbck.watchsensorlab.healthkit_initial_activity": ActivityKind(healthKitType: configuration.activityType)?.rawValue ?? String(configuration.activityType.rawValue),
            ]) { [weak self] success, error in
                guard !success, let error else { return }
                DispatchQueue.main.async {
                    self?.sessionStatus = "Métadonnées Santé: \(error.localizedDescription)"
                }
            }

            startedAt = Date()
            pausedAt = nil
            pausedDuration = 0
            resetPresentationData(keepActivity: true)
            phase = .active
            effectiveActivity = initialEffectiveActivity(for: selectedActivity)
            authorityRevision = max(authorityRevision, 1)
            sessionStatus = selectedActivity.isAutomatic ? "Auto · analyse en cours" : "\(selectedActivity.label) en cours"

            requestLocationPermission()
            locationManager.startUpdatingLocation()
            startMotion()
            startPedometer()
            startAltitude()
            startMotionClassifierIfNeeded()
            startClock()

            let date = startedAt ?? Date()
            session.startActivity(with: date)
            builder.beginCollection(withStart: date) { [weak self] success, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if !success, let error {
                        self.sessionStatus = "Entraînement: \(error.localizedDescription)"
                        self.sendEvent("health_collection_error", payload: ["message": error.localizedDescription])
                    } else if self.selectedActivity == .swimBikeRun {
                        self.beginTriathlonActivity(.swimming, at: date)
                    }
                }
            }

            session.startMirroringToCompanionDevice { [weak self] success, error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.sessionStatus = success ? "iPhone + Watch synchronisés" : "Miroir iPhone: \(error?.localizedDescription ?? "indisponible")"
                    self.sendEvent(success ? "health_mirror_started" : "health_mirror_failed", payload: [
                        "message": error?.localizedDescription ?? "",
                    ])
                    self.sendAuthority(force: true)
                }
            }
            sendEvent("session_started", payload: [
                "origin": origin,
                "selected_activity": selectedActivity.rawValue,
                "healthkit_activity_type": configuration.activityType.rawValue,
                "healthkit_activity": ActivityKind(healthKitType: configuration.activityType)?.rawValue ?? "unknown",
                "authority_revision": authorityRevision,
            ])
            sendAuthority(force: true)
        } catch {
            sessionStatus = "Impossible de démarrer: \(error.localizedDescription)"
            sendEvent("session_start_error", payload: ["message": error.localizedDescription])
            phase = .ready
        }
    }

    func pause() {
        guard phase == .active else { return }
        authorityRevision += 1
        autoPaused = false
        pauseCore(reason: "manual")
        sendAuthority(force: true)
    }

    func resume() {
        guard phase == .paused else { return }
        authorityRevision += 1
        autoPaused = false
        resumeCore(reason: "manual")
        sendAuthority(force: true)
    }

    func stop() {
        guard running else { return }
        authorityRevision += 1
        stopCore(status: "Session terminée")
    }

    func advanceTriathlon() {
        guard selectedActivity == .swimBikeRun, phase == .active, let session = workoutSession else { return }
        let now = Date()

        if multisportTransition, let next = nextTriathlonActivity {
            session.endCurrentActivity(on: now)
            beginTriathlonActivity(next, at: now)
            effectiveActivity = next
            multisportTransition = false
            nextTriathlonActivity = nil
            triathlonMotionCandidate = nil
            triathlonMotionToken = UUID()
            authorityRevision += 1
            sessionStatus = "Triathlon · \(next.label)"
            sendEvent("multisport_segment_started", payload: ["activity": next.rawValue, "trigger": "manual_or_auto"])
            sendAuthority(force: true)
            return
        }

        let next: ActivityKind?
        switch effectiveActivity {
        case .swimming: next = .cycling
        case .cycling: next = .running
        default: next = nil
        }
        guard let next else { return }

        session.endCurrentActivity(on: now)
        let transition = HKWorkoutConfiguration()
        transition.activityType = .transition
        transition.locationType = .outdoor
        session.beginNewActivity(configuration: transition, date: now, metadata: nil)
        multisportTransition = true
        nextTriathlonActivity = next
        triathlonMotionCandidate = nil
        triathlonMotionToken = UUID()
        authorityRevision += 1
        sessionStatus = "Transition → \(next.label)"
        sendEvent("multisport_transition_started", payload: ["next_activity": next.rawValue, "trigger": "manual_or_auto"])
        sendAuthority(force: true)
    }

    func deleteAllTestData() {
        guard !running else {
            sessionStatus = "Termine la session avant d’effacer"
            return
        }
        let purgeID = UUID().uuidString
        applyPurge(purgeID)
        var message = makeMessage(kind: .purge)
        message.purgeID = purgeID
        sendWC(message)
    }

    private func initialEffectiveActivity(for activity: ActivityKind) -> ActivityKind {
        if activity == .swimBikeRun { return .swimming }
        return activity.isAutomatic ? .walking : activity
    }

    private func beginTriathlonActivity(_ activity: ActivityKind, at date: Date) {
        guard let session = workoutSession else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activity.healthKitType
        configuration.locationType = .outdoor
        session.beginNewActivity(configuration: configuration, date: date, metadata: [
            "com.rzbck.watchsensorlab.segment_activity": activity.rawValue,
        ])
        effectiveActivity = activity
    }

    private func pauseCore(reason: String) {
        guard phase == .active else { return }
        phase = .paused
        pausedAt = Date()
        currentSpeedMps = 0
        locationManager.stopUpdatingLocation()
        stopPedometer()
        stopAltitude()
        workoutSession?.pause()
        cancelPendingAutoPause()
        sessionStatus = reason == "auto" ? "Pause auto" : "En pause · Watch autoritaire"
        sendEvent(reason == "auto" ? "auto_pause" : "manual_pause", payload: [
            "authority_revision": authorityRevision,
            "activity": displayActivity.rawValue,
            "speed_mps": currentSpeedMps,
            "cadence_spm": cadenceSPM,
        ])
    }

    private func resumeCore(reason: String) {
        guard phase == .paused else { return }
        if let pausedAt { pausedDuration += Date().timeIntervalSince(pausedAt) }
        self.pausedAt = nil
        previousLocation = nil
        previousAltitudeLocation = nil
        phase = .active
        workoutSession?.resume()
        locationManager.startUpdatingLocation()
        startPedometer()
        startAltitude()
        cancelPendingAutoResume()
        sessionStatus = selectedActivity.isAutomatic ? "Auto · \(effectiveActivity.label)" : "\(selectedActivity.label) en cours"
        sendEvent(reason == "auto" ? "auto_resume" : "manual_resume", payload: [
            "authority_revision": authorityRevision,
            "activity": displayActivity.rawValue,
        ])
    }

    private func stopCore(status: String) {
        guard running else { return }
        let end = Date()
        if phase == .paused, let pausedAt { pausedDuration += end.timeIntervalSince(pausedAt) }
        refreshElapsed()
        locationManager.stopUpdatingLocation()
        stopMotion()
        stopPedometer()
        stopAltitude()
        stopMotionClassifier()
        timer?.invalidate()
        timer = nil
        currentSpeedMps = 0
        lastEndedSessionID = sessionID

        if selectedActivity.isAutomatic {
            workoutBuilder?.addMetadata([
                "com.rzbck.watchsensorlab.auto_final_activity": effectiveActivity.rawValue,
                "com.rzbck.watchsensorlab.auto_transition_count": automaticActivityTransitions,
                "com.rzbck.watchsensorlab.auto_healthkit_semantics_match": workoutSession?.workoutConfiguration.activityType == effectiveActivity.healthKitType && automaticActivityTransitions == 0,
            ]) { _, _ in }
        }

        sendEvent("session_stopping", payload: [
            "authority_revision": authorityRevision,
            "effective_activity": effectiveActivity.rawValue,
            "distance_m": distanceMeters,
            "active_energy_kcal": activeEnergyKcal,
            "auto_transition_count": automaticActivityTransitions,
            "healthkit_activity": ActivityKind(healthKitType: workoutSession?.workoutConfiguration.activityType ?? .other)?.rawValue ?? "unknown",
        ])
        sendMetricSnapshotIfNeeded(force: true)
        sendAuthority(force: true, phaseOverride: "ended")

        let builder = workoutBuilder
        let routeBuilder = workoutRouteBuilder
        let routeLocations = healthRouteLocations
        let completedSessionID = sessionID
        workoutSession?.end()

        if saveWorkoutToHealth, let builder {
            sessionStatus = "\(status) · sauvegarde Santé…"
            finishAndSaveWorkout(
                builder: builder,
                routeBuilder: routeBuilder,
                locations: routeLocations,
                end: end,
                sessionID: completedSessionID,
                status: status
            )
        } else {
            builder?.discardWorkout()
            sessionStatus = "\(status) · Santé non modifiée"
        }

        workoutSession = nil
        workoutBuilder = nil
        workoutRouteBuilder = nil
        healthRouteLocations = []
        startedAt = nil
        pausedAt = nil
        phase = .ready
        autoPaused = false
        multisportTransition = false
        nextTriathlonActivity = nil
    }

    private func finishAndSaveWorkout(
        builder: HKLiveWorkoutBuilder,
        routeBuilder: HKWorkoutRouteBuilder?,
        locations: [CLLocation],
        end: Date,
        sessionID: String,
        status: String
    ) {
        let finishCollection: (Bool, Error?) -> Void = { [weak self] routeReady, routeError in
            builder.endCollection(withEnd: end) { [weak self] success, error in
                guard let self else { return }
                guard success else {
                    DispatchQueue.main.async {
                        self.sessionStatus = "Santé: \(error?.localizedDescription ?? "fin de collecte impossible")"
                    }
                    return
                }

                builder.finishWorkout { [weak self] workout, error in
                    guard let self else { return }
                    guard let workout else {
                        DispatchQueue.main.async {
                            self.sessionStatus = "Santé: \(error?.localizedDescription ?? "sauvegarde impossible")"
                        }
                        return
                    }

                    self.sendHealthSaveResult(workout: workout, sessionID: sessionID)

                    guard routeReady, let routeBuilder, !locations.isEmpty else {
                        DispatchQueue.main.async {
                            if let routeError {
                                self.sessionStatus = "\(status) · Santé sauvegardée · parcours: \(routeError.localizedDescription)"
                            } else {
                                self.sessionStatus = "\(status) · Santé sauvegardée (sans parcours)"
                            }
                        }
                        return
                    }

                    routeBuilder.finishRoute(
                        with: workout,
                        metadata: [
                            Self.managedWorkoutMetadataKey: true,
                            Self.sessionMetadataKey: sessionID,
                        ]
                    ) { [weak self] _, routeError in
                        DispatchQueue.main.async {
                            guard let self else { return }
                            if let routeError {
                                self.sessionStatus = "\(status) · Santé sauvegardée · parcours: \(routeError.localizedDescription)"
                            } else {
                                self.sessionStatus = "\(status) · Santé + parcours sauvegardés"
                            }
                        }
                    }
                }
            }
        }

        guard let routeBuilder, !locations.isEmpty else {
            finishCollection(false, nil)
            return
        }

        routeBuilder.insertRouteData(locations) { success, error in
            finishCollection(success, error)
        }
    }

    private func sendHealthSaveResult(workout: HKWorkout, sessionID: String) {
        sendEvent("health_workout_saved", payload: [
            "session_id": sessionID,
            "workout_uuid": workout.uuid.uuidString,
            "activity": ActivityKind(healthKitType: workout.workoutActivityType)?.rawValue ?? "unknown",
            "auto_transition_count": automaticActivityTransitions,
        ])
    }

    private func resetPresentationData(keepActivity: Bool) {
        elapsedSeconds = 0
        distanceMeters = 0
        currentSpeedMps = 0
        altitudeMeters = 0
        elevationGainMeters = 0
        elevationLossMeters = 0
        heartRate = 0
        averageHeartRate = 0
        activeEnergyKcal = 0
        cadenceSPM = 0
        steps = 0
        route = []
        healthRouteLocations = []
        currentCoordinate = nil
        horizontalAccuracy = -1
        previousLocation = nil
        previousAltitudeLocation = nil
        accelX = 0
        accelY = 0
        accelZ = 0
        gyroX = 0
        gyroY = 0
        gyroZ = 0
        gyroSource = "unavailable"
        autoCandidate = nil
        autoCandidateDecision = nil
        autoPaused = false
        autoPauseCandidateSince = nil
        autoResumeCandidateSince = nil
        lastMotionWasStationary = false
        lastMotionCandidate = nil
        usingBarometricElevation = false
        hasAbsoluteBarometricAltitude = false
        pedometerBaseSteps = 0
        multisportTransition = false
        nextTriathlonActivity = nil
        triathlonMotionCandidate = nil
        triathlonMotionToken = UUID()
        automaticActivityTransitions = 0
        lastMetricSnapshotSend = .distantPast
        lastReliableMetricSnapshotSend = .distantPast
        lastAutoEvidenceSend = .distantPast
        autoConfidence = selectedActivity.isAutomatic ? "—" : "manuel"
        autoProvenance = selectedActivity.isAutomatic ? "En attente" : "Choix utilisateur"
        if !keepActivity {
            selectedActivity = .automatic
            effectiveActivity = .walking
        } else {
            effectiveActivity = initialEffectiveActivity(for: selectedActivity)
        }
    }

    private func configureLocation() {
        locationManager.delegate = self
        locationManager.activityType = .fitness
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter = 1.0
        locationManager.allowsBackgroundLocationUpdates = true
    }

    private func configureAltitudeSampler() {
        altitudeSampler.onRelativeDelta = { [weak self] delta in
            guard let self, self.phase == .active else { return }
            if delta > 0 { self.elevationGainMeters += delta }
            else { self.elevationLossMeters += abs(delta) }
            self.sendAuthority()
        }
        altitudeSampler.onAbsoluteAltitude = { [weak self] altitude, accuracy in
            guard let self, self.phase == .active, accuracy >= 0, accuracy <= 20 else { return }
            self.hasAbsoluteBarometricAltitude = true
            self.altitudeMeters = altitude
        }
    }

    private func requestLocationPermission() {
        if locationManager.authorizationStatus == .notDetermined { locationManager.requestWhenInUseAuthorization() }
    }

    private func startClock() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshElapsed()
                self.sendAuthority()
                self.sendMetricSnapshotIfNeeded()
            }
        }
    }

    private func refreshElapsed() {
        guard let startedAt else { elapsedSeconds = 0; return }
        let end = pausedAt ?? Date()
        elapsedSeconds = max(0, end.timeIntervalSince(startedAt) - pausedDuration)
    }

    private func startMotionClassifierIfNeeded() {
        guard CMMotionActivityManager.isActivityAvailable(), selectedActivity.isAutomatic || autoPauseEnabled || selectedActivity == .swimBikeRun else { return }
        activityManager.startActivityUpdates(to: .main) { [weak self] activity in
            guard let self, let activity, self.running else { return }
            guard activity.confidence != .low else { return }

            let rawMotionCandidate: ActivityKind?
            if activity.running { rawMotionCandidate = .running }
            else if activity.cycling { rawMotionCandidate = .cycling }
            else if activity.walking { rawMotionCandidate = .walking }
            else { rawMotionCandidate = nil }
            self.lastMotionCandidate = rawMotionCandidate

            if activity.stationary {
                self.lastMotionWasStationary = true
                self.lastMotionCandidate = nil
                self.stageAutoPauseIfNeeded()
                return
            }

            if rawMotionCandidate != nil {
                self.lastMotionWasStationary = false
                self.cancelPendingAutoPause()
                self.stageAutoResumeIfNeeded()
            }

            if self.selectedActivity.isAutomatic,
               let decision = WatchAutoPolicy.decision(
                    from: activity,
                    elapsedSeconds: self.elapsedSeconds,
                    distanceMeters: self.distanceMeters,
                    elevationGainMeters: self.elevationGainMeters,
                    elevationLossMeters: self.elevationLossMeters
               ) {
                self.updateAutoEvidence(decision)
                self.stageAutomaticCandidate(decision)
            }

            if self.selectedActivity == .swimBikeRun, let candidate = rawMotionCandidate {
                self.stageTriathlonMotionCandidate(candidate, confidence: WatchAutoPolicy.confidenceLabel(activity.confidence))
            }
        }
    }

    private func updateAutoEvidence(_ decision: WatchAutoDecision) {
        autoConfidence = decision.confidence
        autoProvenance = decision.provenance
        let now = Date()
        if now.timeIntervalSince(lastAutoEvidenceSend) >= 15 {
            lastAutoEvidenceSend = now
            sendEvent("auto_evidence", payload: [
                "activity": decision.activity.rawValue,
                "confidence": decision.confidence,
                "provenance": decision.provenance,
                "distance_m": distanceMeters,
                "elevation_gain_m": elevationGainMeters,
                "elevation_loss_m": elevationLossMeters,
            ])
        }
    }

    private func stageAutomaticCandidate(_ decision: WatchAutoDecision) {
        let candidate = decision.activity
        guard candidate != effectiveActivity else {
            autoCandidate = nil
            autoCandidateDecision = nil
            autoCandidateToken = UUID()
            return
        }
        if autoCandidate != candidate || autoCandidateDecision != decision {
            autoCandidate = candidate
            autoCandidateDecision = decision
            autoCandidateToken = UUID()
            let token = autoCandidateToken
            sendEvent("auto_candidate", payload: [
                "activity": candidate.rawValue,
                "confidence": decision.confidence,
                "provenance": decision.provenance,
                "dwell_s": decision.dwellSeconds,
            ])
            DispatchQueue.main.asyncAfter(deadline: .now() + decision.dwellSeconds) { [weak self] in
                guard let self, self.running, self.phase == .active, self.selectedActivity.isAutomatic,
                      self.autoCandidate == candidate, self.autoCandidateToken == token else { return }
                let previous = self.effectiveActivity
                self.effectiveActivity = candidate
                self.autoCandidate = nil
                self.autoCandidateDecision = nil
                self.automaticActivityTransitions += 1
                self.authorityRevision += 1
                self.sessionStatus = "Auto · \(candidate.label) détectée"
                let healthActivity = self.workoutSession?.workoutConfiguration.activityType ?? .other
                self.sendEvent("auto_activity_changed", payload: [
                    "from": previous.rawValue,
                    "to": candidate.rawValue,
                    "confidence": decision.confidence,
                    "provenance": decision.provenance,
                    "healthkit_container_type": healthActivity.rawValue,
                    "healthkit_activity": ActivityKind(healthKitType: healthActivity)?.rawValue ?? "unknown",
                    "healthkit_semantic_mismatch": healthActivity != candidate.healthKitType,
                ])
                self.sendAuthority(force: true)
                self.sendMetricSnapshotIfNeeded(force: true)
            }
        }
    }

    private func stageAutoPauseIfNeeded() {
        guard autoPauseEnabled, phase == .active else { return }
        guard WatchAutoPolicy.shouldStagePause(
            activity: displayActivity,
            stationary: lastMotionWasStationary,
            speedMps: currentSpeedMps,
            cadenceSPM: cadenceSPM
        ) else {
            cancelPendingAutoPause()
            return
        }
        guard autoPauseCandidateSince == nil else { return }
        autoPauseCandidateSince = Date()
        autoPauseToken = UUID()
        let token = autoPauseToken
        let delay = WatchAutoPolicy.pauseDwell(for: displayActivity)
        sendEvent("auto_pause_candidate", payload: [
            "activity": displayActivity.rawValue,
            "dwell_s": delay,
            "speed_mps": currentSpeedMps,
            "cadence_spm": cadenceSPM,
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.phase == .active, self.autoPauseEnabled,
                  self.autoPauseToken == token,
                  WatchAutoPolicy.shouldStagePause(
                    activity: self.displayActivity,
                    stationary: self.lastMotionWasStationary,
                    speedMps: self.currentSpeedMps,
                    cadenceSPM: self.cadenceSPM
                  ) else { return }
            self.autoPauseCandidateSince = nil
            self.autoPaused = true
            self.authorityRevision += 1
            self.pauseCore(reason: "auto")
            self.sendAuthority(force: true)
        }
    }

    private func cancelPendingAutoPause() {
        autoPauseCandidateSince = nil
        autoPauseToken = UUID()
    }

    private func stageAutoResumeIfNeeded() {
        guard autoPauseEnabled, phase == .paused, autoPaused else { return }
        guard WatchAutoPolicy.shouldStageResume(
            activity: displayActivity,
            stationary: lastMotionWasStationary,
            speedMps: currentSpeedMps,
            cadenceSPM: cadenceSPM,
            motionCandidate: lastMotionCandidate
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
            "motion_candidate": lastMotionCandidate?.rawValue ?? "none",
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.phase == .paused, self.autoPaused, self.autoPauseEnabled,
                  self.autoResumeToken == token,
                  WatchAutoPolicy.shouldStageResume(
                    activity: self.displayActivity,
                    stationary: self.lastMotionWasStationary,
                    speedMps: self.currentSpeedMps,
                    cadenceSPM: self.cadenceSPM,
                    motionCandidate: self.lastMotionCandidate
                  ) else { return }
            self.autoResumeCandidateSince = nil
            self.authorityRevision += 1
            self.resumeCore(reason: "auto")
            self.autoPaused = false
            self.sendAuthority(force: true)
        }
    }

    private func cancelPendingAutoResume() {
        autoResumeCandidateSince = nil
        autoResumeToken = UUID()
    }

    private func stageTriathlonMotionCandidate(_ candidate: ActivityKind, confidence: String) {
        guard selectedActivity == .swimBikeRun, phase == .active else { return }

        let expected: ActivityKind?
        let shouldStartTransition: Bool
        if multisportTransition {
            expected = nextTriathlonActivity
            shouldStartTransition = false
        } else {
            switch effectiveActivity {
            case .swimming:
                expected = (candidate == .walking || candidate == .cycling) ? candidate : nil
            case .cycling:
                expected = (candidate == .walking || candidate == .running) ? candidate : nil
            default:
                expected = nil
            }
            shouldStartTransition = expected != nil
        }
        guard let expected else {
            triathlonMotionCandidate = nil
            triathlonMotionToken = UUID()
            return
        }

        if multisportTransition, let next = nextTriathlonActivity {
            guard candidate == next else { return }
        }

        guard triathlonMotionCandidate != candidate else { return }
        triathlonMotionCandidate = candidate
        triathlonMotionToken = UUID()
        let token = triathlonMotionToken
        let dwell: TimeInterval = shouldStartTransition ? 12 : 8
        sendEvent("triathlon_auto_candidate", payload: [
            "candidate": candidate.rawValue,
            "confidence": confidence,
            "phase": multisportTransition ? "transition" : effectiveActivity.rawValue,
            "dwell_s": dwell,
        ])

        DispatchQueue.main.asyncAfter(deadline: .now() + dwell) { [weak self] in
            guard let self, self.phase == .active, self.selectedActivity == .swimBikeRun,
                  self.triathlonMotionCandidate == candidate, self.triathlonMotionToken == token else { return }
            self.sendEvent("triathlon_auto_transition", payload: [
                "candidate": candidate.rawValue,
                "confidence": confidence,
                "action": self.multisportTransition ? "start_next_segment" : "start_transition",
            ])
            self.advanceTriathlon()
            if self.multisportTransition, self.nextTriathlonActivity == candidate {
                self.triathlonMotionCandidate = nil
                self.stageTriathlonMotionCandidate(candidate, confidence: confidence)
            }
        }
    }

    private func stopMotionClassifier() {
        activityManager.stopActivityUpdates()
        autoCandidate = nil
        autoCandidateDecision = nil
        autoCandidateToken = UUID()
        cancelPendingAutoPause()
        cancelPendingAutoResume()
        triathlonMotionCandidate = nil
        triathlonMotionToken = UUID()
    }

    private func startMotion() {
        motionSampler.start { [weak self] frame in
            guard let self else { return }
            self.accelX = frame.accelX
            self.accelY = frame.accelY
            self.accelZ = frame.accelZ
            self.gyroX = frame.gyroX
            self.gyroY = frame.gyroY
            self.gyroZ = frame.gyroZ
            self.gyroSource = frame.gyroSource
            self.sendMotionIfNeeded()
        }
        sendEvent("motion_started", payload: [
            "gyro_available": motionSampler.isGyroAvailable,
        ])
    }

    private func stopMotion() {
        motionSampler.stop()
    }

    private func startAltitude() {
        usingBarometricElevation = CMAltimeter.isRelativeAltitudeAvailable()
        altitudeSampler.start()
        sendEvent("altimeter_started", payload: [
            "relative_available": CMAltimeter.isRelativeAltitudeAvailable(),
            "absolute_available": CMAltimeter.isAbsoluteAltitudeAvailable(),
        ])
    }

    private func stopAltitude() {
        altitudeSampler.stop()
    }

    private func startPedometer() {
        guard CMPedometer.isStepCountingAvailable() || CMPedometer.isCadenceAvailable() else { return }
        let base = steps
        pedometerBaseSteps = base
        pedometer.startUpdates(from: Date()) { [weak self] data, error in
            DispatchQueue.main.async {
                guard let self, self.running else { return }
                if let error {
                    self.sendEvent("pedometer_error", payload: ["message": error.localizedDescription])
                    return
                }
                guard let data else { return }
                self.steps = self.pedometerBaseSteps + data.numberOfSteps.intValue
                if let cadence = data.currentCadence?.doubleValue, cadence > 0 {
                    self.cadenceSPM = cadence * 60
                }
                var payload: [String: Any] = ["steps": self.steps]
                if self.cadenceSPM > 0 { payload["cadence_spm"] = self.cadenceSPM }
                if let pace = data.currentPace?.doubleValue { payload["pace_s_per_m"] = pace }
                self.sendSensorSample(kind: "pedometer", payload: payload, reliable: false)
            }
        }
    }

    private func stopPedometer() {
        pedometer.stopUpdates()
        pedometerBaseSteps = steps
    }

    private func accept(location: CLLocation) {
        guard phase == .active else { return }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 35 else { return }
        guard abs(location.timestamp.timeIntervalSinceNow) < 10 else { return }
        horizontalAccuracy = location.horizontalAccuracy
        currentCoordinate = location.coordinate
        if !hasAbsoluteBarometricAltitude { altitudeMeters = location.altitude }

        var acceptedForDistance = false
        var deltaMeters = 0.0
        var impliedSpeed = 0.0

        if let previous = previousLocation {
            let delta = location.distance(from: previous)
            let dt = location.timestamp.timeIntervalSince(previous.timestamp)
            let implied = dt > 0 ? delta / dt : .infinity
            let nativeSpeed = location.speed >= 0 ? location.speed : implied
            let limit = displayActivity.plausibleMaxSpeedMps
            let accuracyOK = max(previous.horizontalAccuracy, location.horizontalAccuracy) <= 25
            let plausible = dt > 0.15 && dt < 12 && delta >= 0.6 && delta < 150 && implied <= limit * 1.35 && nativeSpeed <= limit * 1.35

            deltaMeters = delta
            impliedSpeed = implied.isFinite ? implied : 0

            if accuracyOK, plausible {
                acceptedForDistance = true
                distanceMeters += delta
                let clipped = min(nativeSpeed, limit)
                currentSpeedMps = currentSpeedMps == 0 ? clipped : currentSpeedMps * 0.80 + clipped * 0.20
            } else if Date().timeIntervalSince(lastGPSRejectionEvent) > 5, delta > 3 {
                lastGPSRejectionEvent = Date()
                sendEvent("watch_gps_delta_rejected", payload: [
                    "delta_m": delta,
                    "dt_s": dt,
                    "implied_speed_mps": implied.isFinite ? implied : -1,
                    "native_speed_mps": nativeSpeed,
                    "horizontal_accuracy_m": location.horizontalAccuracy,
                    "limit_mps": limit,
                    "activity": displayActivity.rawValue,
                ])
            }
        }

        if !usingBarometricElevation {
            if location.verticalAccuracy >= 0, location.verticalAccuracy <= 12, let previousAltitudeLocation {
                let delta = location.altitude - previousAltitudeLocation.altitude
                if abs(delta) >= 3.0 {
                    if delta > 0 { elevationGainMeters += delta } else { elevationLossMeters += abs(delta) }
                    self.previousAltitudeLocation = location
                }
            } else if previousAltitudeLocation == nil, location.verticalAccuracy >= 0, location.verticalAccuracy <= 12 {
                previousAltitudeLocation = location
            }
        }

        if route.isEmpty || location.distance(from: CLLocation(latitude: route.last!.latitude, longitude: route.last!.longitude)) >= 1.5 {
            route.append(location.coordinate)
        }
        healthRouteLocations.append(location)
        previousLocation = location
        sendWatchLocationIfNeeded(location, acceptedForDistance: acceptedForDistance, deltaMeters: deltaMeters, impliedSpeed: impliedSpeed)
        if autoPauseEnabled { stageAutoPauseIfNeeded() }
        sendAuthority()
        sendMetricSnapshotIfNeeded()
    }

    private func sendMotionIfNeeded() {
        let now = Date()
        guard running, now.timeIntervalSince(lastMotionSend) >= 0.2 else { return }
        lastMotionSend = now
        sendSensorSample(kind: "motion", payload: [
            "accel": [accelX, accelY, accelZ],
            "gyro": [gyroX, gyroY, gyroZ],
            "gyro_source": gyroSource,
            "selected_activity": selectedActivity.rawValue,
            "effective_activity": effectiveActivity.rawValue,
        ], reliable: false)
    }

    private func sendWatchLocationIfNeeded(_ location: CLLocation, acceptedForDistance: Bool, deltaMeters: Double, impliedSpeed: Double) {
        let now = Date()
        guard now.timeIntervalSince(lastWatchLocationSend) >= 0.9 else { return }
        lastWatchLocationSend = now
        sendSensorSample(kind: "watch_location", payload: [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "altitude_m": location.altitude,
            "display_altitude_m": altitudeMeters,
            "distance_m": distanceMeters,
            "speed_mps": currentSpeedMps,
            "native_speed_mps": location.speed,
            "horizontal_accuracy_m": location.horizontalAccuracy,
            "vertical_accuracy_m": location.verticalAccuracy,
            "delta_m": deltaMeters,
            "implied_speed_mps": impliedSpeed,
            "accepted_for_distance": acceptedForDistance,
            "barometric_elevation": usingBarometricElevation,
            "selected_activity": selectedActivity.rawValue,
            "effective_activity": effectiveActivity.rawValue,
        ], reliable: false)
    }

    private func sendMetricSnapshotIfNeeded(force: Bool = false) {
        guard running || force, !sessionID.isEmpty else { return }
        let now = Date()
        let reachableInterval: TimeInterval = 2
        let offlineInterval: TimeInterval = 30

        if phoneReachable {
            guard force || now.timeIntervalSince(lastMetricSnapshotSend) >= reachableInterval else { return }
            lastMetricSnapshotSend = now
            sendSensorSample(kind: "authority_metrics", payload: metricSnapshotPayload(), reliable: false)
        } else {
            guard force || now.timeIntervalSince(lastReliableMetricSnapshotSend) >= offlineInterval else { return }
            lastReliableMetricSnapshotSend = now
            sendSensorSample(kind: "authority_metrics", payload: metricSnapshotPayload(), reliable: true)
        }
    }

    private func metricSnapshotPayload() -> [String: Any] {
        [
            "session_id": sessionID,
            "elapsed_s": elapsedSeconds,
            "distance_m": distanceMeters,
            "speed_mps": currentSpeedMps,
            "altitude_m": altitudeMeters,
            "elevation_gain_m": elevationGainMeters,
            "elevation_loss_m": elevationLossMeters,
            "heart_rate_bpm": heartRate,
            "average_heart_rate_bpm": averageHeartRate,
            "active_energy_kcal": activeEnergyKcal,
            "cadence_spm": cadenceSPM,
            "steps": steps,
            "selected_activity": selectedActivity.rawValue,
            "effective_activity": effectiveActivity.rawValue,
            "auto_confidence": autoConfidence,
            "auto_provenance": autoProvenance,
            "horizontal_accuracy_m": horizontalAccuracy,
            "barometric_elevation": usingBarometricElevation,
        ]
    }

    private func sendEvent(_ name: String, payload: [String: Any] = [:]) {
        var eventPayload = payload
        eventPayload["name"] = name
        eventPayload["session_id"] = sessionID
        eventPayload["authority_revision"] = authorityRevision
        eventPayload["timestamp"] = Date().timeIntervalSince1970
        sendSensorSample(kind: "event", payload: eventPayload, reliable: true)
    }

    private func sendSensorSample(kind: String, payload: [String: Any], reliable: Bool) {
        guard WCSession.isSupported() else { return }
        let packet: [String: Any] = [
            "type": "sensor_sample",
            "source": "watch",
            "kind": kind,
            "timestamp": Date().timeIntervalSince1970,
            "payload": payload,
        ]
        let session = WCSession.default
        if session.activationState == .activated, session.isReachable {
            session.sendMessage(packet, replyHandler: nil, errorHandler: nil)
        } else if reliable, session.activationState == .activated {
            session.transferUserInfo(packet)
        }
    }

    private func makeMessage(kind: TrackerWireMessage.Kind) -> TrackerWireMessage {
        TrackerWireMessage(
            kind: kind,
            command: nil,
            sessionID: sessionID,
            revision: authorityRevision,
            selectionRevision: selectionRevision,
            selectedActivity: selectedActivity.rawValue,
            effectiveActivity: effectiveActivity.rawValue,
            phase: running ? phase.rawValue : "ready",
            purgeID: lastPurgeID,
            timestamp: Date().timeIntervalSince1970,
            startedAt: startedAt?.timeIntervalSince1970,
            elapsedSeconds: elapsedSeconds,
            distanceMeters: distanceMeters,
            speedMps: currentSpeedMps,
            altitudeMeters: altitudeMeters,
            elevationGainMeters: elevationGainMeters,
            elevationLossMeters: elevationLossMeters,
            heartRateBPM: heartRate,
            averageHeartRateBPM: averageHeartRate,
            activeEnergyKcal: activeEnergyKcal
        )
    }

    private func sendAuthority(force: Bool = false, phaseOverride: String? = nil) {
        let now = Date()
        if !force, now.timeIntervalSince(lastStateSend) < 0.75 { return }
        lastStateSend = now
        var message = makeMessage(kind: .authority)
        if let phaseOverride { message.phase = phaseOverride }
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

    private func handleWire(_ message: TrackerWireMessage) {
        applyPurgeIfNeeded(message.purgeID)
        switch message.kind {
        case .request:
            handleRequest(message)
        case .selection:
            guard !running, message.selectionRevision >= selectionRevision else { return }
            selectionRevision = message.selectionRevision
            if let value = ActivityKind(rawValue: message.selectedActivity) { selectedActivity = value }
            effectiveActivity = initialEffectiveActivity(for: selectedActivity)
            sessionStatus = selectedActivity.isAutomatic ? "Auto synchronisé" : "\(selectedActivity.label) synchronisée"
            sendWC(makeMessage(kind: .selection))
        case .purge:
            applyPurgeIfNeeded(message.purgeID)
        case .authority:
            break
        }
    }

    private func handleRequest(_ message: TrackerWireMessage) {
        guard let command = message.command else { return }
        if command == "start" {
            guard !running else { sendAuthority(force: true); return }
            selectionRevision = max(selectionRevision, message.selectionRevision)
            if let value = ActivityKind(rawValue: message.selectedActivity) { selectedActivity = value }
            effectiveActivity = initialEffectiveActivity(for: selectedActivity)
            pendingRemoteSessionID = message.sessionID
            authorityRevision = max(1, authorityRevision + 1)
            if let config = pendingPhoneConfiguration {
                pendingPhoneConfiguration = nil
                start(configuration: config, origin: "iphone", sessionID: message.sessionID)
            } else {
                start(configuration: nil, origin: "iphone", sessionID: message.sessionID)
            }
            return
        }

        guard running, message.sessionID == sessionID else { return }
        switch command {
        case "pause":
            if phase == .active { pause() } else { sendAuthority(force: true) }
        case "resume":
            if phase == .paused { resume() } else { sendAuthority(force: true) }
        case "stop":
            if running { stop() }
        default:
            break
        }
    }

    private func handlePreferences(_ payload: [String: Any]) {
        guard !running, let enabled = payload["auto_pause_enabled"] as? Bool else { return }
        autoPauseEnabled = enabled
        defaults.set(enabled, forKey: "tracker.autoPauseEnabled")
    }

    private func applyPurgeIfNeeded(_ purgeID: String) {
        guard !purgeID.isEmpty, purgeID != lastPurgeID, !running else { return }
        applyPurge(purgeID)
    }

    private func applyPurge(_ purgeID: String) {
        guard !purgeID.isEmpty, purgeID != lastPurgeID else { return }
        lastPurgeID = purgeID
        defaults.set(purgeID, forKey: "tracker.lastPurgeID")
        resetPresentationData(keepActivity: true)
        sessionID = ""
        lastEndedSessionID = ""
        authorityRevision = 0
        sessionStatus = "Données locales effacées · suppression Santé…"
        deleteManagedHealthData()
    }

    private func deleteManagedHealthData() {
        let predicate = HKQuery.predicateForObjects(withMetadataKey: Self.managedWorkoutMetadataKey)

        healthStore.deleteObjects(of: HKSeriesType.workoutRoute(), predicate: predicate) { [weak self] routeSuccess, routeCount, routeError in
            guard let self else { return }
            self.healthStore.deleteObjects(of: HKObjectType.workoutType(), predicate: predicate) { [weak self] workoutSuccess, workoutCount, workoutError in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if routeSuccess && workoutSuccess {
                        self.sessionStatus = "Données locales + Santé effacées · \(workoutCount) séance(s), \(routeCount) parcours"
                    } else {
                        let detail = workoutError?.localizedDescription
                            ?? routeError?.localizedDescription
                            ?? "suppression HealthKit incomplète"
                        self.sessionStatus = "Données locales effacées · Santé: \(detail)"
                    }
                }
            }
        }
    }

    private static func makeSessionID() -> String { String(Int(Date().timeIntervalSince1970 * 1000)) }
    private static func revisionNow() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}

extension SensorModel: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.sendEvent("health_session_state", payload: [
                "from": fromState.rawValue,
                "to": toState.rawValue,
            ])
            if toState == .paused, self.phase == .active {
                self.phase = .paused
                self.authorityRevision += 1
                self.sendAuthority(force: true)
            } else if toState == .running, self.phase == .paused, !self.autoPaused {
                self.phase = .active
                self.authorityRevision += 1
                self.sendAuthority(force: true)
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.sessionStatus = "Santé: \(error.localizedDescription)"
            self?.sendEvent("health_session_error", payload: ["message": error.localizedDescription])
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        for packet in data {
            guard let message = TrackerWireCodec.decode(packet) else { continue }
            DispatchQueue.main.async { [weak self] in self?.handleWire(message) }
        }
    }
}

extension SensorModel: HKLiveWorkoutBuilderDelegate {
    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType,
                  let statistics = workoutBuilder.statistics(for: quantityType) else { continue }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch quantityType.identifier {
                case HKQuantityTypeIdentifier.heartRate.rawValue:
                    let unit = HKUnit.count().unitDivided(by: HKUnit.minute())
                    self.heartRate = statistics.mostRecentQuantity()?.doubleValue(for: unit) ?? self.heartRate
                    self.averageHeartRate = statistics.averageQuantity()?.doubleValue(for: unit) ?? self.averageHeartRate
                case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
                    self.activeEnergyKcal = statistics.sumQuantity()?.doubleValue(for: HKUnit.kilocalorie()) ?? self.activeEnergyKcal
                case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue,
                     HKQuantityTypeIdentifier.distanceCycling.rawValue,
                     HKQuantityTypeIdentifier.distanceSwimming.rawValue:
                    let healthDistance = statistics.sumQuantity()?.doubleValue(for: HKUnit.meter()) ?? 0
                    if healthDistance >= self.distanceMeters * 0.8, healthDistance <= self.distanceMeters * 1.25 + 100 {
                        self.distanceMeters = max(self.distanceMeters, healthDistance)
                    }
                default:
                    break
                }
                self.sendAuthority(force: true)
                self.sendMetricSnapshotIfNeeded()
            }
        }
    }
}

extension SensorModel: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            if phase == .active { manager.startUpdatingLocation() }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async { [weak self] in self?.accept(location: location) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.sessionStatus = "GPS: \(error.localizedDescription)"
            self?.sendEvent("location_error", payload: ["message": error.localizedDescription])
        }
    }
}

extension SensorModel: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.phoneReachable = session.isReachable
            if let error { self?.sessionStatus = "iPhone: \(error.localizedDescription)" }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let changed = self.phoneReachable != session.isReachable
            self.phoneReachable = session.isReachable
            if changed, self.running {
                self.sendEvent("iphone_reachability_changed", payload: ["reachable": session.isReachable])
                self.sendMetricSnapshotIfNeeded(force: true)
            }
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { receiveWC(message) }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { receiveWC(applicationContext) }

    private func receiveWC(_ payload: [String: Any]) {
        if payload["type"] as? String == "tracker_preferences_v4" {
            DispatchQueue.main.async { [weak self] in self?.handlePreferences(payload) }
            return
        }

        guard payload["type"] as? String == "tracker_wire_v3",
              let data = payload["data"] as? Data,
              let message = TrackerWireCodec.decode(data) else { return }
        DispatchQueue.main.async { [weak self] in self?.handleWire(message) }
    }
}
