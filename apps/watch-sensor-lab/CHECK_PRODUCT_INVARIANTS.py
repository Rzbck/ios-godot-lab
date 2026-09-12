#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(__file__).resolve().parent


def read(relative: str) -> str:
    return (root / relative).read_text(encoding="utf-8")


errors = []


def require(text: str, token: str, label: str):
    if token not in text:
        errors.append(f"{label}: token absent: {token}")


def forbid(text: str, token: str, label: str):
    if token in text:
        errors.append(f"{label}: token interdit encore présent: {token}")


iphone_root = read("iphone/Sources/TrackerApp.swift")
iphone_history = read("iphone/Sources/HealthWorkoutHistory.swift")
iphone_review = read("iphone/Sources/SessionReviewTimeline.swift")
iphone_repair = read("iphone/Sources/HistoricalHealthKitRepair.swift")
restore_packet = read("iphone/Sources/TrackerHealthRestorePacket.swift")
iphone_reliable = read("iphone/Sources/WatchReliableRecovery.swift")

watch_root = read("watch/Sources/WatchSensorLabApp.swift")
watch_history = read("watch/Sources/WatchRecentHistory.swift")
watch_restore = read("watch/Sources/WatchRestoreWorkflow.swift")
watch_model = read("watch/Sources/SensorModel.swift")

# ---------------------------------------------------------------------------
# A. Une seule surface active peut MUTER l'historique HealthKit : iPhone.
# ---------------------------------------------------------------------------
require(
    iphone_root,
    "HistoricalHealthKitRepairView()",
    "Route réparation historique iPhone montée",
)
require(
    iphone_root,
    'Label("Récupération"',
    "Onglet Récupération iPhone visible",
)
require(
    iphone_repair,
    "HistoricalHealthKitRepairCoordinator.shared",
    "Coordinateur unique historique iPhone",
)
require(
    iphone_repair,
    'Label("Reconstruire dans Santé"',
    "Action de reconstruction iPhone visible",
)

# L'ancien panneau de validation peut rester visible comme information, mais il
# ne doit plus déclencher le backend Watch historique.
require(
    iphone_review,
    "Ce panneau ne modifie plus HealthKit",
    "Panneau legacy rendu lecture seule",
)
forbid(
    iphone_review,
    "workflowCorrectHistoricalActivity(",
    "Ancienne correction iPhone active",
)

# La Watch reste autoritaire pour le LIVE seulement. Les surfaces historiques
# Watch doivent être informatives et ne plus envoyer de mutation HealthKit.
require(
    watch_root,
    "WatchRestoreEntryPage().tag(4)",
    "Page récupération Watch montée",
)
require(
    watch_restore,
    "Réparation historique sur iPhone",
    "Watch redirige la réparation vers iPhone",
)
forbid(
    watch_restore,
    "workflowRestoreHistoricalActivity(",
    "Ancienne restauration Watch active",
)
forbid(
    watch_restore,
    "requestHistoricalRestore(",
    "Ancienne demande raw Watch active",
)
forbid(
    watch_history,
    "workflowCorrectHistoricalActivity(",
    "Ancienne correction historique Watch active",
)
forbid(
    watch_history,
    '"Corriger le sport"',
    "Bouton correction historique Watch actif",
)

# ---------------------------------------------------------------------------
# B. L'écriture historique doit utiliser HKWorkoutBuilder SUR IPHONE.
#    Aucun transfert vers la Watch ne fait partie du nouveau chemin.
# ---------------------------------------------------------------------------
require(
    iphone_repair,
    "HKWorkoutBuilder(",
    "Builder historique iPhone",
)
require(
    iphone_repair,
    "HKWorkoutRouteBuilder",
    "Route builder historique iPhone",
)
require(
    iphone_repair,
    "finishWorkout",
    "Finalisation workout historique iPhone",
)
forbid(
    iphone_repair,
    "WCSession",
    "Le nouveau chemin historique ne doit pas dépendre de WatchConnectivity",
)
forbid(
    iphone_repair,
    "transferFile(",
    "Le nouveau chemin historique ne doit pas transférer les raw à la Watch",
)

# ---------------------------------------------------------------------------
# C. Autorisations d'ÉCRITURE explicites avant toute reconstruction.
# ---------------------------------------------------------------------------
for token, label in [
    ("HKObjectType.workoutType()", "Autorisation workout"),
    ("HKSeriesType.workoutRoute()", "Autorisation route"),
    (".heartRate", "Autorisation fréquence cardiaque"),
    (".activeEnergyBurned", "Autorisation énergie"),
    (".distanceCycling", "Autorisation distance vélo"),
    (".distanceWalkingRunning", "Autorisation distance marche/course"),
    (".distanceSwimming", "Autorisation distance natation"),
    ("authorizationStatus(for:", "Contrôle statut d'écriture"),
    (".sharingAuthorized", "Écriture Santé explicitement autorisée"),
]:
    require(iphone_repair, token, label)

