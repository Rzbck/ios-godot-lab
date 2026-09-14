import Foundation
import SwiftUI

/// Runtime auto-pause policy on the Watch.
///
/// The user-facing control is intentionally just the master Auto-Pause toggle.
/// Stabilization delays are small implementation details, not workout settings.
/// This keeps the behavior close to the native Workout experience: stop moving,
/// pause automatically; move again, resume automatically.
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
        _ = activity
        _ = defaults
        return true
    }

    static func pauseDwell(
        for activity: ActivityKind,
        defaults: UserDefaults = .standard
    ) -> TimeInterval {
        _ = activity
        _ = defaults
        return 2.0
    }

    static func resumeDwell(
        for activity: ActivityKind,
        defaults: UserDefaults = .standard
    ) -> TimeInterval {
        _ = activity
        _ = defaults
        return 0.8
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
                        "Aucun délai à régler. Quand Pause automatique est activée, la Watch combine mouvement, GPS et cadence pour mettre en pause et reprendre de façon réactive."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    Text(
                        "Le bouton Pause reste prioritaire : une pause manuelle ne redémarre jamais toute seule."
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
