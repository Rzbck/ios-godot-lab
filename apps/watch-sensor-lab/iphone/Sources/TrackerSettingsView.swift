import Foundation
import SwiftUI

// Legacy preference model kept for wire/backward compatibility with installs
// that already persisted per-sport values. The product no longer exposes these
// timings: the Watch applies one adaptive runtime policy behind the master
// Auto-Pause toggle.
enum AutoPauseProfileKind: String, CaseIterable, Identifiable, Hashable {
    case walking
    case hiking
    case running
    case cycling

    var id: String { rawValue }

    var label: String {
        switch self {
        case .walking: return "Marche"
        case .hiking: return "Randonnée"
        case .running: return "Course"
        case .cycling: return "Vélo"
        }
    }

    var symbol: String {
        switch self {
        case .walking: return "figure.walk"
        case .hiking: return "figure.hiking"
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        }
    }

    // Kept only so older code/configuration payloads remain source compatible.
    var pauseRange: ClosedRange<Double> { 1...30 }
    var resumeRange: ClosedRange<Double> { 0.5...15 }

    var defaultPreference: AutoPauseProfilePreference {
        .init(enabled: true, pauseDwell: 2.0, resumeDwell: 0.8)
    }

    var enabledPayloadKey: String { "auto_pause_\(rawValue)_enabled" }
    var pausePayloadKey: String { "auto_pause_\(rawValue)_pause_dwell" }
    var resumePayloadKey: String { "auto_pause_\(rawValue)_resume_dwell" }
}

struct AutoPauseProfilePreference: Equatable {
    var enabled: Bool
    var pauseDwell: Double
    var resumeDwell: Double
}

enum PhoneAutoPausePreferences {
    private static let configuredPrefix = "tracker.phoneAutoPause.configured."
    private static let enabledPrefix = "tracker.phoneAutoPause.enabled."
    private static let pausePrefix = "tracker.phoneAutoPause.pauseDwell."
    private static let resumePrefix = "tracker.phoneAutoPause.resumeDwell."

    static func load(defaults: UserDefaults = .standard) -> [AutoPauseProfileKind: AutoPauseProfilePreference] {
        Dictionary(uniqueKeysWithValues: AutoPauseProfileKind.allCases.map { profile in
            let fallback = profile.defaultPreference
            let enabledKey = enabledPrefix + profile.rawValue
            let pauseKey = pausePrefix + profile.rawValue
            let resumeKey = resumePrefix + profile.rawValue
            let enabled = defaults.object(forKey: enabledKey) == nil ? fallback.enabled : defaults.bool(forKey: enabledKey)
            let pause = defaults.object(forKey: pauseKey) == nil ? fallback.pauseDwell : defaults.double(forKey: pauseKey)
            let resume = defaults.object(forKey: resumeKey) == nil ? fallback.resumeDwell : defaults.double(forKey: resumeKey)
            return (
                profile,
                AutoPauseProfilePreference(
                    enabled: enabled,
                    pauseDwell: pause,
                    resumeDwell: resume
                )
            )
        })
    }

    static func isConfigured(
        _ profile: AutoPauseProfileKind,
        defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.bool(forKey: configuredPrefix + profile.rawValue)
    }

    static func save(
        _ preference: AutoPauseProfilePreference,
        for profile: AutoPauseProfileKind,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(preference.enabled, forKey: enabledPrefix + profile.rawValue)
        defaults.set(preference.pauseDwell, forKey: pausePrefix + profile.rawValue)
        defaults.set(preference.resumeDwell, forKey: resumePrefix + profile.rawValue)
        defaults.set(true, forKey: configuredPrefix + profile.rawValue)
    }
}

struct TrackerSettingsView: View {
    @EnvironmentObject private var tracker: TrackerModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(
                        "Pause automatique",
                        isOn: Binding(
                            get: { tracker.autoPauseEnabled },
                            set: { tracker.workflowSetAutoPauseEnabled($0) }
                        )
                    )
                    .tint(.mint)

                    Label("Mode adaptatif", systemImage: "waveform.path.ecg")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Entraînement")
                } footer: {
                    Text(
                        "Aucun délai à régler. La Watch combine mouvement, GPS et cadence pour mettre en pause et reprendre automatiquement. La pause manuelle reste prioritaire."
                    )
                }

                Section("Connexion") {
                    LabeledContent("Apple Watch") {
                        if tracker.watchReachable {
                            Label("Connectée", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Label("Non joignable", systemImage: "exclamationmark.circle")
                                .foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent("Santé") {
                        if tracker.healthAuthorized {
                            Label("Autorisée", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Text("À vérifier")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("À propos") {
                    LabeledContent("Build") {
                        Text(BuildInfo.gitSHA)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Text(
                        "Les anciennes valeurs de profils sont conservées uniquement pour compatibilité avec les installations précédentes ; elles ne pilotent plus la détection runtime."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
