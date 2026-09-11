import SwiftUI

extension SensorModel {
    func workflowRestoreHistoricalActivity(
        sessionID: String,
        activity: ActivityKind
    ) {
        requestHistoricalRestore(
            sessionID: sessionID,
            activity: activity
        )
    }
}

struct WatchRestoreEntryPage: View {
    @ObservedObject private var history = WatchRecentHistoryStore.shared
    @State private var showRestore = false

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("RÉCUPÉRATION")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "arrow.clockwise.heart.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
            }

            Spacer(minLength: 0)

            Image(systemName: "externaldrive.badge.timemachine")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.orange)

            Text("Restaurer une séance Tracker absente de Santé")
                .font(.caption.weight(.bold))
                .multilineTextAlignment(.center)

            Text("La Watch refusera un doublon si le workout existe encore.")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer(minLength: 0)

            Button {
                showRestore = true
            } label: {
                Label("Choisir", systemImage: "rectangle.stack.fill")
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(history.activities.isEmpty)
        }
        .padding(.horizontal, 4)
        .sheet(isPresented: $showRestore) {
            WatchRestoreHistoryView()
        }
    }
}

private struct WatchRestoreHistoryView: View {
    @ObservedObject private var history = WatchRecentHistoryStore.shared

    var body: some View {
        Group {
            if history.activities.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("Aucune séance Tracker synchronisée")
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                }
            } else {
                TabView {
                    ForEach(history.activities) { activity in
                        WatchRestoreCandidatePage(activity: activity)
                    }
                }
                .tabViewStyle(.verticalPage)
            }
        }
        .navigationTitle("Restaurer")
    }
}

private struct WatchRestoreCandidatePage: View {
    @EnvironmentObject private var model: SensorModel

    let activity: WatchRecentActivityDigest

    @State private var selection: ActivityKind
    @State private var confirming = false

    init(activity: WatchRecentActivityDigest) {
        self.activity = activity
        _selection = State(
            initialValue: activity.activityKind ?? .other
        )
    }

    private var activities: [ActivityKind] {
        ActivityKind.allCases.filter { !$0.isAutomatic }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: activity.activityKind?.symbol ?? "figure.mixed.cardio")
                    .foregroundStyle(.orange)
                Text(activity.activityKind?.label ?? activity.activity)
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Text(activity.date, format: .dateTime.day().month().hour().minute())
                .font(.caption2)
                .foregroundStyle(.secondary)

            Picker("Sport", selection: $selection) {
                ForEach(activities) { kind in
                    Text(kind.label).tag(kind)
                }
            }

            Button {
                confirming = true
            } label: {
                Label(
                    "Restaurer depuis Tracker",
                    systemImage: "arrow.clockwise.heart.fill"
                )
                .font(.caption.weight(.bold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)

            if !model.sessionStatus.isEmpty {
                Text(model.sessionStatus)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 4)
        .confirmationDialog(
            "Restaurer cette séance ?",
            isPresented: $confirming,
            titleVisibility: .visible
        ) {
            Button("Restaurer en \(selection.label)") {
                model.workflowRestoreHistoricalActivity(
                    sessionID: activity.sessionID,
                    activity: selection
                )
            }

            Button("Annuler", role: .cancel) {}
        } message: {
            Text(
                "À utiliser seulement si cette séance Tracker est absente de Santé. Le backend refuse les doublons et ne supprime aucun workout existant."
            )
        }
    }
}