# ---------------------------------------------------------------------------
# D. Raw Tracker reste la source de reconstruction.
# ---------------------------------------------------------------------------
for token, label in [
    ('"watch_location"', "GPS Watch brut"),
    ('"heart_rate"', "Fréquence cardiaque Watch brute"),
    ('"manual_pause"', "Pauses Watch explicites"),
    ("reconstructedActive", "Préflight durée active"),
]:
    require(restore_packet, token, label)

require(
    iphone_repair,
    "packetBuilder.makeTransferFile(",
    "Réutilisation du préflight raw éprouvé",
)

# ---------------------------------------------------------------------------
# E. Transaction : créer -> relire durablement -> seulement ensuite nettoyer
#    les ANCIENNES RESTAURATIONS GÉNÉRÉES. Jamais un workout normal.
# ---------------------------------------------------------------------------
repair_marker = "let created = try await createHistoricalWorkout("
verify_marker = "try await verifyDurably("
delete_marker = "try await deleteStaleGeneratedObjects("

create_pos = iphone_repair.find(repair_marker)
verify_pos = iphone_repair.find(verify_marker, create_pos + 1 if create_pos >= 0 else 0)
delete_pos = iphone_repair.find(delete_marker, verify_pos + 1 if verify_pos >= 0 else 0)

if min(create_pos, verify_pos, delete_pos) < 0:
    errors.append("Transaction iPhone incomplète (create/verify/delete)")
elif not (create_pos < verify_pos < delete_pos):
    errors.append("Ordre transactionnel invalide : nettoyage avant vérification")

require(
    iphone_repair,
    "let nonRestoreSources = existing.filter",
    "Préservation des workouts Tracker normaux",
)
require(
    iphone_repair,
    "guard nonRestoreSources.isEmpty",
    "Blocage si workout normal existe",
)
require(
    iphone_repair,
    "staleWorkouts.allSatisfy",
    "Suppression limitée aux objets raw générés",
)
require(
    iphone_repair,
    "rawRestoreKey",
    "Traçabilité restauration raw",
)
require(
    iphone_repair,
    'generation = "ios_historical_v2"',
    "Génération iPhone identifiable",
)
require(
    iphone_repair,
    "rollback",
    "Rollback du workout nouvellement créé",
)

# Trois relectures espacées protègent contre un callback de création trop tôt.
require(
    iphone_repair,
    "[0, 1_200_000_000, 3_000_000_000]",
    "Relectures HealthKit différées",
)

# ---------------------------------------------------------------------------
# F. Pas de faux positif produit : une relecture API n'est pas encore une
#    validation Santé/Forme physique. L'ancien état replacement_verified ne
#    doit jamais être écrit par le nouveau coordinateur.
# ---------------------------------------------------------------------------
require(
    iphone_repair,
    "HealthKit écrit et relu sur iPhone · vérifie maintenant Santé puis Forme.",
    "Statut produit distingue relecture et validation physique",
)
forbid(
    iphone_repair,
    '"replacement_verified"',
    "Le nouveau chemin ne doit pas auto-promouvoir la vérité produit",
)
forbid(
    iphone_repair,
    "recentHistoryBridge.publish(",
    "Le nouveau chemin ne doit pas modifier l'historique local avant validation physique",
)

# ---------------------------------------------------------------------------
# G. Les événements Watch fiables du live restent inchangés.
# ---------------------------------------------------------------------------
require(
    iphone_reliable,
    "didReceiveUserInfo",
    "Réception fiable Watch",
)
require(
    iphone_reliable,
    "WatchReliableRecovery.ingest(userInfo)",
    "Journalisation fiable Watch",
)

# Le vieux backend peut encore exister pendant la migration, mais aucune UI
# active ne doit pouvoir l'atteindre. Il sera supprimé après validation physique
# du nouveau chemin iPhone.
require(
    watch_model,
    "HKLiveWorkoutBuilder",
    "Le live Watch reste sur HKLiveWorkoutBuilder",
)

if errors:
    print("TRACKER PRODUCT INVARIANTS: FAIL", file=sys.stderr)
    for error in errors:
        print(f" - {error}", file=sys.stderr)
    sys.exit(1)

print("TRACKER PRODUCT INVARIANTS: OK")
print(" - single active historical HealthKit mutation surface: iPhone")
print(" - Watch historical mutation UI disabled")
print(" - iPhone HKWorkoutBuilder + route reconstruction")
print(" - explicit write authorization checks")
print(" - create/verify-before-cleanup ordering")
print(" - normal Tracker workout deletion blocked")
print(" - no automatic replacement_verified promotion")
print(" - live Watch HKLiveWorkoutBuilder preserved")
