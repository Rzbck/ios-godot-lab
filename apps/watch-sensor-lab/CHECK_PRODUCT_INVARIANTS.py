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

iphone_root = read("iphone/Sources/TrackerApp.swift")
iphone_history = read("iphone/Sources/HealthWorkoutHistory.swift")
iphone_review = read("iphone/Sources/SessionReviewTimeline.swift")
iphone_model = read("iphone/Sources/TrackerModel.swift")
iphone_reliable = read("iphone/Sources/WatchReliableRecovery.swift")
iphone_restore = read("iphone/Sources/TrackerRestoreRecovery.swift")
restore_packet = read("iphone/Sources/TrackerHealthRestorePacket.swift")
phone_bridge = read("iphone/Sources/PhoneRecentHistoryBridge.swift")

watch_root = read("watch/Sources/WatchSensorLabApp.swift")
watch_history = read("watch/Sources/WatchRecentHistory.swift")
watch_restore = read("watch/Sources/WatchRestoreWorkflow.swift")
watch_model = read("watch/Sources/SensorModel.swift")
reconciler = read("watch/Sources/WatchAutoHealthReconciler.swift")

# ------------------------------------------------------------
# A. Les surfaces doivent être RÉELLEMENT montées.
# ------------------------------------------------------------

require(
    iphone_root,
    "HistoryEntryView()",
    "Route iPhone historique"
)

require(
    iphone_history,
    "HealthWorkoutHistoryView()",
    "Entrée historique iPhone"
)

require(
    iphone_history,
    "ActivityReviewCard(",
    "Correction historique dans la fiche iPhone active"
)

require(
    iphone_review,
    "tracker.workflowCorrectHistoricalActivity(",
    "Action correction iPhone"
)

require(
    watch_root,
    "WatchVisualRecentPage(showHistory: $showHistory)",
    "Route Watch récentes"
)

require(
    watch_root,
    "WatchRecentHistoryView()",
    "Historique Watch monté"
)

require(
    watch_history,
    "model.workflowCorrectHistoricalActivity(",
    "Action correction Watch"
)

# La restauration est la fonction critique de l'incident 2026-09-11.
# Elle doit être réellement atteignable sur LES DEUX appareils.
require(
    iphone_root,
    "TrackerRestoreRecoveryView()",
    "Route restauration iPhone montée"
)

require(
    iphone_root,
    'Label("Récupération"',
    "Onglet restauration iPhone visible"
)

require(
    iphone_restore,
    "TrackerRestoreCandidateCard",
    "Carte restauration iPhone présente"
)

require(
    iphone_restore,
    '"Restaurer dans Santé"',
    "Action restauration iPhone visible"
)

require(
    iphone_restore,
    "tracker.workflowRestoreHistoricalActivity(",
    "UI restauration iPhone appelle le workflow"
)

require(
    iphone_restore,
    "restoreHistoricalActivityFromRaw(",
    "Workflow restauration iPhone appelle le backend raw"
)

require(
    watch_root,
    "WatchRestoreEntryPage().tag(4)",
    "Route restauration Watch montée"
)

require(
    watch_restore,
    'Text("RÉCUPÉRATION")',
    "Page restauration Watch visible"
)

require(
    watch_restore,
    '"Restaurer depuis Tracker"',
    "Action restauration Watch visible"
)

require(
    watch_restore,
    "model.workflowRestoreHistoricalActivity(",
    "UI restauration Watch appelle le workflow"
)

require(
    watch_restore,
    "requestHistoricalRestore(",
    "Workflow restauration Watch demande les raw à l'iPhone"
)

# ------------------------------------------------------------
# B. Une correction confirmée doit converger sur les 2 devices.
# ------------------------------------------------------------

require(
    watch_history,
    "func applyConfirmedActivity(",
    "Mise à jour locale Watch après correction"
)

require(
    reconciler,
    "WatchRecentHistoryStore.shared",
    "Reconciler -> historique Watch"
)

require(
    iphone_model,
    "recentHistoryBridge.publish(",
    "iPhone republie après résultat Watch"
)

