import Foundation

/// Versioned, device-independent input format for accelerated workout replay.
///
/// A scenario describes evidence over virtual time. It does not write HealthKit,
/// start a workout session, touch GPS, or communicate with a paired Watch.
/// The same schema can later be consumed by XCTest, UI-test launch fixtures, or
/// a read-only on-device self-test endpoint.
struct TrackerAutomationFrame: Codable, Equatable {
    let offsetSeconds: TimeInterval
    let motion: TrackerMotionEvidence
    let speedMps: Double
    let cadenceSPM: Double
    let heartRateBPM: Double
    let distanceDeltaMeters: Double
    let horizontalAccuracyMeters: Double
}

struct TrackerAutomationScenario: Codable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let name: String
    let selectedActivity: ActivityKind
    let autoPauseEnabled: Bool
    let frames: [TrackerAutomationFrame]

    init(
        name: String,
        selectedActivity: ActivityKind = .automatic,
        autoPauseEnabled: Bool = true,
        frames: [TrackerAutomationFrame]
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.name = name
        self.selectedActivity = selectedActivity
        self.autoPauseEnabled = autoPauseEnabled
        self.frames = frames
    }

    func validate() throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw TrackerAutomationScenarioError.unsupportedSchema(schemaVersion)
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TrackerAutomationScenarioError.emptyName
        }
        guard !frames.isEmpty else {
            throw TrackerAutomationScenarioError.emptyFrames
        }

        var previousOffset: TimeInterval = -1
        for (index, frame) in frames.enumerated() {
            guard frame.offsetSeconds >= 0,
                  frame.offsetSeconds > previousOffset else {
                throw TrackerAutomationScenarioError.nonMonotonicTime(index)
            }
            guard frame.speedMps >= 0,
                  frame.cadenceSPM >= 0,
                  frame.heartRateBPM >= 0,
                  frame.distanceDeltaMeters >= 0,
                  frame.horizontalAccuracyMeters >= 0 else {
                throw TrackerAutomationScenarioError.negativeMetric(index)
            }
            previousOffset = frame.offsetSeconds
        }
    }
}

enum TrackerAutomationScenarioError: Error, Equatable {
    case unsupportedSchema(Int)
    case emptyName
    case emptyFrames
    case nonMonotonicTime(Int)
    case negativeMetric(Int)
}

struct TrackerAutomationReplayResult: Equatable {
    let activityCandidates: [ActivityKind]
    let pauseCandidateFrameIndexes: [Int]
    let resumeCandidateFrameIndexes: [Int]
    let autoPauseFrameIndexes: [Int]
    let autoResumeFrameIndexes: [Int]
    let endedPaused: Bool
    let totalDistanceMeters: Double
    let maximumSpeedMps: Double
    let finalHeartRateBPM: Double
}

