import Foundation
import SwiftUI

/// Runtime auto-pause policy on the Watch.
///
/// The user-facing control remains a single master Auto-Pause toggle. Runtime
/// stabilization is intentionally conservative: false pauses are worse than a
/// slightly late pause, especially for low-speed walking and imperfect GPS.
enum WatchAutoPauseSettings {
    // Legacy storage/wire keys. SensorModel still accepts them so an iPhone on
    // an older build can synchronize safely during upgrades. They no longer
    // tune runtime behavior in the new adaptive mode.
    static let walkEnabledKey = "tracker.autoPause.walk.enabled"
    static let hikeEnabledKey = "tracker.autoPause.hike.enabled"
    static let runEnabledKey = "tracker.autoPause.run.enabled"
    static let cycleEnabledKey = "tracker.autoPause.cycle.enabled"

    static let walkPauseDwellKey = "tracker.autoPause.walk.pauseDwell"
    static let hikePauseDwellKey = "tracker.autoPause.hike.pauseDwell"
    static let runPauseDwellKey = "tracker.autoPause.run.pauseDwell"
    static let cyclePauseDwellKey = "tracker.autoPause.cycle.pauseDwell"

    static let walkResumeDwellKey = "tracker.autoPause.walk.resumeDwell"
    static let hikeResumeDwellKey = "tracker.autoPause.hike.resumeDwell"
    static let runResumeDwellKey = "tracker.autoPause.run.resumeDwell"
    static let cycleResumeDwellKey = "tracker.autoPause.cycle.resumeDwell"

    static func isEnabled(
        for activity: ActivityKind,
        defaults: UserDefaults = .standard
    ) -> Bool {
        _ = defaults
        return TrackerAutoPauseStabilityPolicy.supports(activity)
    }

    static func pauseDwell(
        for activity: ActivityKind,
        defaults: UserDefaults = .standard
    ) -> TimeInterval {
        _ = defaults
        return TrackerAutoPauseStabilityPolicy.pauseDwell(for: activity)
    }

    static func resumeDwell(
        for activity: ActivityKind,
        defaults: UserDefaults = .standard
    ) -> TimeInterval {
        _ = defaults
        return TrackerAutoPauseStabilityPolicy.resumeDwell(for: activity)
    }

    static func stationaryEvidenceFreshness(
        for activity: ActivityKind,
        defaults: UserDefaults = .standard
    ) -> TimeInterval {
        _ = defaults
        return TrackerAutoPauseStabilityPolicy.stationaryEvidenceFreshness(for: activity)
    }

    static func speedEvidenceFreshness(
        for activity: ActivityKind,
        defaults: UserDefaults = .standard
    ) -> TimeInterval {
        _ = defaults
        return TrackerAutoPauseStabilityPolicy.speedEvidenceFreshness(for: activity)
    }

    static func repauseCooldown(
        for activity: ActivityKind,
        defaults: UserDefaults = .standard
    ) -> TimeInterval {
        _ = defaults
        return TrackerAutoPauseStabilityPolicy.repauseCooldown(for: activity)
    }
}

struct WatchAutoPauseSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Pause auto adaptative", systemImage: "pause.circle.fill")
                        .font(.headline)

                    Text(
                        "La Watch confirme un arrêt avec plusieurs signaux avant de mettre en pause. Après une reprise, une courte hystérésis évite les bascules pause/reprise répétées."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    Text(
                        "Pause auto est volontairement prudente et limitée aux activités locomotrices prises en charge. Le bouton Pause reste toujours prioritaire."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Pause auto")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }
}
