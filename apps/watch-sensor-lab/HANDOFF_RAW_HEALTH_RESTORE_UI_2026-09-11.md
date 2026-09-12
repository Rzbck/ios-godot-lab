# HANDOFF — Historical HealthKit Restore — 2026-09-12

## Objectif

Restaurer correctement la session Tracker brute `1789141684582` comme `cycling` / Vélo dans Apple Santé et Forme, sans perdre les raw Tracker, sans doublon et sans réactiver les anciens chemins concurrents de correction historique.

## Dépôt / chantier

- dépôt : `Rzbck/ios-godot-lab`
- worktree Windows : `E:\_Project\IOS APP\ios-godot-lab\worktrees\watch-healthkit-historical-unification`
- branche : `fix/watch-healthkit-historical-unification-20260912`
- dernier SHA de code avant cette mise à jour documentaire : `5f6efa6ac6b497cb395f379234bc760a9509a90b`
- SHA installé ayant reproduit l’erreur route : `34cafd1f94721fd8ea5e69dad798348689c8985a`

Toujours revérifier `HEAD`, `git status`, la branche et la CI avant toute nouvelle modification ou installation.

## Données incident à préserver

- session raw : `1789141684582`
- cible réelle : `cycling` / Vélo
- 354 samples cardio Watch exploitables
- 344 points GPS Watch valides
- 515 points GPS iPhone valides
- 4 intervalles de pause reconstruits
- snapshot incident gelé
- ZIP incident SHA-256 : `269AB9E727AA62BCC202594DE33F994902B936C555D0C407DCC2BA56D01C45B0`
- manifest restauration SHA-256 : `7FF9907FB8BE4FFC42892F512090FEF65233ED3AFF05865063A59B701FA4EB86`

Ne jamais modifier ou supprimer les raw Tracker de cette session.

## Historique matériel réellement observé

### Build `b355cca10bc173536f61972914710cc6d30e4c07`

- UI `Récupération` présente physiquement sur iPhone et Watch.
- première tentative : `authorization is not determined`, puis autorisations Santé accordées sur Watch.
- seconde tentative : l’app a cru la restauration réussie et la session a disparu de la liste de récupération.
- observation utilisateur : aucun exercice correspondant dans Santé ni Forme.
- verdict : **échec produit**, malgré la relecture interne HealthKit.
- l’ancien résumé local a pu afficher Vélo alors que Santé/Forme n’avaient aucun workout : la relecture interne ne doit jamais promouvoir la vérité produit.

### Build `34cafd1f94721fd8ea5e69dad798348689c8985a`

- CI run device artifact : `34676438775`, succès complet.
- IPA installée physiquement sur iPhone + companion Watch.
- session raw visible dans l’app iPhone, absente de Santé/Forme, Vélo sélectionnable.
- une seule tentative a été lancée.
- erreur exacte observée : `This route builder is attached to a workout builder and will be finished with the workout builder`.
- après erreur : aucun exercice correspondant visible dans Santé ni Forme.
- verdict : **échec matériel**, ne pas relancer cette IPA.

## Cause racine du deuxième échec

Dans `HistoricalHealthKitRepair.swift`, le route builder était obtenu via :

`HKWorkoutBuilder.seriesBuilder(for: HKSeriesType.workoutRoute())`

Il est donc attaché au `HKWorkoutBuilder`. Le code appelait ensuite `finishWorkout`, puis tentait à nouveau `finishRoute` sur ce route builder attaché. Sur l’appareil, HealthKit refuse cette double finalisation avec le message ci-dessus.

Le correctif de `5f6efa6ac6b497cb395f379234bc760a9509a90b` :

