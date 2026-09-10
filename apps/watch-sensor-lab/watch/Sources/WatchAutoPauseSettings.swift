import SwiftUI

enum WatchAutoPauseSettings {
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

    static func isEnabled(for activity: ActivityKind, defaults: UserDefaults = .standard) -> Bool {
        bool(defaults, key: enabledKey(for: activity), fallback: true)
    }

    static func pauseDwell(for activity: ActivityKind, defaults: UserDefaults = .standard) -> TimeInterval {
        value(defaults, key: pauseKey(for: activity), fallback: defaultPauseDwell(for: activity))
    }

    static func resumeDwell(for activity: ActivityKind, defaults: UserDefaults = .standard) -> TimeInterval {
        value(defaults, key: resumeKey(for: activity), fallback: defaultResumeDwell(for: activity))
    }

    private static func enabledKey(for activity: ActivityKind) -> String {
        switch activity {
        case .hiking: return hikeEnabledKey
        case .running, .trackAndField: return runEnabledKey
        case .cycling, .handCycling: return cycleEnabledKey
        default: return walkEnabledKey
        }
    }

    private static func pauseKey(for activity: ActivityKind) -> String {
        switch activity {
        case .hiking: return hikePauseDwellKey
        case .running, .trackAndField: return runPauseDwellKey
        case .cycling, .handCycling: return cyclePauseDwellKey
        default: return walkPauseDwellKey
        }
    }

    private static func resumeKey(for activity: ActivityKind) -> String {
        switch activity {
        case .hiking: return hikeResumeDwellKey
        case .running, .trackAndField: return runResumeDwellKey
        case .cycling, .handCycling: return cycleResumeDwellKey
        default: return walkResumeDwellKey
        }
    }

    private static func defaultPauseDwell(for activity: ActivityKind) -> Double {
        switch activity {
        case .cycling, .handCycling: return 7
        case .running, .trackAndField: return 9
        case .hiking: return 14
        default: return 11
        }
    }

    private static func defaultResumeDwell(for activity: ActivityKind) -> Double {
        switch activity {
        case .cycling, .handCycling, .running, .trackAndField: return 3
        case .hiking: return 5
        default: return 4
        }
    }

    private static func bool(_ defaults: UserDefaults, key: String, fallback: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return defaults.bool(forKey: key)
    }

    private static func value(_ defaults: UserDefaults, key: String, fallback: Double) -> Double {
        guard defaults.object(forKey: key) != nil else { return fallback }
        return max(1, defaults.double(forKey: key))
    }
}

struct WatchAutoPauseSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(WatchAutoPauseSettings.walkEnabledKey) private var walkEnabled = true
    @AppStorage(WatchAutoPauseSettings.hikeEnabledKey) private var hikeEnabled = true
    @AppStorage(WatchAutoPauseSettings.runEnabledKey) private var runEnabled = true
    @AppStorage(WatchAutoPauseSettings.cycleEnabledKey) private var cycleEnabled = true

    @AppStorage(WatchAutoPauseSettings.walkPauseDwellKey) private var walkPauseDwell = 11.0
    @AppStorage(WatchAutoPauseSettings.hikePauseDwellKey) private var hikePauseDwell = 14.0
    @AppStorage(WatchAutoPauseSettings.runPauseDwellKey) private var runPauseDwell = 9.0
    @AppStorage(WatchAutoPauseSettings.cyclePauseDwellKey) private var cyclePauseDwell = 7.0

    var body: some View {
        NavigationStack {
            List {
                Text("L’interrupteur Pause auto reste le maître. Ici tu peux désactiver un sport ou ajuster le temps d’arrêt requis avant la pause.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                profile("Marche", symbol: "figure.walk", enabled: $walkEnabled, dwell: $walkPauseDwell, range: 7...20)
                profile("Randonnée", symbol: "figure.hiking", enabled: $hikeEnabled, dwell: $hikePauseDwell, range: 9...25)
                profile("Course", symbol: "figure.run", enabled: $runEnabled, dwell: $runPauseDwell, range: 5...16)
                profile("Vélo", symbol: "bicycle", enabled: $cycleEnabled, dwell: $cyclePauseDwell, range: 4...14)
            }
            .navigationTitle("Pause auto")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func profile(
        _ title: String,
        symbol: String,
        enabled: Binding<Bool>,
        dwell: Binding<Double>,
        range: ClosedRange<Double>
    ) -> some View {
        Section {
            Toggle(isOn: enabled) {
                Label(title, systemImage: symbol)
            }
            if enabled.wrappedValue {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Pause après")
                        Spacer()
                        Text("\(Int(dwell.wrappedValue.rounded())) s")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: dwell, in: range, step: 1)
                }
                .font(.caption)
            }
        }
    }
}