require(
    phone_bridge,
    "healthBySession",
    "Digest Watch utilise aussi la vérité HealthKit"
)

require(
    iphone_model,
    '"replacement_verified"',
    "Persistance correction iPhone"
)

# ------------------------------------------------------------
# C. Transaction HealthKit :
#    créer -> relire/vérifier -> seulement ensuite supprimer.
# ------------------------------------------------------------

marker = "private func repairHistoricalActivityTransaction("
start = reconciler.find(marker)

if start < 0:
    errors.append("Transaction correction HealthKit absente")
else:
    tx = reconciler[start:]

    create = tx.find(
        "createHistoricalCorrectionWorkout("
    )

    verify = tx.find(
        "let verifiedWorkouts"
    )

    delete_original = tx.find(
        "try await deleteObjects(sourceWorkouts)"
    )

    rollback = tx.find(
        "try? await deleteObjects(replacementObjects)"
    )

    if min(create, verify, delete_original, rollback) < 0:
        errors.append(
            "Transaction HealthKit incomplète "
            "(create/verify/delete/rollback)"
        )
    elif not (
        create < verify < delete_original
    ):
        errors.append(
            "Ordre transactionnel invalide : "
            "la suppression précède la vérification"
        )

# ------------------------------------------------------------
# D. Les deux appareils doivent appeler le workflow COMMUN
#    pour la correction historique.
# ------------------------------------------------------------

for text, name in [
    (iphone_review, "iPhone"),
    (watch_history, "Watch"),
]:
    require(
        text,
        "workflowCorrectHistoricalActivity",
        f"Workflow commun {name}"
    )

# ------------------------------------------------------------
# E. Incident 2026-09-11 :
#    une demande utilisateur n'est PAS une vérité HealthKit.
# ------------------------------------------------------------

require(
    phone_bridge,
    'healthKitSyncState == "replacement_verified"',
    "Digest Watch refuse replacement_requested"
)

require(
    iphone_review,
    'review.healthKitSyncState == "replacement_verified"',
    "ActivityReviewStore refuse une correction non vérifiée"
)

require(
    reconciler,
    "cloneQuantitySamples(",
    "Replacement HealthKit clone les quantity samples"
)

require(
    reconciler,
    '"com.rzbck.watchsensorlab.reconstructed_sample"',
    "Samples reconstruits traçables"
)

require(
    reconciler,
    "var shareTypes: Set<HKSampleType>",
    "Autorisation écriture quantity samples"
)

# ------------------------------------------------------------
# F. Une validation AVANT suppression ne suffit pas.
#    Il faut une seconde relecture APRES suppression.
# ------------------------------------------------------------

if start >= 0:
    tx = reconciler[start:]

    delete_original = tx.find(
        "try await deleteObjects(sourceWorkouts)"
    )

    post_delete = tx.find(
        "var postDeleteWorkouts"
    )

    durable_samples = tx.find(
        "let postDeleteSamples"
    )

    if min(
        delete_original,
        post_delete,
        durable_samples,
    ) < 0:
        errors.append(
            "Transaction HealthKit sans vérification finale "
            "post-suppression"
        )
    elif not (
        delete_original
        < post_delete
        < durable_samples
    ):
        errors.append(
            "Ordre invalide de la relecture finale HealthKit"
        )

require(
    reconciler,
    "let postDeleteAutoWorkouts",
    "Réconciliation Auto relue après suppression"
)

require(
    iphone_model,
    '"replacement_failed_source_missing"',
    "Échec distingue source absente et original conservé"
)

require(
    iphone_model,
    "recentHistoryBridge.publish(",
    "Échec republie la vérité vers Watch"
)

# ------------------------------------------------------------
# G. Restauration raw Tracker -> HealthKit.
# ------------------------------------------------------------

require(
    restore_packet,
    '"watch_location"',
    "Restauration privilégie le GPS Watch"
)

require(
    restore_packet,
    '"heart_rate"',
    "Restauration conserve la fréquence cardiaque"
)

require(
    restore_packet,
    '"manual_pause"',
    "Restauration utilise les pauses Watch explicites"
)

