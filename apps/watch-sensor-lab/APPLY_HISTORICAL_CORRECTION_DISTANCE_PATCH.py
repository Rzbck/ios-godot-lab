#!/usr/bin/env python3
"""Build-time safety patch for the active iPhone HealthKit v4 repair flow.

A Tracker-managed normal workout may coexist temporarily with one generated v4
candidate. The candidate is created from Tracker raw evidence and verified while
the normal source remains intact. Only an explicit finalization action may delete
the old normal workout, and it re-verifies the candidate immediately before and
after that deletion.

The patch is deterministic and idempotent because both iPhone and Watch project
pre-build phases may invoke it in one checkout.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
COORD = ROOT / "iphone/Sources/HistoricalHealthKitRepairV4.swift"
VIEW = ROOT / "iphone/Sources/HistoricalHealthKitRepairV4View.swift"
COORD_MARKER = "func finalizeNormalSourceCorrection("
VIEW_MARKER = "Finaliser après validation Santé/Forme"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, got {count}")
    return text.replace(old, new, 1)


coord = COORD.read_text(encoding="utf-8")
view = VIEW.read_text(encoding="utf-8")

if COORD_MARKER not in coord:
    coord = replace_once(
        coord,
        '''        var canReconstruct: Bool {
            generatedWorkoutCount == 0
                && normalWorkoutCount == 0
                && chosenPoints >= 2
                && !distanceConflict
                && !severeRouteCounterConflict
        }
''',
        '''        var canReconstruct: Bool {
            generatedWorkoutCount == 0
                && normalWorkoutCount <= 1
                && chosenPoints >= 2
                && !distanceConflict
                && !severeRouteCounterConflict
        }
''',
        "allow one normal source",
    )

    coord = replace_once(
        coord,
        '''                if !normal.isEmpty {
                    statusBySession[sessionID] =
                        "Workout Tracker normal détecté · reconstruction historique bloquée."
                } else if !generated.isEmpty {
                    let sourceBundle = generated.first?.sourceRevision.source.bundleIdentifier ?? "inconnu"
                    statusBySession[sessionID] =
                        "\\(generated.count) restauration(s) v4 présente(s) · source \\(sourceBundle). Nettoyer avant toute nouvelle écriture."
                } else if conflict {
''',
        '''                if normal.count > 1 {
                    statusBySession[sessionID] =
                        "Plusieurs workouts Tracker normaux détectés · aucune écriture autorisée."
                } else if !generated.isEmpty {
                    let sourceBundle = generated.first?.sourceRevision.source.bundleIdentifier ?? "inconnu"
                    if normal.count == 1 {
                        statusBySession[sessionID] =
                            "Candidat v4 + workout source présents · source conservée. Vérifier Santé/Forme puis finaliser explicitement."
                    } else {
                        statusBySession[sessionID] =
                            "\\(generated.count) restauration(s) v4 présente(s) · source \\(sourceBundle). Nettoyer avant toute nouvelle écriture."
                    }
                } else if conflict {
''',
        "inspect normal source state",
    )

    coord = replace_once(
        coord,
        '''                let generated = workouts.filter { isGenerated($0, sessionID: sessionID) }
                let normal = workouts.filter { !isGenerated($0, sessionID: sessionID) }
                guard normal.isEmpty else {
                    throw V4Error.operation("workout Tracker normal présent ; nettoyage annulé")
                }
                guard !generated.isEmpty else {
''',
        '''                let generated = workouts.filter { isGenerated($0, sessionID: sessionID) }
                guard !generated.isEmpty else {
''',
        "cleanup preserves normal source",
    )

    coord = replace_once(
        coord,
        '''                let generated = existing.filter { isGenerated($0, sessionID: sessionID) }
                let normal = existing.filter { !isGenerated($0, sessionID: sessionID) }
                guard normal.isEmpty else {
                    throw V4Error.operation("workout Tracker normal présent ; aucune écriture effectuée")
                }
                guard generated.isEmpty else {
                    throw V4Error.operation("restauration v4 déjà présente ; nettoyer avant de recommencer")
                }
''',
        '''                let generated = existing.filter { isGenerated($0, sessionID: sessionID) }
                let normal = existing.filter { !isGenerated($0, sessionID: sessionID) }
                guard normal.count <= 1 else {
                    throw V4Error.operation("plusieurs workouts Tracker normaux présents ; aucune écriture effectuée")
                }
                if let sourceWorkout = normal.first,
                   sourceWorkout.workoutActivityType == targetActivity.healthKitType {
                    throw V4Error.operation("le workout Tracker normal est déjà du sport demandé")
                }
                guard generated.isEmpty else {
                    throw V4Error.operation("restauration v4 déjà présente ; nettoyer avant de recommencer")
                }
                let sourceRetained = normal.count == 1
''',
        "repair allows one normal source",
    )

    coord = replace_once(
        coord,
        '''                internallyVerifiedSessions.insert(sessionID)
                auditBySession.removeValue(forKey: sessionID)
                statusBySession[sessionID] =
                    "HealthKit v4 segmenté écrit et relu · une seule restauration · PAS encore validé dans Santé/Forme."
''',
        '''                internallyVerifiedSessions.insert(sessionID)
                auditBySession.removeValue(forKey: sessionID)
                statusBySession[sessionID] =
                    sourceRetained
                        ? "Candidat HealthKit v4 écrit et relu · workout source conservé · vérifier Santé/Forme avant finalisation."
                        : "HealthKit v4 segmenté écrit et relu · une seule restauration · PAS encore validé dans Santé/Forme."
''',
        "candidate status",
    )

    finalizer = r'''

    func finalizeNormalSourceCorrection(sessionID: String) {
        guard activeSessionID == nil else { return }
        activeSessionID = sessionID
        statusBySession[sessionID] =
            "Relecture du candidat avant suppression de la source…"

        Task { @MainActor in
            defer { activeSessionID = nil }
            do {
                let summary = try loadSummary(sessionID: sessionID)
                let raw = try loadRawRoutes(sessionID: sessionID)
                guard !hasDistanceConflict(summary: summary, raw: raw) else {
                    throw V4Error.operation("distance summary/raw non confirmée ; source conservée")
                }

                let existing = try await managedWorkouts(
                    sessionID: sessionID,
                    summary: summary
                )
                let generated = existing.filter { isGenerated($0, sessionID: sessionID) }
                let normal = existing.filter { !isGenerated($0, sessionID: sessionID) }
                guard generated.count == 1, normal.count == 1 else {
                    throw V4Error.operation("finalisation exige exactement un candidat et un workout source")
                }

                let candidate = generated[0]
                let sourceWorkout = normal[0]
                guard
                    let targetRaw = candidate.metadata?[correctionTargetKey] as? String,
                    let targetActivity = ActivityKind(rawValue: targetRaw),
                    !targetActivity.isAutomatic,
                    candidate.workoutActivityType == targetActivity.healthKitType
                else {
                    throw V4Error.operation("sport cible du candidat invalide ; source conservée")
                }
                guard sourceWorkout.workoutActivityType != targetActivity.healthKitType else {
                    throw V4Error.operation("source déjà du sport cible ; suppression refusée")
                }

                let payload = try makePayload(
                    summary: summary,
                    targetActivity: targetActivity,
                    raw: raw
                )
                let choice = chooseRoute(
                    watch: raw.watch,
                    phone: raw.phone,
                    summary: summary,
                    activity: targetActivity
                )
                guard let selectedRoute = choice.selected,
                      selectedRoute.points.count >= 2 else {
                    throw V4Error.operation("route raw insuffisante pour revalider le candidat")
                }
                let routeSegments = segmentRouteForStorage(
                    selectedRoute,
                    summary: summary
                )
                guard !routeSegments.isEmpty else {
                    throw V4Error.operation("aucun segment de route durable ; source conservée")
                }
                guard !hasSevereRouteCounterConflict(
                    summary: summary,
                    route: selectedRoute,
                    watchRawDistanceMeters: raw.watch.rawDistanceMeters,
                    phoneRawDistanceMeters: raw.phone.rawDistanceMeters
                ) else {
                    throw V4Error.operation("route/compteur incohérents ; source conservée")
                }

                guard let attemptID = candidate.metadata?[attemptKey] as? String,
                      !attemptID.isEmpty else {
                    throw V4Error.operation("attempt_id du candidat absent ; source conservée")
                }
                let candidateRoutes = try await routes(for: candidate)
                let perceivedEffort = HistoricalHealthKitFullFidelity.savedPerceivedEffort(
                    sessionID: sessionID
                )

                try await requestCleanupAuthorization()
                try await verifyDurably(
                    payload: payload,
                    route: selectedRoute,
                    routeSegments: routeSegments,
                    workoutUUID: candidate.uuid,
                    routeUUIDs: Set(candidateRoutes.map(\.uuid)),
                    attemptID: attemptID,
                    perceivedEffort: perceivedEffort
                )

                let sourceRoutes = try await routes(for: sourceWorkout)
                try await delete([sourceWorkout as HKObject])
                if !sourceRoutes.isEmpty {
                    try? await delete(sourceRoutes.map { $0 as HKObject })
                }

                let afterDelete = try await managedWorkouts(
                    sessionID: sessionID,
                    summary: summary
                )
                let afterGenerated = afterDelete.filter { isGenerated($0, sessionID: sessionID) }
                let afterNormal = afterDelete.filter { !isGenerated($0, sessionID: sessionID) }
                guard afterNormal.isEmpty,
                      afterGenerated.count == 1,
                      afterGenerated[0].uuid == candidate.uuid else {
                    throw V4Error.operation("état HealthKit inattendu après suppression de la source")
                }

                let durableRoutes = try await routes(for: afterGenerated[0])
                try await verifyDurably(
                    payload: payload,
                    route: selectedRoute,
                    routeSegments: routeSegments,
                    workoutUUID: afterGenerated[0].uuid,
                    routeUUIDs: Set(durableRoutes.map(\.uuid)),
                    attemptID: attemptID,
                    perceivedEffort: perceivedEffort
                )

                internallyVerifiedSessions.insert(sessionID)
                auditBySession.removeValue(forKey: sessionID)
                statusBySession[sessionID] =
                    "Correction finalisée et relue · ancien workout supprimé · vérifier Santé/Forme."
            } catch {
                statusBySession[sessionID] =
                    "Finalisation échouée · \\(error.localizedDescription)"
            }
        }
    }
'''

    closing = "\n}\n"
    index = coord.rfind(closing)
    if index < 0:
        raise SystemExit("coordinator final class close not found")
    coord = coord[:index] + finalizer + coord[index:]

if VIEW_MARKER not in view:
    view = replace_once(
        view,
        '''    @State private var confirmCleanup = false
    @State private var confirmRepair = false
''',
        '''    @State private var confirmCleanup = false
    @State private var confirmRepair = false
    @State private var confirmFinalize = false
''',
        "view finalize state",
    )

    view = replace_once(
        view,
        '''            if let status = coordinator.statusBySession[summary.sessionID] {
''',
        '''            if let audit,
               audit.generatedWorkoutCount == 1,
               audit.normalWorkoutCount == 1,
               audit.generatedTargetActivity != nil {
                Button(role: .destructive) {
                    confirmFinalize = true
                } label: {
                    Label(
                        "Finaliser après validation Santé/Forme",
                        systemImage: "checkmark.shield.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(coordinator.activeSessionID != nil)
            }

            if let status = coordinator.statusBySession[summary.sessionID] {
''',
        "view finalize button",
    )

    view = replace_once(
        view,
        '''        } message: {
            Text(
                "Distance/énergie sont conservées depuis les totaux Tracker. Les raccords GPS impossibles deviennent des frontières de route ; aucun point n’est inventé."
            )
        }
    }
''',
        '''        } message: {
            Text(
                "Distance/énergie sont conservées depuis les totaux Tracker. Les raccords GPS impossibles deviennent des frontières de route ; aucun point n’est inventé."
            )
        }
        .confirmationDialog(
            "Finaliser la correction après vérification dans Santé/Forme ?",
            isPresented: $confirmFinalize,
            titleVisibility: .visible
        ) {
            Button("Supprimer uniquement l’ancien workout source", role: .destructive) {
                coordinator.finalizeNormalSourceCorrection(
                    sessionID: summary.sessionID
                )
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(
                "Le candidat v4 est relu une nouvelle fois avant suppression. Seul le workout Tracker normal de ce session ID est supprimé ; les raw Tracker et le candidat vérifié restent conservés."
            )
        }
    }
''',
        "view finalize dialog",
    )

for required in [
    "normalWorkoutCount <= 1",
    COORD_MARKER,
    "generated.count == 1, normal.count == 1",
    "verifyDurably(",
    "sourceWorkout as HKObject",
]:
    if required not in coord:
        raise SystemExit(f"iphone v4 correction invariant missing: {required}")

for required in [
    VIEW_MARKER,
    "confirmFinalize",
    "finalizeNormalSourceCorrection",
]:
    if required not in view:
        raise SystemExit(f"iphone v4 correction view invariant missing: {required}")

COORD.write_text(coord, encoding="utf-8")
VIEW.write_text(view, encoding="utf-8")
print("IPHONE V4 NORMAL-WORKOUT CORRECTION PATCH: OK")
