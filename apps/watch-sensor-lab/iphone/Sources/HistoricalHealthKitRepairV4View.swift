import Foundation
import SwiftUI

struct HistoricalHealthKitRepairV4View: View {
    @ObservedObject private var coordinator = HistoricalHealthKitRepairV4Coordinator.shared
    @State private var summaries: [TrackerSummary] = []
    private let store = NativeSessionStore()

    var body: some View {
        NavigationStack {
            Group {
                if summaries.isEmpty {
                    ContentUnavailableView(
                        "Aucune séance Tracker",
                        systemImage: "checkmark.circle.fill"
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 7) {
                                Label("Récupération Santé v4 · route segmentée", systemImage: "point.3.connected.trianglepath.dotted")
                                    .font(.headline.weight(.bold))
                                Text(
                                    "Dernier candidat : conserve la reconstruction riche, coupe seulement les raccords GPS impossibles, écrit distance/énergie sur les intervalles actifs et relie l’effort au workout."
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))

                            ForEach(summaries) { summary in
                                HistoricalRepairV4Card(summary: summary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Récupération")
            .onAppear {
                summaries = store.listSummaries().sorted { $0.startedAt > $1.startedAt }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct HistoricalRepairV4Card: View {
    @ObservedObject private var coordinator = HistoricalHealthKitRepairV4Coordinator.shared
    let summary: TrackerSummary

    @State private var selection: ActivityKind?
    @State private var perceivedEffort: Int?
    @State private var confirmCleanup = false
    @State private var confirmRepair = false

    private var audit: HistoricalHealthKitRepairV4Coordinator.Audit? {
        coordinator.auditBySession[summary.sessionID]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ActivityKind(rawValue: summary.activity)?.label ?? summary.activity)
                        .font(.headline.weight(.bold))
                    Text(summary.startedAt, format: .dateTime.day().month().year().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(summary.sessionID)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if coordinator.internallyVerifiedSessions.contains(summary.sessionID) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(.orange)
                }
            }

            HStack(spacing: 12) {
                metric(v4Distance(summary.distanceMeters), "Résumé")
                metric(audit.map { "\($0.watchRawPoints)" } ?? "—", "GPS Watch")
                metric(audit.map { "\($0.phoneRawPoints)" } ?? "—", "GPS iPhone")
            }

            if let audit {
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        "Route rendue : \(audit.chosenSource ?? "aucune") · \(audit.chosenPoints) points · \(v4Distance(audit.selectedGeometryMeters))"
                    )
                    Text(
                        String(
                            format: "Géométrie source W %.2f km · iPhone %.2f km",
                            audit.watchGeometryMeters / 1000,
                            audit.phoneGeometryMeters / 1000
                        )
                    )
                    if let value = audit.watchRawDistanceMeters {
                        Text(String(format: "Compteur raw Watch %.2f km", value / 1000))
                    }
                    if let value = audit.phoneRawDistanceMeters {
                        Text(String(format: "Compteur raw iPhone %.2f km", value / 1000))
                    }
                    Text("Référence distance : \(audit.distanceReferenceSource ?? "aucune")")
                    Text(
                        "Gaps actifs >3s : \(audit.activeGapsOver3Seconds) · max \(String(format: "%.1f", audit.maxActiveGapSeconds))s"
                    )
                    Text("Restaurations HealthKit : \(audit.generatedWorkoutCount)")
                    if let rawType = audit.generatedWorkoutActivityTypeRawValue {
                        Text("Type HK restauration : \(rawType) · cible \(audit.generatedTargetActivity ?? "inconnue")")
                    }
                    if let brand = audit.generatedWorkoutBrandName {
                        Text("Brand HK restauration : \(brand)")
                    }
                    if let score = audit.generatedEffortScore {
                        Text(String(format: "Effort Apple relié : %.0f / 10 (%d sample)", score, audit.generatedEffortSampleCount))
                    } else if audit.generatedWorkoutCount > 0 {
                        Text("Effort Apple relié : absent (\(audit.generatedEffortSampleCount) sample)")
                    }
                    if let saved = audit.savedPerceivedEffort {
                        Text("Effort choisi mémorisé : \(saved) / 10")
                    }
                    if audit.distanceConflict {
                        Text("DISTANCE SUMMARY/RAW NON CONFIRMÉE · écriture bloquée")
                            .foregroundStyle(.red)
                    }
                    if audit.severeRouteCounterConflict {
                        Text("ROUTE/COMPTEUR INCOHÉRENTS · détour majeur · écriture bloquée")
                            .foregroundStyle(.red)
                    }
                    if audit.routeGeometryConflict {
                        Text("QUALITÉ ROUTE · géométrie rendue ≠ distance Tracker · diagnostic visible")
                            .foregroundStyle(.yellow)
                    }
                    if audit.routeContinuityConflict {
                        Text("QUALITÉ ROUTE · trou GPS réel conservé · diagnostic non bloquant")
                            .foregroundStyle(.yellow)
                    }
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }

            Button {
                coordinator.inspect(sessionID: summary.sessionID)
            } label: {
                Label("Actualiser le diagnostic", systemImage: "waveform.path.ecg.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(coordinator.activeSessionID != nil)

            if let audit, audit.generatedWorkoutCount > 0 {
                Button(role: .destructive) {
                    confirmCleanup = true
                } label: {
                    Label(
                        "Nettoyer \(audit.generatedWorkoutCount) restauration(s) de test",
                        systemImage: "trash"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(coordinator.activeSessionID != nil)
            }

            Picker("Sport réel", selection: $selection) {
                Text("Choisir…").tag(Optional<ActivityKind>.none)
                ForEach(ActivityKind.allCases.filter { !$0.isAutomatic }) { activity in
                    Text(activity.label).tag(Optional(activity))
                }
            }
            .pickerStyle(.menu)

            Picker("Effort ressenti Apple", selection: $perceivedEffort) {
                Text("Non renseigné").tag(Optional<Int>.none)
                ForEach(1...10, id: \.self) { value in
                    Text("\(value) / 10").tag(Optional(value))
                }
            }
            .pickerStyle(.menu)
            .onChange(of: perceivedEffort) { _, value in
                HistoricalHealthKitFullFidelity.setSavedPerceivedEffort(
                    value,
                    sessionID: summary.sessionID
                )
            }

            Button {
                confirmRepair = true
            } label: {
                Label(
                    "Reconstruire proprement dans Santé",
                    systemImage: "heart.circle.fill"
                )
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(
                selection == nil
                    || coordinator.activeSessionID != nil
                    || audit?.canReconstruct != true
            )

            if let status = coordinator.statusBySession[summary.sessionID] {
                Text(status)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(
                        status.contains("échoué")
                            || status.contains("bloquée")
                            || status.contains("aucune écriture")
                            ? .red
                            : .secondary
                    )
            }
        }
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 20))
        .onAppear {
            if perceivedEffort == nil {
                perceivedEffort = HistoricalHealthKitFullFidelity.savedPerceivedEffort(
                    sessionID: summary.sessionID
                )
            }
            if audit == nil { coordinator.inspect(sessionID: summary.sessionID) }
        }
        .confirmationDialog(
            "Supprimer uniquement les restaurations Tracker de test de cette session ?",
            isPresented: $confirmCleanup,
            titleVisibility: .visible
        ) {
            Button("Nettoyer les restaurations de test", role: .destructive) {
                coordinator.cleanupGeneratedRestorations(sessionID: summary.sessionID)
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(
                "Le filtre exige raw_restoration=true + le session ID exact. Les raw Tracker et les workouts normaux restent intacts."
            )
        }
        .confirmationDialog(
            "Créer UNE nouvelle restauration v4 segmentée ?",
            isPresented: $confirmRepair,
            titleVisibility: .visible
        ) {
            if let selection {
                Button("Reconstruire en \(selection.label)") {
                    coordinator.repair(
                        sessionID: summary.sessionID,
                        targetActivity: selection,
                        perceivedEffort: perceivedEffort
                    )
                }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(
                "Distance/énergie sont conservées depuis les totaux Tracker. Les raccords GPS impossibles deviennent des frontières de route ; aucun point n’est inventé."
            )
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func v4Distance(_ meters: Double) -> String {
    meters >= 1000
        ? String(format: "%.2f km", meters / 1000)
        : String(format: "%.0f m", meters)
}
