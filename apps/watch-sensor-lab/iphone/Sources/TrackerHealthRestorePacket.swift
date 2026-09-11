import Foundation

enum TrackerHealthRestorePacketError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message):
            return message
        }
    }
}

final class TrackerHealthRestorePacketBuilder {
    private struct PauseMark {
        let timestamp: TimeInterval
        let pause: Bool
    }

    private struct PhaseMark {
        let timestamp: TimeInterval
        let from: String
        let to: String
    }

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    func makeTransferFile(
        sessionID: String,
        targetActivity: ActivityKind
    ) throws -> URL {
        guard
            !sessionID.isEmpty,
            !targetActivity.isAutomatic
        else {
            throw TrackerHealthRestorePacketError.invalid(
                "demande de restauration invalide"
            )
        }

        let documents =
            try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: false
            )

        let directory =
            documents
                .appendingPathComponent(
                    "Sessions",
                    isDirectory: true
                )
                .appendingPathComponent(
                    sessionID,
                    isDirectory: true
                )

        let summaryURL =
            directory.appendingPathComponent(
                "summary.json"
            )

        let samplesURL =
            directory.appendingPathComponent(
                "samples.jsonl"
            )

        guard
            FileManager.default.fileExists(
                atPath: summaryURL.path
            ),
            FileManager.default.fileExists(
                atPath: samplesURL.path
            )
        else {
            throw TrackerHealthRestorePacketError.invalid(
                "raw Tracker ou summary.json absent"
            )
        }

        let summary =
            try decoder.decode(
                TrackerSummary.self,
                from: Data(contentsOf: summaryURL)
            )

        guard summary.sessionID == sessionID else {
            throw TrackerHealthRestorePacketError.invalid(
                "summary.json ne correspond pas à la session"
            )
        }

        let startedAt =
            summary.startedAt.timeIntervalSince1970

        let endedAt =
            summary.endedAt.timeIntervalSince1970

        guard endedAt > startedAt else {
            throw TrackerHealthRestorePacketError.invalid(
                "bornes temporelles Tracker invalides"
            )
        }

        var watchLocations:
            [TrackerHealthRestoreLocation] = []

        var phoneLocations:
            [TrackerHealthRestoreLocation] = []

        var heartRates:
            [TrackerHealthRestoreHeartRate] = []

        var pauseMarks: [PauseMark] = []
        var phaseMarks: [PhaseMark] = []

        var sources = [samplesURL]

        let reliableURL =
            directory.appendingPathComponent(
                "watch_reliable.jsonl"
            )

        if FileManager.default.fileExists(
            atPath: reliableURL.path
        ) {
            sources.append(reliableURL)
        }