require(
    restore_packet,
    "reconstructedActive",
    "Restauration vérifie la durée active avant transfert"
)

require(
    iphone_model,
    "session.transferFile(",
    "iPhone transfère la restauration comme fichier"
)

require(
    iphone_reliable,
    "didReceiveUserInfo",
    "iPhone reçoit les événements Watch durables"
)

require(
    iphone_reliable,
    "WatchReliableRecovery.ingest(userInfo)",
    "Événement Watch durable journalisé"
)

require(
    iphone_reliable,
    "receiveWC(userInfo)",
    "Événement Watch durable injecté dans le modèle produit"
)

if (
    iphone_model + iphone_reliable
).count("didReceiveUserInfo") != 1:
    errors.append(
        "iPhone doit avoir exactement un récepteur "
        "WCSession didReceiveUserInfo"
    )

require(
    watch_model,
    "didReceive file: WCSessionFile",
    "Watch reçoit le paquet de restauration"
)

require(
    reconciler,
    "restoreHistoricalActivityTransaction(",
    "Transaction restauration raw présente"
)

require(
    reconciler,
    "verifyRawRestoration(",
    "Restauration relue dans HealthKit"
)

require(
    reconciler,
    "700_000_000",
    "Restauration possède une seconde relecture différée"
)

restore_marker = (
    "private func restoreHistoricalActivityTransaction("
)

restore_start = reconciler.find(restore_marker)

if restore_start < 0:
    errors.append(
        "Transaction restauration raw absente"
    )
else:
    restore_tx = reconciler[restore_start:]

    next_marker = restore_tx.find(
        "private func makeRawRestoreSamples("
    )

    if next_marker >= 0:
        restore_tx = restore_tx[:next_marker]

    if "deleteObjects(sourceWorkouts)" in restore_tx:
        errors.append(
            "Restauration raw ne doit jamais supprimer "
            "un workout source"
        )

    if "deleteObjects(existing)" in restore_tx:
        errors.append(
            "Restauration raw ne doit jamais supprimer "
            "un workout existant"
        )

    compact_restore_tx = "".join(restore_tx.split())

    if "deleteObjects(createdObjects)" not in compact_restore_tx:
        errors.append(
            "Restauration raw sans rollback des objets créés"
        )

# ------------------------------------------------------------
# H. Le chemin de restauration doit rester cohérent de bout en bout.
# ------------------------------------------------------------

iphone_restore_compact = "".join(iphone_restore.split())
watch_restore_compact = "".join(watch_restore.split())
watch_model_compact = "".join(watch_model.split())
iphone_model_compact = "".join(iphone_model.split())

require(
    iphone_restore_compact,
    "tracker.workflowRestoreHistoricalActivity(",
    "Chaîne restauration iPhone UI -> workflow"
)

require(
    iphone_restore_compact,
    "restoreHistoricalActivityFromRaw(",
    "Chaîne restauration iPhone workflow -> raw"
)

require(
    watch_restore_compact,
    "model.workflowRestoreHistoricalActivity(",
    "Chaîne restauration Watch UI -> workflow"
)

require(
    watch_restore_compact,
    "requestHistoricalRestore(",
    "Chaîne restauration Watch workflow -> iPhone"
)

require(
    watch_model_compact,
    'request.command="restore_historical_activity"',
    "Commande restauration Watch -> iPhone"
)

require(
    iphone_model_compact,
    'message.command=="restore_historical_activity"',
    "Commande restauration reçue par iPhone"
)

if errors:
    print(
        "TRACKER PRODUCT INVARIANTS: FAIL",
        file=sys.stderr
    )

    for error in errors:
        print(f" - {error}", file=sys.stderr)

    sys.exit(1)

print("TRACKER PRODUCT INVARIANTS: OK")
print(" - mounted iPhone historical correction")
print(" - mounted Watch historical correction")
print(" - cross-device correction convergence")
print(" - HealthKit create/verify/delete ordering")
print(" - mounted iPhone raw HealthKit restoration")
print(" - mounted Watch raw HealthKit restoration")
print(" - end-to-end raw restore command path")
