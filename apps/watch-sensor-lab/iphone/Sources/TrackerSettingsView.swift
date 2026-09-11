import Foundation
import SwiftUI

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

    var pauseRange: ClosedRange<Double> {
        switch self {
        case .walking: return 7...20
        case .hiking: return 9...25
        case .running: return 5...16
        case .cycling: return 4...14
        }
    }

    var resumeRange: ClosedRange<Double> {
        switch self {
        case .walking: return 2...8
        case .hiking: return 3...10
        case .running, .cycling: return 2...7
        }
    }

    var defaultPreference: AutoPauseProfilePreference {
        switch self {
        case .walking: return .init(enabled: true, pauseDwell: 11, resumeDwell: 4)
        case .hiking: return .init(enabled: true, pauseDwell: 14, resumeDwell: 5)
        case .running: return .init(enabled: true, pauseDwell: 9, resumeDwell: 3)
        case .cycling: return .init(enabled: true, pauseDwell: 7, resumeDwell: 3)
        }
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
            return (profile, AutoPauseProfilePreference(enabled: enabled, pauseDwell: pause, resumeDwell: resume))
        })
    }

    static func isConfigured(_ profile: AutoPauseProfileKind, defaults: UserDefaults = .standard) -> Bool {
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
                } header: {
                    Text("Entraînement")
                } footer: {
                    Text("L’iPhone configure. La Watch reste l’autorité qui applique pause, reprise et état de séance.")
                }

                Section("Profils de pause automatique") {
                    ForEach(AutoPauseProfileKind.allCases) { profile in
                        NavigationLink {
                            AutoPauseProfileSettingsView(profile: profile)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: profile.symbol)
                                    .frame(width: 24)
                                    .foregroundStyle(.mint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.label)
                                    Text(profileSummary(profile))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if PhoneAutoPausePreferences.isConfigured(profile) {
                                    Image(systemName: "checkmark.icloud.fill")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
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
                    Text("Les réglages avancés qui existaient sur la Watch ne sont pas écrasés tant que tu ne modifies pas le profil correspondant sur l’iPhone. Après la première modification, l’iPhone devient la source de vérité de ce profil.")
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

    private func profileSummary(_ profile: AutoPauseProfileKind) -> String {
        let value = tracker.autoPauseProfiles[profile] ?? profile.defaultPreference
        if !value.enabled { return "Désactivée" }
        return "Pause \(Int(value.pauseDwell.rounded())) s · reprise \(Int(value.resumeDwell.rounded())) s"
    }
}

private struct AutoPauseProfileSettingsView: View {
    @EnvironmentObject private var tracker: TrackerModel
    let profile: AutoPauseProfileKind

    private var preference: AutoPauseProfilePreference {
        tracker.autoPauseProfiles[profile] ?? profile.defaultPreference
    }

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Activer pour \(profile.label.lowercased())",
                    isOn: Binding(
                        get: { preference.enabled },
                        set: { tracker.setAutoPauseProfile(profile, enabled: $0) }
                    )
                )
                .tint(.mint)
            }

            if preference.enabled {
                Section("Pause") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Pause après")
                            Spacer()
                            Text("\(Int(preference.pauseDwell.rounded())) s")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { preference.pauseDwell },
                                set: { tracker.setAutoPauseProfile(profile, pauseDwell: $0) }
                            ),
                            in: profile.pauseRange,
                            step: 1
                        )
                    }
                }

                Section("Reprise") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Reprise après")
                            Spacer()
                            Text("\(Int(preference.resumeDwell.rounded())) s")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { preference.resumeDwell },
                                set: { tracker.setAutoPauseProfile(profile, resumeDwell: $0) }
                            ),
                            in: profile.resumeRange,
                            step: 1
                        )
                    }
                }
            }

            Section {
                Text("La détection elle-même reste sport-aware sur la Watch. Ces durées règlent seulement combien de temps l’état doit rester stable avant pause ou reprise.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(profile.label)
        .navigationBarTitleDisplayMode(.inline)
    }
}