        for sourceURL in sources {
            let text =
                try String(
                    contentsOf: sourceURL,
                    encoding: .utf8
                )

            for rawLine in text.split(
                separator: "\n",
                omittingEmptySubsequences: true
            ) {
                guard
                    let data =
                        String(rawLine).data(
                            using: .utf8
                        ),
                    let object =
                        try? JSONSerialization
                            .jsonObject(with: data)
                            as? [String: Any],
                    let timestamp =
                        number(object["timestamp"])
                else {
                    continue
                }

                // On ne transporte jamais des points extérieurs
                // à la séance réelle.
                guard
                    timestamp >= startedAt,
                    timestamp <= endedAt
                else {
                    continue
                }

                let record =
                    object["record"] as? String ?? ""

                let kind =
                    object["kind"] as? String ?? ""

                let source =
                    object["source"] as? String ?? ""

                let payload =
                    object["payload"]
                        as? [String: Any] ?? [:]

                let quality =
                    object["quality"]
                        as? [String: Any] ?? [:]

                if record == "sample",
                   kind == "heart_rate",
                   source == "watch",
                   let bpm = number(payload["bpm"]),
                   bpm > 0,
                   bpm < 260 {

                    heartRates.append(
                        TrackerHealthRestoreHeartRate(
                            timestamp: timestamp,
                            bpm: bpm
                        )
                    )
                    continue
                }

                if record == "sample",
                   kind == "watch_location",
                   let latitude =
                        number(payload["latitude"]),
                   let longitude =
                        number(payload["longitude"]) {

                    let horizontal =
                        number(
                            payload[
                                "horizontal_accuracy_m"
                            ]
                        ) ?? -1

                    if horizontal >= 0,
                       horizontal <= 50 {

                        watchLocations.append(
                            TrackerHealthRestoreLocation(
                                timestamp: timestamp,
                                latitude: latitude,
                                longitude: longitude,
                                altitudeMeters:
                                    number(
                                        payload[
                                            "altitude_m"
                                        ]
                                    ) ?? 0,
                                horizontalAccuracyMeters:
                                    horizontal,
                                verticalAccuracyMeters:
                                    number(
                                        payload[
                                            "vertical_accuracy_m"
                                        ]
                                    ) ?? -1,
                                speedMps:
                                    number(
                                        payload[
                                            "native_speed_mps"
                                        ]
                                    )
                                    ?? number(
                                        payload[
                                            "speed_mps"
                                        ]
                                    )
                            )
                        )
                    }
                    continue
                }

                if record == "sample",
                   kind == "location",
                   let latitude =
                        number(payload["latitude"]),
                   let longitude =
                        number(payload["longitude"]) {

                    let horizontal =
                        number(
                            quality[
                                "horizontal_accuracy_m"
                            ]
                        ) ?? -1

                    if horizontal >= 0,
                       horizontal <= 50 {

                        phoneLocations.append(
                            TrackerHealthRestoreLocation(
                                timestamp: timestamp,
                                latitude: latitude,
                                longitude: longitude,
                                altitudeMeters:
                                    number(
                                        payload[
                                            "altitude_m"
                                        ]
                                    ) ?? 0,
                                horizontalAccuracyMeters:
                                    horizontal,
                                verticalAccuracyMeters:
                                    number(
                                        quality[
                                            "vertical_accuracy_m"
                                        ]
                                    ) ?? -1,
                                speedMps:
                                    number(
                                        quality[
                                            "native_speed_mps"
                                        ]
                                    )
                                    ?? number(
                                        payload[
                                            "speed_mps"
                                        ]
                                    )
                            )
                        )
                    }
                    continue
                }

                guard record == "event" else {
                    continue
                }

                let event =
                    object["event"] as? String ?? ""

                // Source préférée : les événements explicites
                // émis par pauseCore/resumeCore sur la Watch.
                if source == "watch",
                   event == "manual_pause"
                    || event == "auto_pause" {

                    pauseMarks.append(
                        PauseMark(
                            timestamp: timestamp,
                            pause: true
                        )
                    )
                    continue
                }

                if source == "watch",
                   event == "manual_resume"
                    || event == "auto_resume" {

                    pauseMarks.append(
                        PauseMark(
                            timestamp: timestamp,
                            pause: false
                        )
                    )
                    continue
                }

                // Fallback uniquement si les événements explicites
                // ne sont pas disponibles.
                if source == "watch",
                   event == "phase_changed",
                   let from =
                        payload["from"] as? String,
                   let to =
                        payload["to"] as? String {

                    phaseMarks.append(
                        PhaseMark(
                            timestamp: timestamp,
                            from: from,
                            to: to
                        )
                    )
                }
            }
        }

        heartRates =
            deduplicateHeartRates(
                heartRates
            )

        watchLocations =
            deduplicateLocations(
                watchLocations
            )

        phoneLocations =
            deduplicateLocations(
                phoneLocations
            )

        let locations =
            watchLocations.count >= 2
                ? watchLocations
                : phoneLocations

        let pauseResult =
            makePauses(
                explicit: pauseMarks,
                fallback: phaseMarks,
                workoutStart: startedAt,
                workoutEnd: endedAt
            )

        let pauses = pauseResult.pauses

        let wallDuration =
            endedAt - startedAt

        let pauseDuration =
            pauses.reduce(0) {
                $0
                    + max(
                        0,
                        $1.endedAt - $1.startedAt
                    )
            }

        let reconstructedActive =
            max(
                0,
                wallDuration - pauseDuration
            )

        let durationTolerance =
            max(
                20,
                summary.duration * 0.04
            )

        guard
            abs(
                reconstructedActive
                    - summary.duration
            ) <= durationTolerance
        else {
            throw TrackerHealthRestorePacketError.invalid(
                String(
                    format:
                        "pauses raw incohérentes : actif %.1fs, attendu %.1fs",
                    reconstructedActive,
                    summary.duration
                )
            )
        }

        guard !heartRates.isEmpty else {
            throw TrackerHealthRestorePacketError.invalid(
                "aucune fréquence cardiaque Watch brute"
            )
        }

        guard locations.count >= 2 else {
            throw TrackerHealthRestorePacketError.invalid(
                "parcours GPS Tracker insuffisant"
            )
        }

        guard summary.distanceMeters > 0 else {
            throw TrackerHealthRestorePacketError.invalid(
                "distance Tracker invalide"
            )
        }

        let restore =
            TrackerHealthRestorePayload(
                schema:
                    TrackerHealthRestorePayload
                        .currentSchema,
                sessionID:
                    summary.sessionID,
                targetActivity:
                    targetActivity.rawValue,
                sourceActivity:
                    summary.activity,
                startedAt:
                    startedAt,
                endedAt:
                    endedAt,
                activeDuration:
                    summary.duration,
                distanceMeters:
                    summary.distanceMeters,
                activeEnergyKcal:
                    summary.activeEnergyKcal,
                heartRates:
                    heartRates,
                locations:
                    locations,
                pauses:
                    pauses,
                pauseProvenance:
                    pauseResult.provenance,
                sourceBuildSHA:
                    summary.buildSHA,
                sourceAlgorithmVersion:
                    summary.algorithmVersion
            )

