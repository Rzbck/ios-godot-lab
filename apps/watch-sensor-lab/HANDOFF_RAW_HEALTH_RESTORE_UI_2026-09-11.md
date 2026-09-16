# HANDOFF — Historical HealthKit Restore — final candidate — 2026-09-12

## Objectif

Restaurer une dernière fois la session Tracker brute `1789141684582` comme `cycling` / Vélo dans Apple Santé/Forme, sans altérer les raw, sans doublon, sans faux raccord GPS, et avec une distance/effort réellement interprétés par HealthKit comme attendu.

Ce HANDOFF est la reprise autoritaire de ce chantier. Les anciens détails volatils dans les précédentes versions de ce document sont remplacés par l’état ci-dessous. Toujours revérifier Git/CI/appareil avant mutation.

## Dépôt / worktree / branche

- dépôt : `Rzbck/ios-godot-lab`
- worktree Windows : `E:\_Project\IOS APP\ios-godot-lab\worktrees\watch-healthkit-historical-unification`
- branche : `fix/watch-healthkit-historical-unification-20260912`
- dernier build physiquement testé avant le candidat final : `f9b4f102e85fbf89ef0a9506bd9aa17b3620833f`
- CI de `f9b4...` : run `34706007709`, succès complet
- **ne jamais confondre CI verte et validation Santé/Forme physique**

### Règle utilisateur impérative — IPA

À chaque nouveau SHA candidat prêt à tester :

1. vérifier que sa CI exacte est complètement verte ;
2. **donner immédiatement à l’utilisateur la commande updater/IPA exact-SHA, avant toute autre manipulation** ;
3. ne jamais attendre que l’utilisateur réclame l’IPA ;
4. utiliser le workflow normal existant :

```powershell
.\apps\watch-sensor-lab\UPDATE_WATCH_SENSOR_LAB.ps1 -ExpectedBranch "fix/watch-healthkit-historical-unification-20260912" -OpenFolder
```

Le script doit rester la voie normale : fast-forward de la branche, résolution/build exact HEAD, téléchargement via `gh`, vérification SHA/métadonnées, puis ouverture de l’IPA pour iLoader.

## Session incident gelée — ne jamais modifier les raw

- session : `1789141684582`
- activité réelle : `cycling` / Vélo
- début : `2026-09-11T15:48:04Z`
- fin : `2026-09-11T16:28:25Z`
- durée active : `838.8637968301773 s`
- distance Tracker : `2801.3859133812175 m`
- énergie active : `163.46184575168397 kcal`
- FC moyenne : `141.9047936085219 bpm`
- D+ : `57.109818596908674 m`
- D- : `64.02989046631959 m`
- GPS Watch raw : 344 points
- GPS iPhone raw : ~514/515 points selon lecture/déduplication
- 4 pauses Watch reconstruites
- snapshot incident : `E:\_Project\IOS APP\_Analysis\watch-sensor-lab\incident-post-correction-20260911-220227`
- ZIP SHA-256 : `269AB9E727AA62BCC202594DE33F994902B936C555D0C407DCC2BA56D01C45B0`
- manifest SHA-256 : `7FF9907FB8BE4FFC42892F512090FEF65233ED3AFF05865063A59B701FA4EB86`

Ne jamais modifier/supprimer le snapshot ou les raw Tracker.

## Workouts réels à ne jamais supprimer

Deux sorties Vélo live valides sont hors cible du chantier :

- session `1789198788819`, UUID `71536652-B018-4A94-9E1A-2246E7DB11B6`
- session `1789196258375`, UUID `BAEABB89-8959-4E19-B518-7615A341B992`

Tout nettoyage historique doit rester `raw_restoration=true` + session ID exact `1789141684582`.

## Ce que le forensic USB a réellement appris

L’API locale `wsl_diag_v1` via USB/usbmux est validée physiquement et reste strictement lecture seule.

Sur le raw, la grosse anomalie GPS est visible autour de `14:24Z–14:28Z` :

