# HANDOFF — Historical HealthKit Restore — 2026-09-12

## Objectif

Restaurer correctement la session Tracker brute `1789141684582` comme `cycling` / Vélo dans Apple Santé et Forme, sans perdre les raw Tracker, sans doublon et sans réactiver les anciens chemins concurrents de correction historique.

Un deuxième chantier live/post-session est désormais identifié : nettoyer le workflow de fin d’activité iPhone + Watch afin qu’aucune ancienne UI ou étape de confirmation incomplète ne subsiste.

## Dépôt / chantier

- dépôt : `Rzbck/ios-godot-lab`
- worktree Windows : `E:\_Project\IOS APP\ios-godot-lab\worktrees\watch-healthkit-historical-unification`
- branche : `fix/watch-healthkit-historical-unification-20260912`
- HEAD local vérifié avant développement v4 : `d2bb22a9fc188bddf5d5bcc98a54bc1bfd2dadf9`
- dernier SHA de code v4 testé CI avant cette mise à jour documentaire : `70723649a88f87140a21a3e07c93b3e2b25b863c`
- CI v4 : run `34679790259`, succès complet (invariants, iPhone, Watch, HealthKit, packaging)
- l’utilisateur indique avoir installé la nouvelle IPA après ce build, mais la sortie exacte de l’updater / SHA-256 de cette installation n’a pas été recopiée dans le chat : ne pas inventer l’identité matérielle exacte sans vérification.

Toujours revérifier `HEAD`, `git status`, la branche et la CI avant toute nouvelle modification ou installation.

## Données incident à préserver

- session raw : `1789141684582`
- cible réelle : `cycling` / Vélo
- début : `2026-09-11T15:48:04Z`
- fin : `2026-09-11T16:28:25Z`
- durée active summary : `838.8637968301773 s`
- distance summary gelée : `2801.3859133812175 m`
- énergie active : `163.46184575168397 kcal`
- FC moyenne : `141.9047936085219 bpm`
- D+ : `57.109818596908674 m`
- D- : `64.02989046631959 m`
- 354 samples cardio Watch exploitables
- 344 points GPS Watch valides
- 515 points GPS iPhone valides
- 4 intervalles de pause reconstruits
- snapshot incident gelé : `E:\_Project\IOS APP\_Analysis\watch-sensor-lab\incident-post-correction-20260911-220227`
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

### Build `34cafd1f94721fd8ea5e69dad798348689c8985a`

- CI run device artifact : `34676438775`, succès complet.
- IPA installée physiquement sur iPhone + companion Watch.
- une reconstruction Vélo a échoué avec : `This route builder is attached to a workout builder and will be finished with the workout builder`.
- après erreur : aucun exercice correspondant visible dans Santé ni Forme.
- verdict : **échec matériel**.

### Build/code `3e955e978198bbf33db0797a6df3c74479254389` — v3 full-fidelity

- artifact exact produit par run `34678577777`.
- IPA : `E:\_Project\IOS APP\ios-godot-lab\artifacts\watch-sensor-lab\3e955e978198\WatchSensorLab-companion-unsigned-3e955e978198.ipa`
- IPA SHA-256 : `a56b08b6c8e8ddeeb585dd87e1e8d66e8f9300bb4702e74abda1bd16ebbcc41d`.
- installée physiquement iPhone + Watch selon l’utilisateur.
- reconstruction v3 : statut interne `HealthKit full-fidelity écrit et relu · PAS encore validé dans Santé/Forme`.
- Santé/Forme montrent un second workout Vélo : il y a désormais **2 restaurations de test** de la session.
- malgré la relecture interne : **aucune carte/tracé visible dans Forme**.
- l’utilisateur avait explicitement choisi un effort Apple 1–10 ; la v3 relit le `workoutEffortScore` associé au workout, mais **aucun effort visible dans Forme**.
- verdict : workout/route/effort existent côté HealthKit selon nos requêtes, mais le résultat produit visible reste incomplet ; **ne plus créer de restauration supplémentaire avant nettoyage**.

