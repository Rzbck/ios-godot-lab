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
iphone_review = read("iphone/Sources/SessionReviewTimeline.swift")
iphone_repair = read("iphone/Sources/HistoricalHealthKitRepair.swift")
restore_packet = read("iphone/Sources/TrackerHealthRestorePacket.swift")
iphone_reliable = read("iphone/Sources/WatchReliableRecovery.swift")

watch_root = read("watch/Sources/WatchSensorLabApp.swift")
watch_history = read("watch/Sources/WatchRecentHistory.swift")
watch_restore = read("watch/Sources/WatchRestoreWorkflow.swift")
watch_model = read("watch/Sources/SensorModel.swift")

# ---------------------------------------------------------------------------
# A. Une seule SURFACE PRODUIT active peut muter l'historique HealthKit : iPhone.
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
    "Coordinateur historique iPhone",
)
require(
    iphone_repair,
    'Label(\n                    "Reconstruire dans Santé"',
    "Action de reconstruction iPhone visible",
)

# L'ancien panneau de validation devient strictement informatif.
require(
    iphone_review,
    "Ce panneau ne modifie plus HealthKit",
    "Panneau legacy rendu lecture seule",
)
forbid(
    iphone_review,
    "workflowCorrectHistoricalActivity(",
    "Ancienne correction iPhone active dans le panneau review",
)

# La Watch reste autoritaire pour le LIVE seulement.
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
    "Ancienne restauration Watch active dans l'UI",
)
forbid(
    watch_restore,
    "requestHistoricalRestore(",
    "Ancienne demande raw Watch active dans l'UI",
)
forbid(
    watch_history,
    "workflowCorrectHistoricalActivity(",
    "Ancienne correction historique Watch active dans l'historique",
)
forbid(
    watch_history,
    '"Corriger le sport"',
    "Bouton correction historique Watch actif",
)

# ---------------------------------------------------------------------------
# B. L'écriture historique v2 utilise HKWorkoutBuilder SUR IPHONE.
#    Aucun transfert vers la Watch ne fait partie du nouveau chemin.
# ---------------------------------------------------------------------------
for token, label in [
    ("HKWorkoutBuilder(", "Builder historique iPhone"),
    ("HKWorkoutRouteBuilder", "Route builder historique iPhone"),
    ("finishWorkout", "Finalisation workout historique iPhone"),
]:
    require(iphone_repair, token, label)

for token, label in [
    ("WCSession", "Le nouveau chemin ne doit pas dépendre de WatchConnectivity"),
    ("transferFile(", "Le nouveau chemin ne doit pas transférer les raw à la Watch"),
]:
    forbid(iphone_repair, token, label)

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
# D. Les raw Tracker restent l'unique source de reconstruction.
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
# E. Après l'incident, aucune ancienne donnée HealthKit n'est nettoyée sur la
#    seule base d'une relecture API. La v2 crée + relit; elle ne supprime qu'un
#    objet qu'ELLE vient de créer si sa propre transaction échoue.
# ---------------------------------------------------------------------------
create_marker = "let created = try await createHistoricalWorkout("
verify_marker = "try await verifyDurably("
create_pos = iphone_repair.find(create_marker)
verify_pos = iphone_repair.find(verify_marker, create_pos + 1 if create_pos >= 0 else 0)

if create_pos < 0 or verify_pos < 0:
    errors.append("Transaction iPhone incomplète (create/verify)")
elif create_pos >= verify_pos:
    errors.append("Ordre transactionnel invalide : vérification avant création")

require(
    iphone_repair,
    "let normalSources = existing.filter",
    "Détection des workouts Tracker normaux",
)
require(
    iphone_repair,
    "guard normalSources.isEmpty",
    "Blocage si workout normal existe",
)
forbid(
    iphone_repair,
    "deleteStaleGeneratedObjects(",
    "Nettoyage automatique d'anciennes restaurations avant validation physique",
)
require(
    iphone_repair,
    "Deliberately no cleanup here",
    "Garde-fou explicite contre nettoyage automatique",
)
require(
    iphone_repair,
    "var rollback: [HKObject] = []",
    "Rollback limité à la tentative v2",
)

# Un seul appel de suppression est autorisé dans ce fichier: le rollback des
# objets créés dans la tentative courante.
if iphone_repair.count("await delete(") != 1:
    errors.append(
        "La v2 doit avoir exactement un appel delete: rollback de la tentative courante"
    )

require(
    iphone_repair,
    'generation = "ios_historical_v2"',
    "Génération iPhone identifiable",
)
require(
    iphone_repair,
    "[0, 1_200_000_000, 3_000_000_000]",
    "Trois relectures HealthKit différées",
)

# ---------------------------------------------------------------------------
# F. Pas de faux positif produit : API relue != Santé/Forme validés.
# ---------------------------------------------------------------------------
require(
    iphone_repair,
    "PAS encore validé dans Santé/Forme.",
    "Statut distingue relecture interne et validation physique",
)
forbid(
    iphone_repair,
    '"replacement_verified"',
    "Le nouveau chemin ne doit pas auto-promouvoir la vérité produit",
)
forbid(
    iphone_repair,
    "recentHistoryBridge.publish(",
    "Le nouveau chemin ne doit pas réécrire l'historique local avant validation physique",
)

# ---------------------------------------------------------------------------
# G. Le live Watch reste intact.
# ---------------------------------------------------------------------------
require(
    iphone_reliable,
    "WatchReliableRecovery.ingest(userInfo)",
    "Journalisation fiable Watch",
)
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
print(" - one active historical mutation surface: iPhone")
print(" - legacy correction controls are read-only/hidden")
print(" - historical HKWorkoutBuilder + route run on iPhone")
print(" - explicit write authorization is verified")
print(" - raw Tracker data remains the reconstruction source")
print(" - create -> durable reread; no old-object cleanup")
print(" - rollback can only target the current v2 attempt")
print(" - internal HealthKit reread is not physical validation")
print(" - live Watch HKLiveWorkoutBuilder remains unchanged")