- Watch : ~`1874.9 m` de géométrie pour ~`386.4 m` de compteur ;
- iPhone : ~`1875.5 m` de géométrie pour ~`391.3 m` de compteur ;
- les deux sources partent donc ensemble sur une géométrie incohérente ;
- les fenêtres sont diagnostiquées `bridge_outside_counter_budget` ;
- le compteur Watch final `2801.39 m` reste l’autorité scalaire fiable.

L’outil forensic expose les raw : le fait qu’il continue d’afficher ces fenêtres après filtrage est normal et ne signifie pas que la route finale les écrit telles quelles.

## Historique des reconstructions utiles

### v3 `3e955e978198bbf33db0797a6df3c74479254389`

- workout Vélo visible physiquement ;
- HealthKit relisait route + effort ;
- Forme n’affichait pas correctement carte/effort ;
- plusieurs restaurations de test avaient été accumulées : cette méthode ne doit pas être réactivée comme chemin concurrent.

### v4 riche / avant filtre agressif — exemple `bb76abddeebbdbf91f480eefb4cf543cd33ca031`

Audit typique :

- Watch filtré ~321 points ;
- iPhone filtré 506 points ;
- route choisie ~443 points, `WATCH+IPHONE` ;
- géométrie ~3854 m ;
- visuellement, la reconstruction était nettement plus complète que le candidat `f9b4`, mais gardait un grand raccord/segment rouge faux.

**Le point important donné par l’utilisateur : ces versions étaient bien meilleures ; le problème principal à corriger était le grand raccord rouge, pas de supprimer la moitié de la route.**

### `f9b4f102e85fbf89ef0a9506bd9aa17b3620833f` — échec produit malgré audit interne vert

Avant écriture :

- `watch_filtered_points = 125`
- `chosen_points = 253`
- `selected_geometry_m = 1977.875 m`
- `severe_route_counter_conflict = False`
- `can_reconstruct = True`

Une reconstruction Vélo avec effort `3/10` a été créée. API après écriture :

- `internally_verified = True`
- `generated_workouts = 1`
- `normal_workouts = 0`
- type HealthKit raw `13` / `cycling`
- effort sample relu `3`
- brand forcé absent

Mais validation physique utilisateur dans Forme/Santé : **ÉCHEC PRODUIT** :

- Forme affiche `Vélo (plein air) : 0,99 KM` au lieu de ~`2,80 km` ;
- un grand segment droit rouge faux reste visible ;
- la route est beaucoup plus pauvre/pointillée que les meilleures reconstructions précédentes ;
- l’effort `3/10` n’est pas visible côté produit ;
- l’utilisateur ne voit plus l’identification/logo de l’application comme auparavant.

Les captures utilisateur font autorité. `internally_verified=True` ne valide jamais le rendu produit.

## Cause racine probable de la distance 0,99 km

La v4 `f9b4` écrit la distance totale `2801.39 m` comme **un seul `HKQuantitySample` couvrant tout le temps mur** de la séance, alors que le workout contient ~26 minutes de pauses et seulement ~839 s actives.

Apple documente que les statistiques d’activité HealthKit ne gardent que la portion d’un quantity sample qui tombe dans la plage temporelle de l’activité et interpolent un sample qui la dépasse. Le rapport `838.86 / ~2421` appliqué à `2801 m` donne environ `0.97 km`, quasiment exactement les `0.99 km` affichés par Forme.

Le dernier candidat doit donc écrire les totaux connus uniquement sur les intervalles actifs et vérifier **les statistiques du workout HealthKit**, pas seulement la somme des samples générés.

## Cause du grand segment rouge / stratégie finale

Le filtre `f9b4` a supprimé trop de coordonnées pour essayer de rendre la géométrie sûre. Cela a dégradé la carte sans garantir l’absence de raccord droit entre deux morceaux restants.

Stratégie finale :

- revenir à la sélection de route plus riche pré-`f9b4` ;
- garder le débruitage local et le remplissage secondaire uniquement des vrais trous raw ;
- **ne plus supprimer des minutes entières après pause** ;
- détecter un raccord actif physiquement impossible ;
- à cet endroit, conserver les coordonnées des deux côtés mais créer **deux `HKWorkoutRoute` indépendantes** associées au même workout ;
- ne jamais fabriquer/interpoler une coordonnée entre les deux ;
- métadonnées de route : index + nombre total de segments + UUID externe unique par segment ;
- relecture durable de tous les segments créés.

