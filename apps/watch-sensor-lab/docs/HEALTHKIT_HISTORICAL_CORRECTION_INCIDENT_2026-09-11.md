# Incident HealthKit — correction historique 2026-09-11

## Portée

Application : Watch Sensor Lab

Branche :
`fix/watch-auto-run-integrity-20260911`

Build matériel concerné lors de l'observation finale :
`77ff62acceec5034e785c4a424b4919938e087d3`

Session terrain à restaurer :
`1789141684582`

Activité confirmée par l'utilisateur :
`cycling` / Vélo

## État initial connu

Le workout HealthKit de cette session a été sauvegardé par la Watch avec :

- activité HealthKit : `walking`
- workout UUID :
  `CBC8097B-4C5A-4851-804A-84E8F5716177`

L'événement durable `health_workout_saved` existe dans
`watch_reliable.jsonl`.

La session Tracker brute reste disponible indépendamment de HealthKit.

Résumé Tracker conservé :

- début : `2026-09-11T15:48:04Z`
- fin : `2026-09-11T16:28:25Z`
- durée active : `838.8637968301773 s`
- distance : `2801.3859133812175 m`
- énergie active : `163.46184575168397 kcal`
- FC moyenne : `141.9047936085219 bpm`
- D+ : `57.109818596908674 m`
- D- : `64.02989046631959 m`

Les raw contiennent notamment :

- `344` enregistrements `watch_location`
- `354` enregistrements `heart_rate`
- `410` enregistrements `pedometer`
- `912` enregistrements `authority_metrics`
- `10008` enregistrements `motion`

## Sauvegardes gelées

Snapshot post-incident :

`E:\_Project\IOS APP\_Analysis\watch-sensor-lab\incident-post-correction-20260911-220227`

ZIP :

`E:\_Project\IOS APP\_Analysis\watch-sensor-lab\incident-post-correction-20260911-220227.zip`

SHA-256 ZIP :

`269AB9E727AA62BCC202594DE33F994902B936C555D0C407DCC2BA56D01C45B0`

Manifest de restauration :

`RESTORE_MANIFEST_1789141684582.json`

SHA-256 manifest :

`7FF9907FB8BE4FFC42892F512090FEF65233ED3AFF05865063A59B701FA4EB86`

Ces fichiers ne doivent pas être modifiés ou supprimés.

## Observation matérielle

Après une tentative de correction depuis l'iPhone :

- l'interface Watch a affiché Vélo ;
- après fermeture/réouverture de l'app iPhone, la séance n'était
  plus présente dans l'historique HealthKit de l'application ;
- la séance avait également disparu de Santé Apple.

Cette observation matérielle est autoritaire.

## Log de correction actuellement disponible

Le log durable disponible contient :

1. `health_manual_correction_started`
2. cible `cycling`
3. `health_manual_correction_failed`
4. message :
   `aucun workout Watch Tracker correspondant à cette session`

Conclusion certaine :

au moment de CETTE tentative observée, il n'existait déjà plus
de workout Watch Tracker associé à `1789141684582`.

Cette tentative n'est donc pas celle qui permet d'identifier
la suppression initiale.

## Cause de disparition : NON encore prouvée

Ne pas écrire ou supposer qu'une ligne précise du moteur est la
cause de la disparition tant que cela n'est pas démontré.

Le code installé possède toutefois une faiblesse transactionnelle
réelle :

- création du remplacement ;
- première relecture HealthKit ;
- suppression de la source ;
- pas de seconde relecture obligatoire du remplacement après la
  suppression.

Cette faiblesse doit être corrigée même si elle n'est pas encore
prouvée comme cause exacte de cet incident.

## Bug UI / convergence prouvé

`ActivityReviewCard.saveReview()` sauvegarde le choix utilisateur
avant la confirmation HealthKit avec :

`healthKitSyncState = replacement_requested`

`PhoneRecentHistoryBridge` utilise actuellement
`confirmedActivity` en priorité sans exiger
`replacement_verified`.

Conséquence :