- ajoute les métadonnées au route builder attaché avant la finalisation ;
- insère les points GPS ;
- finalise uniquement le `HKWorkoutBuilder` ;
- relit ensuite la route associée depuis HealthKit au lieu d’appeler `finishRoute` une seconde fois ;
- ajoute un `historical_attempt_id` unique à chaque tentative ;
- vérifie workout, samples et route uniquement avec cet identifiant de tentative afin qu’un ancien essai partiel ne puisse pas produire un faux positif ;
- le rollback ne cible que les objets portant l’identifiant de la tentative courante.

## Architecture active

- LIVE : Watch reste l’autorité HealthKit, avec `HKWorkoutSession` + `HKLiveWorkoutBuilder`.
- reconstruction HISTORIQUE : iPhone uniquement, via `HKWorkoutBuilder` et raw Tracker.
- la Watch ne doit plus proposer un deuxième système actif de correction historique.
- l’ancien panneau de correction iPhone doit rester lecture seule.
- une relecture `HKHealthStore` n’est pas une validation Santé/Forme.

## Ce qui est validé

- raw/preflight de la session ;
- UI de récupération sur matériel ;
- pipeline exact-SHA ;
- installation iPhone + Watch du build `34cafd1...` ;
- reproduction matérielle exacte de l’erreur de double finalisation du route builder ;
- cause dans le code identifiée et corrigée dans `5f6efa6...`.

## Ce qui n’est PAS encore validé

- CI du SHA final contenant le correctif route ;
- artifact device exact du SHA final ;
- installation physique du correctif ;
- création réelle du workout Vélo dans Santé ;
- présence dans Forme ;
- cardio, distance et route GPS du workout restauré ;
- absence de doublon ;
- persistance après fermeture/réouverture ;
- éventuels objets HealthKit partiels laissés par les anciennes tentatives.

## Règles de test matériel

- ne plus lancer de restauration avec `34cafd1...` ;
- une seule tentative par nouveau candidat matériel ;
- après tentative, ne jamais conclure au succès sur le seul statut interne de l’app ;
- vérifier d’abord Santé puis Forme ;
- ensuite seulement vérifier cardio, distance, route et cohérence temporelle ;
- ne pas utiliser l’ancien système `Corriger le sport` pendant le diagnostic ;
- ne supprimer aucun objet HealthKit ancien/masqué sans identification précise de son UUID et de sa provenance.

## Règle PowerShell / workflow utilisateur

L’utilisateur ne veut plus de gros blocs PowerShell interactifs multilignes qui restent bloqués sur le prompt `>>`.

Pour ce chantier :

- privilégier les scripts `.ps1` déjà présents dans le dépôt ;
- donner une commande courte à la fois ;
- éviter les gros blocs `& { ... }` sauf nécessité absolue et demande explicite ;
- attendre la sortie de la commande courte avant l’étape suivante ;
- conserver `UPDATE_WATCH_SENSOR_LAB.ps1` comme workflow normal exact-SHA pour récupérer l’IPA.

## Prochaine étape exacte

1. vérifier le HEAD final de `fix/watch-healthkit-historical-unification-20260912` après cette mise à jour ;
2. attendre la CI du HEAD final ;
3. si rouge : lire l’erreur exacte et corriger sans test matériel ;
4. si vert : utiliser `UPDATE_WATCH_SENSOR_LAB.ps1` depuis le worktree dédié pour produire/récupérer l’artifact device exact ;
5. installer l’IPA sur iPhone + Watch ;
6. confirmer que la session `1789141684582` est toujours visible dans `Récupération` et absente de Santé/Forme ;
7. sélectionner Vélo ;
8. lancer **une seule** reconstruction ;
9. relever le statut final exact ;
10. contrôler Santé et Forme avant toute autre action.

## Éléments à ne pas modifier

- raw session `1789141684582` ;
- snapshot/ZIP/manifest incident ;
- architecture LIVE Watch ;
- exact-SHA pipeline ;
- protections transactionnelles ;
- autres workouts HealthKit non concernés ;
- stash/sauvegardes locales de l’ancien worktree sans demande explicite.