Le but est de garder la meilleure reconstruction existante tout en supprimant le trait droit artificiel.

## Correctifs du candidat final

Le candidat final doit combiner, en une seule tentative :

- route riche + segmentation des raccords impossibles ;
- distance et énergie réparties sur les intervalles actifs, total exact conservé ;
- assertion `HKWorkoutBuilder.statistics(for:)` avant finish ;
- relecture `HKWorkout.statistics(for:)` après finish, distance attendue ~`2801.39 m` ;
- effort Apple via relation workout-level (`activity: nil`) et relecture avec le même prédicat ;
- vérification `workout.sourceRevision.source.bundleIdentifier == Bundle.main.bundleIdentifier` ;
- **ne pas remettre `HKMetadataKeyWorkoutBrandName`** : l’ancien brand forcé faisait apparaître `Watch Tracker` à la place du type Vélo ;
- garder type HealthKit `cycling` / raw 13 ;
- nettoyage exact-session uniquement ;
- aucun changement du live Watch `HKLiveWorkoutBuilder` ;
- Diagnostic API toujours lecture seule.

Concernant l’icône visible dans Santé/Forme : la source HealthKit est attribuée par HealthKit à l’app qui écrit le workout. Le candidat final vérifie le bundle source réel. Ne pas falsifier un brand pour simuler une attribution visuelle.

## État Santé avant la prochaine tentative

La restauration ratée `f9b4` doit être nettoyée **avant** toute écriture du candidat final. Ne jamais empiler une nouvelle restauration.

Préflight obligatoire via :

```powershell
.\apps\watch-sensor-lab\WSL.ps1 recovery 1789141684582
```

Avant d’autoriser `Reconstruire proprement dans Santé`, attendre :

- `generated_workouts = 0`
- `normal_workouts = 0`
- raw toujours présents

Si `generated_workouts = 1`, utiliser une seule fois l’action UI `Nettoyer 1 restauration(s) de test`, puis relancer l’audit.

## Validation finale attendue

Une seule reconstruction du candidat final, puis :

1. WSL doit montrer type `cycling`, une seule restauration, effort choisi, source app, distance workout HealthKit ~`2.80 km` ;
2. Forme/Santé doivent afficher physiquement ~`2.80 km`, Vélo, FC/calories cohérentes ;
3. carte : pas de grand raccord rouge artificiel ; les vrais trous/données GPS manquantes peuvent rester pointillés ;
4. effort choisi doit être visible côté produit si Apple le rend pour cette reconstruction ;
5. vérifier l’attribution/source visuelle de l’app ;
6. si cette tentative échoue encore, **ne pas créer une autre restauration** : conserver le résultat, nettoyer uniquement sur décision explicite et clôturer l’incident avec la limite constatée.

## Pipeline / commandes

Updater IPA exact-SHA normal :

```powershell
.\apps\watch-sensor-lab\UPDATE_WATCH_SENSOR_LAB.ps1 -ExpectedBranch "fix/watch-healthkit-historical-unification-20260912" -OpenFolder
```

Audit USB :

```powershell
.\apps\watch-sensor-lab\WSL.ps1 recovery 1789141684582
```

## À ne pas modifier

- raw / snapshot / ZIP / manifest de `1789141684582` ;
- workouts réels listés plus haut ;
- live Watch / `HKLiveWorkoutBuilder` hors chantier séparé ;
- pipeline exact-SHA updater + iLoader ;
- autres applications/dépôts du projet ;
- stash de l’ancien worktree sans demande explicite.

## Après ce chantier

Une fois cette dernière tentative historique validée ou définitivement classée, passer au chantier produit suivant : synchronisation/fin de séance iPhone+Watch, UI de confirmation, mode Auto, puis réutiliser les enseignements compteur/GPS/segmentation dans le tracking live sans copier aveuglément le code historique.