une surface iPhone ou Watch peut afficher `cycling` alors que
HealthKit n'a pas confirmé la correction.

Règle durable :

`replacement_requested` n'est jamais une vérité d'activité
HealthKit.

Seul `replacement_verified` peut remplacer l'activité HealthKit
dans les surfaces historiques synchronisées.

Un libellé d'interface ne constitue jamais une preuve de mutation
HealthKit.

## Invariants transactionnels à imposer

Une correction historique destructive doit respecter :

1. identifier explicitement la ou les sources ;
2. figer les données nécessaires au remplacement ;
3. créer le remplacement ;
4. relire et vérifier le remplacement ;
5. ne supprimer aucune source avant cette vérification ;
6. supprimer la source ;
7. RELIRE À NOUVEAU HealthKit ;
8. vérifier que le remplacement existe toujours et correspond au
   UUID/type/session attendus ;
9. seulement ensuite émettre
   `health_manual_correction_completed`;
10. seulement ensuite faire converger iPhone + Watch vers le sport
    corrigé.

Une erreur ne doit jamais déclarer
`original_preserved = true` si aucune source n'existe réellement.

## Samples HealthKit

Pour les restaurations à partir de Tracker raw :

- ne pas dépendre d'anciens objets `HKSample` ;
- créer de nouveaux `HKQuantitySample` à partir des valeurs Tracker ;
- associer ces nouveaux samples au nouveau workout ;
- reconstruire le parcours à partir des `watch_location` ;
- utiliser la FC brute `heart_rate` ;
- utiliser les événements pause/reprise issus des transitions de phase ;
- vérifier la nouvelle représentation par relecture HealthKit.

## Restauration de 1789141684582

Cette session est désormais un cas de restauration, et non une simple
correction d'un workout existant.

Source de vérité disponible :

`Documents/Sessions/1789141684582`

Objectif :

recréer un workout HealthKit `cycling` conservant autant que possible :

- horaire réel ;
- pauses ;
- distance ;
- fréquence cardiaque ;
- énergie ;
- parcours GPS ;
- dénivelé ;
- provenance Tracker ;
- session ID original.

Ne jamais recréer plusieurs fois le même workout.

Le restaurateur devra être idempotent grâce au session ID et à une
metadata de restauration dédiée.

## Validation physique obligatoire

La restauration ne sera considérée validée que lorsque :

- Santé Apple affiche la séance en Vélo ;
- la séance reste présente après fermeture/réouverture ;
- iPhone et Watch affichent le même sport ;
- horaires et durée sont cohérents ;
- distance est cohérente ;
- fréquence cardiaque est présente ;
- parcours est présent et cohérent ;
- aucune ancienne séance Marche dupliquée ne subsiste.

## Règle de développement issue de l'incident

Tout futur chantier de mutation historique HealthKit doit ajouter :

- documentation de l'incident ou migration ;
- sauvegarde avant opération destructive ;
- preuve de relecture HealthKit après mutation ;
- invariant automatisé lorsque vérifiable statiquement ;
- validation matérielle distincte de la CI.


## Durcissement candidat après incident

État : code local candidat, NON encore compilé par CI et NON validé matériellement.

Correctifs introduits :

- `replacement_requested` ne peut plus alimenter l'activité historique synchronisée ;
- seule une correction `replacement_verified` peut changer la vérité affichée ;
- un échec republie immédiatement l'état réel vers la Watch ;
- `original_preserved` est calculé d'après une relecture HealthKit réelle ;
- les anciens `HKQuantitySample` ne sont plus réutilisés directement ;
- chaque remplacement reçoit de nouveaux `HKQuantitySample` traçables ;
- les types quantité nécessaires sont demandés en écriture ;
- correction historique : relecture obligatoire après suppression de la source ;
- réconciliation Auto : relecture obligatoire après suppression du conteneur original ;
- ces règles deviennent des invariants bloquants dans `CHECK_PRODUCT_INVARIANTS.py`.

Important :

ces changements ne restaurent PAS encore la session `1789141684582`.
La restauration restera une opération séparée et idempotente à partir des raw Tracker.