## Audit GPS raw hors ligne — lecture seule

Script : `apps/watch-sensor-lab/ANALYZE_HISTORICAL_ROUTE.py`.

Résultats sur le snapshot gelé :

### Watch
- 344 points valides
- couverture : début +42.73 s / fin -0.76 s
- gaps méd/p90/p95/max : `1.02 / 1.48 / 2.04 / 1162.08 s`
- gaps >3/>5/>10/>30 : `13 / 10 / 9 / 7`
- précision méd/p90/max : `4.7 / 6.5 / 21.4 m`
- distance géométrique brute : `3844.6 m`
- écart vs summary : `+1043.2 m`
- vitesse géométrique max : `73.4 km/h`
- 0 point pendant les pauses reconstruites

### iPhone
- 515 points valides
- couverture : début +3.08 s / fin -0.96 s
- gaps méd/p90/p95/max : `1.00 / 1.17 / 2.00 / 1160.56 s`
- gaps >3/>5/>10/>30 : `18 / 12 / 8 / 6`
- précision méd/p90/max : `8.8 / 13.2 / 35.0 m`
- distance géométrique brute : `4180.2 m`
- écart vs summary : `+1378.8 m`
- vitesse géométrique max aberrante : `321239.6 km/h`
- 1 point pendant une pause

Conclusion : ne pas injecter aveuglément un flux GPS complet. Les gaps traversant les pauses ne doivent pas être assimilés à des pertes GPS actives, et les sauts impossibles doivent être filtrés. Le choix Watch/iPhone doit être fondé sur un audit actif/hors-pause, précision, continuité et cohérence des compteurs raw — pas sur le seul nombre de points.

## V4 clean recovery

Code principal : `apps/watch-sensor-lab/iphone/Sources/HistoricalHealthKitRepairV4.swift`.

Règles :
- diagnostic Watch + iPhone avant toute mutation ;
- aucune nouvelle reconstruction si une restauration de test existe déjà ;
- nettoyage explicite seulement ;
- nettoyage limité aux objets portant `raw_restoration=true` + session ID exact ;
- raw Tracker et workouts normaux intouchables ;
- lecture des compteurs raw Watch/iPhone et détection de conflit avec `summary.distanceMeters` ;
- route Watch/iPhone filtrée (pauses, précision, sauts impossibles) avant sélection ;
- reconstruction bloquée si conflit de distance non résolu ;
- une seule restauration v4 autorisée ;
- relectures durables de l’unicité workout + route + effort.

UI v4 :
- `Récupération Santé v4`
- `Actualiser le diagnostic`
- si anciennes restaurations : `Nettoyer N restauration(s) de test`
- `Reconstruire proprement dans Santé` reste désactivé tant que l’audit n’autorise pas la reconstruction.

## Nouveau bug / dette produit LIVE constaté le 2026-09-12

L’utilisateur a effectué un nouveau tour à vélo, correctement enregistré comme Vélo dans le flux live. Observation matérielle :

- l’enregistrement Vélo lui-même semble correct ;
- **aucune confirmation de fin / type d’activité visible sur la Watch** ;
- sur iPhone, une UI demande de confirmer l’activité mais l’utilisateur ne voit **aucun bouton/action claire permettant de confirmer le type avant de fermer** ;
- cela peut être une ancienne surface devenue incohérente, un chemin post-session distinct du `finishReview`, ou un bouton manquant/masqué ; **cause non encore identifiée** ;
- ne pas empiler de patch avant d’identifier précisément la vue et le chemin d’état utilisés sur iPhone et Watch ;
- audit futur à faire de toutes les surfaces de fin : `WatchActiveWorkoutView`, `ActivityProductContainerView`, `PostActivitySummaryView`, `ActivityReviewCard` / `SessionReviewTimeline`, et tout ancien chemin de confirmation encore monté ;
- objectif futur : une seule sémantique de fin, identique iPhone/Watch, aucune étape fantôme, aucune demande de confirmation sans action possible.

