# Raw HealthKit Restore UI — 2026-09-11

## Pourquoi ce document existe

L’incident de la session `1789141684582` a montré qu’un backend HealthKit compilé ne suffit pas : la fonction critique doit être réellement atteignable depuis les interfaces installées avant de produire un device artifact.

Le build `e7b5006048f75644ea07e32e76a9405a10dd4bdb` contenait le backend de restauration raw mais pas encore de surface utilisateur montée pour lancer cette restauration. Il ne devait donc pas être considéré comme candidat matériel complet pour ce test précis.

## Règle de validation introduite

Pour toute fonction critique iPhone/Watch :

1. la route UI réelle doit être montée ;
2. l’action visible doit appeler le workflow attendu ;
3. le workflow doit atteindre le backend réel ;
4. les deux appareils doivent être couverts quand la fonction est cross-device ;
5. ces propriétés doivent être vérifiées par CI avant la génération d’un artifact appareil ;
6. seulement après une CI verte, produire l’artifact exact-SHA et tester physiquement.

## Surface iPhone

Nouvelle surface : `TrackerRestoreRecoveryView`.

Elle est montée comme onglet `Récupération` dans `TrackerApp.swift`.

Elle compare les `TrackerSummary` locaux avec les workouts Tracker actuellement lisibles dans HealthKit via la metadata `com.rzbck.watchsensorlab.session_id`.

Une séance locale dont le session ID n’est pas lisible dans Santé apparaît comme candidate à la restauration.

L’utilisateur doit choisir explicitement le sport avant de lancer `Restaurer dans Santé`.

Le chemin d’appel est :

`TrackerRestoreRecoveryView`
→ `TrackerModel.workflowRestoreHistoricalActivity`
→ `restoreHistoricalActivityFromRaw`
→ construction paquet raw
→ `WCSession.transferFile`
→ Watch.

## Surface Watch

Nouvelle surface : `WatchRestoreEntryPage`.

Elle est montée comme page supplémentaire du `ReadyWatchHomeView`.

Elle permet de sélectionner une séance synchronisée et un sport, puis d’appeler `Restaurer depuis Tracker`.

Le chemin d’appel est :

`WatchRestoreEntryPage`
→ `SensorModel.workflowRestoreHistoricalActivity`
→ `requestHistoricalRestore`
→ commande `restore_historical_activity`
→ iPhone construit le paquet raw
→ transfert fichier vers Watch
→ transaction HealthKit.

## Garde-fous backend conservés

La restauration raw :

- ne supprime aucun workout HealthKit existant ;
- refuse la création si un workout Tracker existe déjà pour le même session ID ;
- crée de nouveaux samples ;
- reconstruit le parcours ;
- relit et vérifie le workout restauré ;
- effectue une seconde relecture différée ;
- rollback uniquement les objets créés par la tentative si la validation échoue.

## Tests CI bloquants

`CHECK_PRODUCT_INVARIANTS.py` vérifie désormais explicitement :

- route iPhone `TrackerRestoreRecoveryView()` montée ;
- action visible `Restaurer dans Santé` ;
- UI iPhone → `workflowRestoreHistoricalActivity` ;
- workflow iPhone → `restoreHistoricalActivityFromRaw` ;
- route Watch `WatchRestoreEntryPage().tag(4)` montée ;
- action visible `Restaurer depuis Tracker` ;
- UI Watch → `workflowRestoreHistoricalActivity` ;
- workflow Watch → `requestHistoricalRestore` ;
- commande Watch `restore_historical_activity` ;
- réception de cette commande côté iPhone ;
- transfert fichier ;
- transaction et double vérification HealthKit ;
- absence de suppression d’un workout existant dans le chemin de restauration.

## Session de récupération prioritaire

Session : `1789141684582`

Cible utilisateur : `cycling` / Vélo.

Le préflight raw déjà réalisé reste la référence avant écriture Santé :

- HR Watch exploitables : `354` ;
- GPS Watch valides : `344` ;
- GPS iPhone valides : `515` ;
- pauses reconstruites : `4` ;
- durée active summary : `838.864 s` ;
- durée active reconstruite : `859.899 s` ;
- delta : `+21.036 s` ;
- tolérance : `33.555 s` ;
- résultat : `PREFLIGHT RAW RESTORE: OK`.

## Validation matérielle requise

Ne déclarer la restauration validée qu’après :

- création du workout Vélo dans Santé ;
- cardio présent ;
- parcours présent ;
- distance cohérente ;
- horaires cohérents ;
- aucune séance Tracker dupliquée ;
- affichage cohérent iPhone + Watch ;
- fermeture/réouverture des deux apps ;
- nouvelle vérification dans Santé après réouverture.
