#!/usr/bin/env python3
"""Build-time safety patch for the active iPhone HealthKit v4 repair flow.

A Tracker-managed normal workout may coexist temporarily with one generated v4
candidate. The candidate is created from Tracker raw evidence and verified while
the original remains untouched. Deleting the normal source is a separate,
explicit product action after the user has physically checked the candidate in
Apple Health/Fitness.

This patch is deterministic and idempotent because SESSION_SYNC_PATCH.py applies
it before CI invariants, while Xcode pre-build scripts may invoke it again.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
CORE = ROOT / "iphone/Sources/HistoricalHealthKitRepairV4.swift"
VIEW = ROOT / "iphone/Sources/HistoricalHealthKitRepairV4View.swift"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, got {count}")
    return text.replace(old, new, 1)


def require_all(text: str, values: list[str], label: str) -> None:
    missing = [value for value in values if value not in text]
    if missing:
        raise SystemExit(f"{label}: missing invariants: {missing}")


core = CORE.read_text(encoding="utf-8")
view = VIEW.read_text(encoding="utf-8")

# Idempotence for the second Xcode target/build invocation in the same checkout.
if "finalizeNormalSourceCorrection(" in core:
    require_all(
        core,
        [
            "finalizableSessions",
            "normalWorkoutCount <= 1",
            "source normale conservée",
            "source HealthKit normale déjà du type cible",
            "Relecture finale du candidat v4 avant suppression de la source",
            "Correction finalisée côté HealthKit",
        ],
        "historical correction core",
    )
    require_all(
        view,
        [
            "confirmFinalize",
            "Finaliser après validation Santé/Forme",
            "finalizeNormalSourceCorrection(sessionID: summary.sessionID)",
        ],
        "historical correction view",
    )
    print("HISTORICAL CORRECTION DISTANCE PATCH: already applied")
    raise SystemExit(0)

core = replace_once(
    core,
    '''        var canReconstruct: Bool {
            generatedWorkoutCount == 0
                && normalWorkoutCount == 0
                && chosenPoints >= 2
''',
    '''        var canReconstruct: Bool {
            generatedWorkoutCount == 0
                && normalWorkoutCount <= 1
                && chosenPoints >= 2
''',
    "allow one normal source in audit",
)

core = replace_once(
    core,
    '''    @Published private(set) var auditBySession: [String: Audit] = [:]
    @Published private(set) var internallyVerifiedSessions: Set<String> = []
''',
    '''    @Published private(set) var auditBySession: [String: Audit] = [:]
    @Published private(set) var internallyVerifiedSessions: Set<String> = []
    @Published private(set) var finalizableSessions: Set<String> = []
''',
    "finalizable state",
)

core = replace_once(
    core,
    '''                let generated = workouts.filter { isGenerated($0, sessionID: sessionID) }
                let normal = workouts.filter { !isGenerated($0, sessionID: sessionID) }
                let conflict = hasDistanceConflict(
''',
    '''                let generated = workouts.filter { isGenerated($0, sessionID: sessionID) }
                let normal = workouts.filter { !isGenerated($0, sessionID: sessionID) }
                if generated.count == 1 && normal.count == 1 {
                    finalizableSessions.insert(sessionID)
                } else {
                    finalizableSessions.remove(sessionID)
                }
                let conflict = hasDistanceConflict(
''',
    "inspect finalizable state",
)

core = replace_once(
    core,
    '''                if !normal.isEmpty {
                    statusBySession[sessionID] =
                        "Workout Tracker normal détecté · reconstruction historique bloquée."
                } else if !generated.isEmpty {
''',
    '''                if normal.count > 1 {
                    statusBySession[sessionID] =
                        "Plusieurs workouts Tracker normaux détectés · correction bloquée."
                } else if !generated.isEmpty {
''',
    "inspect normal source state",
)

core = replace_once(
    core,
    '''                    statusBySession[sessionID] =
                        "\\(generated.count) restauration(s) de test détectée(s) · \\(renderedText) · source \\(sourceBundle) · nettoyage requis avant tout nouvel essai."
''',
    '''                    statusBySession[sessionID] = normal.count == 1
                        ? "Candidat v4 relu · \\(renderedText) · source normale conservée · valide dans Santé/Forme avant finalisation."
                        : "Correction v4 seule · \\(renderedText) · source \\(sourceBundle) · relue côté HealthKit."
''',
    "inspect generated status",
)

core = replace_once(
    core,
    '''                let generated = workouts.filter { isGenerated($0, sessionID: sessionID) }
                let normal = workouts.filter { !isGenerated($0, sessionID: sessionID) }
                guard normal.isEmpty else {
                    throw V4Error.operation("workout Tracker normal présent ; nettoyage annulé")
                }
                guard !generated.isEmpty else {
''',
    '''                let generated = workouts.filter { isGenerated($0, sessionID: sessionID) }
                let normal = workouts.filter { !isGenerated($0, sessionID: sessionID) }
                guard normal.count <= 1 else {
                    throw V4Error.operation("plusieurs workouts Tracker normaux présents ; nettoyage annulé")
                }
                guard !generated.isEmpty else {
''',
    "cleanup preserves one normal source",
)

core = replace_once(
    core,
    '''                auditBySession.removeValue(forKey: sessionID)
                statusBySession[sessionID] =
                    "Nettoyage vérifié · zéro restauration de test restante · raw Tracker intacts."
''',
    '''                finalizableSessions.remove(sessionID)
                auditBySession.removeValue(forKey: sessionID)
                statusBySession[sessionID] = normal.isEmpty
                    ? "Nettoyage vérifié · zéro restauration de test restante · raw Tracker intacts."
                    : "Candidat v4 nettoyé · workout Tracker normal conservé · raw Tracker intacts."
''',
    "cleanup final state",
)

core = replace_once(
    core,
    '''                let generated = existing.filter { isGenerated($0, sessionID: sessionID) }
                let normal = existing.filter { !isGenerated($0, sessionID: sessionID) }
                guard normal.isEmpty else {
                    throw V4Error.operation("workout Tracker normal présent ; aucune écriture effectuée")
                }
                guard generated.isEmpty else {
''',
    '''                let generated = existing.filter { isGenerated($0, sessionID: sessionID) }
                let normal = existing.filter { !isGenerated($0, sessionID: sessionID) }
                guard normal.count <= 1 else {
                    throw V4Error.operation("plusieurs workouts Tracker normaux présents ; aucune écriture effectuée")
                }
                if let sourceWorkout = normal.first,
                   sourceWorkout.workoutActivityType == targetActivity.healthKitType {
                    throw V4Error.operation("source HealthKit normale déjà du type cible ; aucune reconstruction nécessaire")
                }
                guard generated.isEmpty else {
''',
    "repair accepts one normal source",
)

core = replace_once(
    core,
    '''                internallyVerifiedSessions.insert(sessionID)
                auditBySession.removeValue(forKey: sessionID)
                statusBySession[sessionID] =
                    "HealthKit v4 segmenté écrit et relu · une seule restauration · PAS encore validé dans Santé/Forme."
''',
    '''                internallyVerifiedSessions.insert(sessionID)
                if normal.count == 1 {
                    finalizableSessions.insert(sessionID)
                } else {
                    finalizableSessions.remove(sessionID)
                }
                auditBySession.removeValue(forKey: sessionID)
                statusBySession[sessionID] = normal.count == 1
                    ? "Candidat HealthKit v4 écrit et relu · source normale conservée · PAS encore validé dans Santé/Forme."
                    : "HealthKit v4 segmenté écrit et relu · une seule restauration · PAS encore validé dans Santé/Forme."
''',
    "repair verified candidate state",
)

finalizer = r'''

    /// Deletes the single normal Tracker source only after a generated v4 candidate
    /// has already been created and physically reviewed by the user in Health/Fitness.
    /// The candidate is reread both before and after source deletion.
    func finalizeNormalSourceCorrection(sessionID: String) {
        guard activeSessionID == nil else {
            statusBySession[sessionID] = "Une opération Santé est déjà en cours."
            return
        }
        guard finalizableSessions.contains(sessionID) else {
            statusBySession[sessionID] =
                "Aucun candidat v4 + source normale prêt à finaliser. Actualise le diagnostic."
            return
        }

        activeSessionID = sessionID
        statusBySession[sessionID] =
            "Relecture finale du candidat v4 avant suppression de la source…"

        Task {
            var sourceDeleted = false
            defer { activeSessionID = nil }

            do {
                let summary = try loadSummary(sessionID: sessionID)
                let existing = try await managedWorkouts(sessionID: sessionID, summary: summary)
                let generated = existing.filter { isGenerated($0, sessionID: sessionID) }
                let normal = existing.filter { !isGenerated($0, sessionID: sessionID) }

                guard generated.count == 1,
                      normal.count == 1,
                      let candidate = generated.first,
                      let sourceWorkout = normal.first else {
                    throw V4Error.operation(
                        "finalisation exige exactement un candidat v4 et une source normale"
                    )
                }

                guard let targetRaw = candidate.metadata?[correctionTargetKey] as? String,
                      let targetActivity = ActivityKind(rawValue: targetRaw),
                      !targetActivity.isAutomatic else {
                    throw V4Error.operation("activité cible du candidat v4 introuvable")
                }
                guard sourceWorkout.workoutActivityType != targetActivity.healthKitType else {
                    throw V4Error.operation("source HealthKit normale déjà du type cible")
                }
                guard let attemptID = candidate.metadata?[attemptKey] as? String,
                      !attemptID.isEmpty else {
                    throw V4Error.operation("identité de tentative du candidat v4 absente")
                }

                let payload = try makePayload(
                    sessionID: sessionID,
                    targetActivity: targetActivity
                )
                let raw = try loadRawRoutes(summary: summary)
                guard !hasDistanceConflict(
                    summaryMeters: summary.distanceMeters,
                    watchRawMeters: raw.watchRawDistanceMeters,
                    phoneRawMeters: raw.phoneRawDistanceMeters
                ) else {
                    throw V4Error.operation(
                        "distance Tracker/raw devenue incohérente ; source normale conservée"
                    )
                }

                let choice = chooseRoute(
                    raw: raw,
                    summaryDistanceMeters: summary.distanceMeters,
                    activity: targetActivity
                )
                guard let selectedRoute = choice.selected,
                      selectedRoute.points.count >= 2 else {
                    throw V4Error.operation("route GPS sûre absente avant finalisation")
                }
                let routeSegments = segmentRouteForHealthKit(
                    route: selectedRoute,
                    pauses: raw.pauses,
                    activity: targetActivity
                )
                guard !routeSegments.isEmpty else {
                    throw V4Error.operation("segments HealthKit absents avant finalisation")
                }
                guard !hasSevereRouteCounterConflict(
                    summaryMeters: summary.distanceMeters,
                    renderedGeometryMeters: segmentedGeometry(routeSegments)
                ) else {
                    throw V4Error.operation(
                        "route/compteur devenus incompatibles ; source normale conservée"
                    )
                }

                let candidateRoutes = try await routes(for: candidate)
                guard !candidateRoutes.isEmpty else {
                    throw V4Error.operation("routes du candidat v4 absentes")
                }
                let perceivedEffort = HistoricalHealthKitFullFidelity.savedPerceivedEffort(
                    sessionID: sessionID
                )

                try await verifyDurably(
                    payload: payload,
                    summary: summary,
                    activity: targetActivity,
                    route: selectedRoute,
                    routeSegments: routeSegments,
                    workoutUUID: candidate.uuid,
                    routeUUIDs: Set(candidateRoutes.map(\.uuid)),
                    attemptID: attemptID,
                    perceivedEffort: perceivedEffort
                )

                try await requestCleanupAuthorization()
                let sourceRoutes = try await routes(for: sourceWorkout)

                statusBySession[sessionID] =
                    "Candidat v4 relu · suppression ciblée du workout source normal…"
                try await delete([sourceWorkout])
                sourceDeleted = true

                // Same policy as the previously validated normal correction path:
                // source routes are cleaned only after the workout source is gone.
                // Failure here does not endanger the already verified candidate.
                if !sourceRoutes.isEmpty {
                    try? await delete(sourceRoutes)
                }

                var postDelete: [HKWorkout] = []
                for attempt in 0..<4 {
                    postDelete = try await managedWorkouts(
                        sessionID: sessionID,
                        summary: summary
                    )
                    let durableGenerated = postDelete.filter {
                        isGenerated($0, sessionID: sessionID)
                    }
                    let durableNormal = postDelete.filter {
                        !isGenerated($0, sessionID: sessionID)
                    }
                    if durableGenerated.count == 1,
                       durableGenerated.first?.uuid == candidate.uuid,
                       durableNormal.isEmpty {
                        break
                    }
                    if attempt < 3 {
                        try await Task.sleep(nanoseconds: 350_000_000)
                    }
                }

                let durableGenerated = postDelete.filter {
                    isGenerated($0, sessionID: sessionID)
                }
                let durableNormal = postDelete.filter {
                    !isGenerated($0, sessionID: sessionID)
                }
                guard durableGenerated.count == 1,
                      let durableCandidate = durableGenerated.first,
                      durableCandidate.uuid == candidate.uuid,
                      durableNormal.isEmpty else {
                    throw V4Error.operation(
                        "état HealthKit inattendu après suppression de la source"
                    )
                }

                let durableRoutes = try await routes(for: durableCandidate)
                try await verifyDurably(
                    payload: payload,
                    summary: summary,
                    activity: targetActivity,
                    route: selectedRoute,
                    routeSegments: routeSegments,
                    workoutUUID: durableCandidate.uuid,
                    routeUUIDs: Set(durableRoutes.map(\.uuid)),
                    attemptID: attemptID,
                    perceivedEffort: perceivedEffort
                )

                finalizableSessions.remove(sessionID)
                internallyVerifiedSessions.insert(sessionID)
                auditBySession.removeValue(forKey: sessionID)
                statusBySession[sessionID] =
                    "Correction finalisée côté HealthKit · source normale supprimée · candidat v4 relu après suppression · vérifie une dernière fois dans Santé/Forme."
            } catch {
                if sourceDeleted {
                    finalizableSessions.remove(sessionID)
                    statusBySession[sessionID] =
                        "Finalisation incomplète après suppression de la source · \\(error.localizedDescription) · n’effectue aucun nettoyage avant diagnostic."
                } else {
                    statusBySession[sessionID] =
                        "Finalisation annulée · source normale conservée · \\(error.localizedDescription)"
                }
            }
        }
    }
'''

last_brace = core.rfind("\n}")
if last_brace < 0:
    raise SystemExit("historical correction core: final class brace not found")
core = core[:last_brace] + finalizer + core[last_brace:]

view = replace_once(
    view,
    '''    @State private var confirmCleanup = false
    @State private var confirmRepair = false
''',
    '''    @State private var confirmCleanup = false
    @State private var confirmRepair = false
    @State private var confirmFinalize = false
''',
    "finalize dialog state",
)

view = replace_once(
    view,
    '''                selection == nil
                    || coordinator.activeSessionID != nil
                    || audit?.canReconstruct != true
''',
    '''                selection == nil
                    || coordinator.activeSessionID != nil
                    || audit?.canReconstruct != true
                    || coordinator.finalizableSessions.contains(summary.sessionID)
''',
    "repair disabled while candidate awaits validation",
)

view = replace_once(
    view,
    '''            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(
                selection == nil
                    || coordinator.activeSessionID != nil
                    || audit?.canReconstruct != true
                    || coordinator.finalizableSessions.contains(summary.sessionID)
            )

            if let status = coordinator.statusBySession[summary.sessionID] {
''',
    '''            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(
                selection == nil
                    || coordinator.activeSessionID != nil
                    || audit?.canReconstruct != true
                    || coordinator.finalizableSessions.contains(summary.sessionID)
            )

            if coordinator.finalizableSessions.contains(summary.sessionID) {
                Button(role: .destructive) {
                    confirmFinalize = true
                } label: {
                    Label(
                        "Finaliser après validation Santé/Forme",
                        systemImage: "checkmark.shield.fill"
                    )
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(coordinator.activeSessionID != nil)

                Text(
                    "À utiliser uniquement après avoir vérifié physiquement le candidat Vélo dans Santé/Forme. Cette étape supprime alors le workout source normal."
                )
                .font(.caption2)
                .foregroundStyle(.orange)
            }

            if let status = coordinator.statusBySession[summary.sessionID] {
''',
    "finalize product button",
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
            "Tu as vérifié le candidat corrigé dans Santé/Forme ?",
            isPresented: $confirmFinalize,
            titleVisibility: .visible
        ) {
            Button("Finaliser et supprimer la source normale", role: .destructive) {
                coordinator.finalizeNormalSourceCorrection(sessionID: summary.sessionID)
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text(
                "Le candidat v4 sera relu une dernière fois avant suppression. La source normale n’est supprimée que si le candidat est toujours cohérent."
            )
        }
    }
''',
    "finalize confirmation dialog",
)

require_all(
    core,
    [
        "finalizableSessions",
        "normalWorkoutCount <= 1",
        "finalizeNormalSourceCorrection(",
        "source normale conservée",
        "source HealthKit normale déjà du type cible",
        "verifyDurably(",
        "requestCleanupAuthorization()",
        "try await delete([sourceWorkout])",
        "Correction finalisée côté HealthKit",
    ],
    "final core invariants",
)
require_all(
    view,
    [
        "confirmFinalize",
        "Finaliser après validation Santé/Forme",
        "finalizeNormalSourceCorrection(sessionID: summary.sessionID)",
    ],
    "final view invariants",
)

CORE.write_text(core, encoding="utf-8")
VIEW.write_text(view, encoding="utf-8")
print("HISTORICAL CORRECTION DISTANCE PATCH: OK")