        let cache =
            FileManager.default
                .temporaryDirectory
                .appendingPathComponent(
                    "TrackerHealthRestore",
                    isDirectory: true
                )

        try FileManager.default
            .createDirectory(
                at: cache,
                withIntermediateDirectories: true
            )

        let output =
            cache.appendingPathComponent(
                "restore-\(sessionID)-\(UUID().uuidString).json"
            )

        try encoder
            .encode(restore)
            .write(
                to: output,
                options: .atomic
            )

        return output
    }

    private func makePauses(
        explicit: [PauseMark],
        fallback: [PhaseMark],
        workoutStart: TimeInterval,
        workoutEnd: TimeInterval
    ) -> (
        pauses: [TrackerHealthRestorePause],
        provenance: String
    ) {
        let explicit =
            deduplicatePauseMarks(explicit)

        if explicit.contains(
            where: { $0.pause }
        ) {
            return (
                intervals(
                    from: explicit,
                    workoutStart: workoutStart,
                    workoutEnd: workoutEnd
                ),
                "watch_pause_events"
            )
        }

        let fallbackMarks =
            fallback
                .sorted {
                    $0.timestamp
                        < $1.timestamp
                }
                .compactMap {
                    mark -> PauseMark? in

                    if mark.from == "active",
                       mark.to == "paused" {
                        return PauseMark(
                            timestamp:
                                mark.timestamp,
                            pause: true
                        )
                    }

                    if mark.from == "paused",
                       mark.to == "active" {
                        return PauseMark(
                            timestamp:
                                mark.timestamp,
                            pause: false
                        )
                    }

                    if mark.from == "paused",
                       mark.to == "ended" {
                        return PauseMark(
                            timestamp:
                                min(
                                    mark.timestamp,
                                    workoutEnd
                                ),
                            pause: false
                        )
                    }

                    return nil
                }

        return (
            intervals(
                from:
                    deduplicatePauseMarks(
                        fallbackMarks
                    ),
                workoutStart:
                    workoutStart,
                workoutEnd:
                    workoutEnd
            ),
            "watch_phase_fallback"
        )
    }

    private func intervals(
        from marks: [PauseMark],
        workoutStart: TimeInterval,
        workoutEnd: TimeInterval
    ) -> [TrackerHealthRestorePause] {
        var result:
            [TrackerHealthRestorePause] = []

        var currentStart:
            TimeInterval?

        for mark in marks.sorted(
            by: {
                $0.timestamp
                    < $1.timestamp
            }
        ) {
            let timestamp =
                min(
                    max(
                        mark.timestamp,
                        workoutStart
                    ),
                    workoutEnd
                )

            if mark.pause {
                if currentStart == nil {
                    currentStart =
                        timestamp
                }
            } else if let start =
                currentStart {

                if timestamp > start {
                    result.append(
                        TrackerHealthRestorePause(
                            startedAt: start,
                            endedAt: timestamp
                        )
                    )
                }

                currentStart = nil
            }
        }

        if let start =
            currentStart,
           workoutEnd > start {

            result.append(
                TrackerHealthRestorePause(
                    startedAt: start,
                    endedAt: workoutEnd
                )
            )
        }

        return result
    }

    private func deduplicatePauseMarks(
        _ values: [PauseMark]
    ) -> [PauseMark] {
        var result: [PauseMark] = []

        for value in values.sorted(
            by: {
                $0.timestamp
                    < $1.timestamp
            }
        ) {
            if let last = result.last,
               last.pause == value.pause,
               abs(
                    last.timestamp
                        - value.timestamp
               ) < 1 {
                continue
            }

            result.append(value)
        }

        return result
    }

    private func deduplicateHeartRates(
        _ values:
            [TrackerHealthRestoreHeartRate]
    ) -> [TrackerHealthRestoreHeartRate] {
        var seen = Set<Int64>()
        var result:
            [TrackerHealthRestoreHeartRate] = []

        for value in values.sorted(
            by: {
                $0.timestamp
                    < $1.timestamp
            }
        ) {
            let key =
                Int64(
                    (
                        value.timestamp
                            * 1000
                    ).rounded()
                )

            if seen.insert(key).inserted {
                result.append(value)
            }
        }

        return result
    }

    private func deduplicateLocations(
        _ values:
            [TrackerHealthRestoreLocation]
    ) -> [TrackerHealthRestoreLocation] {
        var seen = Set<String>()
        var result:
            [TrackerHealthRestoreLocation] = []

        for value in values.sorted(
            by: {
                $0.timestamp
                    < $1.timestamp
            }
        ) {
            let key =
                String(
                    format:
                        "%.3f|%.6f|%.6f",
                    value.timestamp,
                    value.latitude,
                    value.longitude
                )

            if seen.insert(key).inserted {
                result.append(value)
            }
        }

        return result
    }

    private func number(
        _ value: Any?
    ) -> Double? {
        if let number =
            value as? NSNumber {
            return number.doubleValue
        }

        if let value =
            value as? Double {
            return value
        }

        return nil
    }
}
