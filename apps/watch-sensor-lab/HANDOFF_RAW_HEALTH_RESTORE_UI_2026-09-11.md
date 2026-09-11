# HANDOFF — Raw HealthKit Restore UI — 2026-09-11

## Objectif

Rendre la restauration d’une séance Tracker disparue de HealthKit réellement atteignable sur iPhone ET Apple Watch, puis restaurer physiquement la session `1789141684582` en `cycling` / Vélo.

## Dépôt

`Rzbck/ios-godot-lab`

## Branche

`fix/watch-auto-run-integrity-20260911`

## Point de départ vérifié

Backend raw compilé/vert :
`e7b5006048f75644ea07e32e76a9405a10dd4bdb`

Ce build a été installé physiquement, mais ne contenait pas encore de surface UI montée pour lancer la restauration. Ne pas le considérer comme validation matérielle de la restauration.

## Changements GitHub directs après ce point

- iPhone : ajout de `TrackerRestoreRecoveryView` et du workflow UI vers `restoreHistoricalActivityFromRaw`.
- iPhone : montage d’un onglet `Récupération` dans `TrackerApp.swift`.
- Watch : ajout de `WatchRestoreEntryPage` et du workflow vers `requestHistoricalRestore`.
- Watch : montage de la page de récupération dans `ReadyWatchHomeView`.
- CI : `CHECK_PRODUCT_INVARIANTS.py` renforcé pour exiger les deux surfaces et le chemin de commande end-to-end.
- Documentation : `docs/RAW_HEALTHKIT_RESTORE_UI_2026-09-11.md`.

## Ce qui est déjà validé

- backend raw restauration compilé sur iPhone et Watch avant ajout UI ;
- préflight raw de `1789141684582` : OK ;
- 354 samples cardio Watch exploitables ;
- 344 points GPS Watch valides ;
- 515 points GPS iPhone valides ;
- 4 intervalles de pause reconstruits ;
- durée active reconstruite dans la tolérance ;
- restauration backend conçue sans suppression d’un workout existant ;
- double relecture HealthKit prévue avant succès.

## Ce qui n’est PAS encore validé

- compilation CI du nouvel UI de récupération ;
- device artifact du nouvel UI ;
- installation physique de ce nouvel UI ;
- restauration réelle de `1789141684582` ;
- présence finale dans Santé ;
- cardio/route/distance après restauration ;
- persistance après fermeture/réouverture ;
- cohérence finale iPhone + Watch.

## Règle introduite suite à l’incident

Ne plus produire/installer un device candidate pour une fonction critique tant que la CI ne prouve pas que sa surface UI réelle est montée et reliée au backend sur tous les appareils concernés.

## Prochaine étape exacte

1. attendre le run CI correspondant au dernier commit de code ;
2. si rouge : lire l’erreur exacte, corriger sur GitHub, relancer ;
3. si vert : déclencher `workflow_dispatch` sur le même HEAD pour produire l’artifact ;
4. vérifier artifact SHA/digest ;
5. installer iPhone + Watch ;
6. vérifier visuellement les surfaces `Récupération` ;
7. sélectionner la session `1789141684582` et `Vélo` ;
8. lancer une seule restauration ;
9. attendre le statut `Restauration Santé vérifiée` ;
10. contrôler Santé, iPhone, Watch ;
11. fermer/réouvrir les apps et contrôler à nouveau.

## Éléments à ne pas modifier

- snapshot incident gelé ;
- ZIP incident SHA-256 `269AB9E727AA62BCC202594DE33F994902B936C555D0C407DCC2BA56D01C45B0` ;
- manifest restauration SHA-256 `7FF9907FB8BE4FFC42892F512090FEF65233ED3AFF05865063A59B701FA4EB86` ;
- session raw `1789141684582` ;
- autorité HealthKit Watch pour les écritures ;
- exact-SHA pipeline ;
- protections transactionnelles post-incident.