L’exact SHA du build utilisé pendant ce tour live n’est pas explicitement confirmé dans le chat ; ne pas l’attribuer à `707236...` sans vérification.

## Architecture active

- LIVE : Watch reste l’autorité HealthKit, avec `HKWorkoutSession` + `HKLiveWorkoutBuilder`.
- reconstruction HISTORIQUE : iPhone uniquement.
- la Watch ne doit plus proposer un deuxième système actif de correction historique.
- une relecture `HKHealthStore` n’est pas une validation Santé/Forme.

## Ce qui est validé

- raw/preflight de la session ;
- pipeline exact-SHA ;
- v3 : création physique de workout Vélo visible dans Santé/Forme ;
- v3 : route et effort relus via HealthKit, mais non visibles dans Forme ;
- audit raw Watch+iPhone réalisé sans mutation ;
- v4 code `70723649...` : CI verte intégrale ;
- l’utilisateur indique avoir installé la nouvelle IPA v4, identité exacte de l’artifact à revérifier si nécessaire.

## Ce qui n’est PAS encore validé

- diagnostic v4 affiché physiquement sur l’iPhone ;
- compte exact d’anciennes restaurations vu par v4 ;
- compteurs raw distance Watch/iPhone vus par v4 ;
- nettoyage physique des deux restaurations de test ;
- vérification après nettoyage : zéro restauration de test et aucune suppression collatérale ;
- résolution du conflit `summary 2.801 km` vs valeur ~`0.99 km` observée précédemment dans une surface de l’app ;
- reconstruction v4 physique ;
- carte visible dans Forme ;
- effort visible dans Forme ;
- workflow live/post-session de confirmation iPhone + Watch.

## Règles de test matériel

- **ne pas reconstruire tant que v4 signale une restauration de test existante** ;
- ouvrir d’abord `Récupération` et relever tout le diagnostic ;
- ne nettoyer que si l’UI confirme que les objets ciblés sont bien des restaurations de test de la session ;
- après nettoyage, vérifier Santé/Forme avant toute nouvelle reconstruction ;
- une seule tentative par nouveau candidat ;
- ne jamais conclure au succès sur le seul statut interne de l’app ;
- ne pas utiliser l’ancien système `Corriger le sport` pendant le diagnostic.

## Règle PowerShell / workflow utilisateur

L’utilisateur ne veut plus de gros blocs PowerShell interactifs multilignes qui restent bloqués sur le prompt `>>`.

- privilégier les scripts `.ps1` existants ;
- donner une commande courte à la fois ;
- éviter les gros blocs `& { ... }` ;
- attendre la sortie avant l’étape suivante ;
- conserver `UPDATE_WATCH_SENSOR_LAB.ps1` comme workflow exact-SHA normal.

## Prochaine étape exacte

1. Sur l’iPhone avec la nouvelle IPA : ouvrir `Récupération`.
2. Ne toucher ni `Reconstruire proprement dans Santé` ni au nettoyage immédiatement.
3. Sur la carte de session `1789141684582`, attendre le diagnostic automatique ou toucher `Actualiser le diagnostic`.
4. Relever exactement : `Résumé`, `GPS Watch`, `GPS iPhone`, `Route`, géométrie W/iPhone, `Compteur raw Watch`, `Compteur raw iPhone`, gaps actifs, `Restaurations HealthKit`, et le statut final.
5. Ensuite seulement décider du nettoyage ciblé des restaurations de test.
6. Après validation/nettoyage du chantier historique, ouvrir un sous-chantier séparé pour la fin de séance live iPhone/Watch et supprimer les UI de confirmation incohérentes ou legacy.

## Éléments à ne pas modifier

- raw session `1789141684582` ;
- snapshot/ZIP/manifest incident ;
- architecture LIVE Watch sans chantier spécifique ;
- exact-SHA pipeline ;
- autres workouts HealthKit non concernés ;
- stash/sauvegardes locales de l’ancien worktree sans demande explicite.
