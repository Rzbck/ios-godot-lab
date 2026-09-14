import SwiftUI

/// Runtime auto-pause policy on the Watch.
///
/// The user-facing control is intentionally just the master Auto-Pause toggle.
/// Stabilization delays are small implementation details, not workout settings.
/// This keeps the behavior close to the native Workout experience: stop moving,
/// pause automatically; move again, resume automatically.
enum WatchAutoPauseSettings {
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