enum TrackerAutomationReplayer {
    static func replay(
        _ scenario: TrackerAutomationScenario
    ) throws -> TrackerAutomationReplayResult {
        try scenario.validate()

        var candidates: [ActivityKind] = []
        var pauseIndexes: [Int] = []
        var resumeIndexes: [Int] = []
        var totalDistance = 0.0
        var maxSpeed = 0.0
        var finalHeartRate = 0.0
        var movementObserved = false
        var currentActivity = scenario.selectedActivity
        var autoPaused = false
        var pauseEligibleSince: TimeInterval?
        var resumeEligibleSince: TimeInterval?
        var autoPauseIndexes: [Int] = []
        var autoResumeIndexes: [Int] = []

        for (index, frame) in scenario.frames.enumerated() {
            let decision = TrackerAutoPolicy.decision(
                from: frame.motion,
                speedMps: frame.speedMps,
                cadenceSPM: frame.cadenceSPM
            )
            if let decision {
                candidates.append(decision.activity)
                currentActivity = decision.activity
            }

            let motionMovementObserved = frame.motion.walking
                || frame.motion.running
                || frame.motion.cycling
            if frame.distanceDeltaMeters > 0 {
                movementObserved = true
            }

            let canPause = TrackerAutoPolicy.canArmPause(
                activity: currentActivity,
                elapsedSeconds: frame.offsetSeconds,
                horizontalAccuracy: frame.horizontalAccuracyMeters,
                movementObserved: movementObserved,
                motionMovementObserved: motionMovementObserved
            ) && TrackerAutoPolicy.shouldStagePause(
                activity: currentActivity,
                enabled: scenario.autoPauseEnabled,
                stationary: frame.motion.stationary,
                speedMps: frame.speedMps,
                cadenceSPM: frame.cadenceSPM
            )
            if canPause {
                pauseIndexes.append(index)
            }

            let canResume = TrackerAutoPolicy.shouldStageResume(
                activity: currentActivity,
                enabled: scenario.autoPauseEnabled,
                stationary: frame.motion.stationary,
                speedMps: frame.speedMps,
                cadenceSPM: frame.cadenceSPM,
                motionCandidate: decision?.activity
            )
            if canResume {
                resumeIndexes.append(index)
            }

            if !autoPaused {
                if canPause {
                    if let since = pauseEligibleSince,
                       frame.offsetSeconds - since >= 2 {
                        autoPaused = true
                        autoPauseIndexes.append(index)
                        pauseEligibleSince = nil
                    } else if pauseEligibleSince == nil {
                        pauseEligibleSince = frame.offsetSeconds
                    }
                } else {
                    pauseEligibleSince = nil
                }
            } else if canResume {
                if let since = resumeEligibleSince,
                   frame.offsetSeconds - since >= 0.8 {
                    autoPaused = false
                    autoResumeIndexes.append(index)
                    resumeEligibleSince = nil
                } else if resumeEligibleSince == nil {
                    resumeEligibleSince = frame.offsetSeconds
                }
            } else {
                resumeEligibleSince = nil
            }

            totalDistance += frame.distanceDeltaMeters
            maxSpeed = max(maxSpeed, frame.speedMps)
            finalHeartRate = frame.heartRateBPM
        }

        return TrackerAutomationReplayResult(
            activityCandidates: candidates,
            pauseCandidateFrameIndexes: pauseIndexes,
            resumeCandidateFrameIndexes: resumeIndexes,
            autoPauseFrameIndexes: autoPauseIndexes,
            autoResumeFrameIndexes: autoResumeIndexes,
            endedPaused: autoPaused,
            totalDistanceMeters: totalDistance,
            maximumSpeedMps: maxSpeed,
            finalHeartRateBPM: finalHeartRate
        )
    }
}

enum TrackerAutomationFixtures {
    static let walkRunCycle = TrackerAutomationScenario(
        name: "walk-run-cycle",
        frames: [
            frame(at: 0, walking: true, speed: 1.4, cadence: 105, heart: 92, distance: 0),
            frame(at: 5, walking: true, speed: 1.5, cadence: 112, heart: 98, distance: 7),
            frame(at: 10, running: true, speed: 3.1, cadence: 164, heart: 132, distance: 16),
            frame(at: 15, running: true, speed: 3.4, cadence: 172, heart: 145, distance: 17),
            frame(at: 20, cycling: true, speed: 6.8, cadence: 0, heart: 138, distance: 34),
            frame(at: 25, cycling: true, speed: 7.2, cadence: 0, heart: 142, distance: 36),
        ]
    )

    static let stopAndResumeWalking = TrackerAutomationScenario(
        name: "walking-auto-pause-resume",
        frames: [
            frame(at: 0, walking: true, speed: 1.2, cadence: 96, heart: 90, distance: 0),
            frame(at: 5, stationary: true, speed: 0.1, cadence: 0, heart: 86, distance: 1),
            frame(at: 10, stationary: true, speed: 0.0, cadence: 0, heart: 82, distance: 0),
            frame(at: 15, walking: true, speed: 1.0, cadence: 88, heart: 91, distance: 5),
        ]
    )

    private static func frame(
        at offset: TimeInterval,
        walking: Bool = false,
        running: Bool = false,
        cycling: Bool = false,
        stationary: Bool = false,
        speed: Double,
        cadence: Double,
        heart: Double,
        distance: Double
    ) -> TrackerAutomationFrame {
        TrackerAutomationFrame(
            offsetSeconds: offset,
            motion: TrackerMotionEvidence(
                walking: walking,
                running: running,
                cycling: cycling,
                stationary: stationary,
                confidence: .high
            ),
            speedMps: speed,
            cadenceSPM: cadence,
            heartRateBPM: heart,
            distanceDeltaMeters: distance,
            horizontalAccuracyMeters: 5
        )
    }
}
