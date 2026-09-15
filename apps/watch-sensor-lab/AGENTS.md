# Collaboration IA — Watch Sensor Lab

Ces règles s'appliquent uniquement à `apps/watch-sensor-lab`.

## Point de départ obligatoire

Avant toute modification, lire dans cet ordre :

1. le `HANDOFF_*.md` du chantier concerné ;
2. `TESTING_STRATEGY.md` ;
3. les workflows `.github/workflows/watch-sensor-lab-*.yml` ;
4. la branche GitHub, son HEAD exact et ses dernières CI.

Toujours vérifier `git worktree list --porcelain`, la branche, le HEAD et l'état CLEAN/DIRTY. Un chantier actif utilise une branche et un worktree dédiés. Quand l'environnement d'agents partage nécessairement le même système de fichiers, le coordinateur attribue des fichiers exclusifs et interdit les commits concurrents ; sinon, chaque agent d'écriture utilise son propre worktree.

Les changements de cette application et de ses deux workflows sont associés à
`@Rzbck` par le `CODEOWNERS` racine. Cette attribution est volontairement
limitée à Watch Sensor Lab : aucune protection globale de `main` ne doit être
ajoutée pour contourner les autres projets du dépôt.

## Répartition parallèle

Le coordinateur découpe le travail en périmètres sans fichiers communs :

- **politique Auto et tests purs** : `Shared/TrackerAutoPolicy.swift`, `Shared/TrackerAutoResumeProbe.swift`, `Tests/Support/TrackerAutomationScenario.swift`, `Tests/TrackerAutoPolicyTests.swift`, `Tests/TrackerAutomationScenarioTests.swift` ;
- **runtime Watch** : `watch/Sources/SensorModel.swift`, `watch/Sources/WatchAutoPolicy.swift`, `watch/Sources/WatchAutoPauseSettings.swift` ;
- **fin de séance et Santé** : `Shared/TrackerSessionControl.swift`, vues de confirmation iPhone/Watch, `watch/Sources/WatchAutoHealthReconciler.swift`, tests UI et contractuels associés ;
- **CI et outillage** : workflows Watch Sensor Lab, scripts `APPLY_*`, `RUN_*`, `CHECK_*`, synchronisation IPA et documentation.

Si deux tâches doivent toucher le même fichier, elles ne sont pas parallèles : le coordinateur les ordonne. Chaque agent remet un diff circonscrit, ses commandes de validation et les limites non testées. Un seul coordinateur crée les commits dans un worktree partagé ; avec des worktrees séparés, les agents peuvent remettre des commits autonomes. Les agents ne mergent pas `main`.

## Sources générées par patchs

Le build applique actuellement une chaîne de patchs aux sources Swift. Un changement runtime doit donc être vérifié dans les deux états :

- fichiers suivis par Git avant patch ;
- fichiers produits après `SESSION_SYNC_PATCH.py` et les scripts de pré-build.

Ordre actuel à préserver :

```text
SESSION_SYNC_PATCH.py
  -> APPLY_AUTO_PAUSE_SAFETY_PATCH.py
  -> APPLY_TERMINAL_SYNC_RELIABILITY_PATCH.py
     -> APPLY_RUNTIME_INTEGRITY_PATCH.py
  -> APPLY_HISTORICAL_CORRECTION_DISTANCE_PATCH.py

Xcode pre-build
  -> APPLY_AUTO_PAUSE_SAFETY_PATCH.py
  -> APPLY_AUTO_BEHAVIOR_PATCH.py
  -> RUN_HISTORICAL_CORRECTION_DISTANCE_PATCH.py
```

Les patchs doivent échouer proprement si leur précondition n'est plus vraie et rester idempotents. Ne pas valider leur comportement uniquement par recherche de chaînes : les tests XCTest doivent exercer les noyaux concernés.

La cible de maintenance est de replier les patchs validés dans les sources Swift suivies par Git, un domaine à la fois, puis de retirer le patch correspondant après CI exact-SHA. Ne pas effectuer ce repli en même temps qu'un changement de comportement.

## Validation minimale par domaine

- changement Auto : contrats iPhone et Watch, replay déterministe, cas sans signal, signaux contradictoires et données périmées ;
- changement fin de séance : tests force / preserve / cancel sur iPhone et Watch, contrôle de commande exact-token et plan Santé final ;
- changement runtime Watch : compilation iPhone + Watch et contrôles de reconnexion/pause ;
- changement CI ou patch : préflight, deux exécutions successives des patchs concernés, puis workflows complets ;
- candidat appareil : tests et build verts sur le même SHA, artifact exact-SHA, récupération par `UPDATE_WATCH_SENSOR_LAB.ps1`, puis validation physique explicitement séparée.

Une IPA compilée ou installée n'est jamais déclarée validée physiquement sans retour de l'utilisateur. Ne pas merger dans `main`, publier une release ou promouvoir un candidat sans son accord explicite.
