# HANDOFF — Cloud Weight Lab V14 legacy control

## Objectif

Retrouver une segmentation détaillée et stable sur iPhone après les régressions de fusion en gros « pâtés », tout en conservant le shell moderne : tracking, estimateur de masse, portrait/paysage, diagnostics persistants, ZIP terrain et pipeline IPA exact-SHA.

Priorités :

1. valider physiquement que les nuages distincts redeviennent des régions distinctes ;
2. mesurer stabilité, faux positifs et latence sur iPhone 13 mini ;
3. ne réintroduire aucune logique adaptative/topologique avant comparaison terrain ;
4. conserver le pipeline exact-SHA et la collecte persistante déjà validée.

Ne jamais confondre CI/build, IPA générée, IPA installée et validation physique iPhone.

## Dépôt / branche / worktree

- dépôt : `Rzbck/ios-godot-lab`
- app : `apps/cloud-weight-lab`
- branche active V14 : `fix/cloud-weight-legacy-control-v14-20260930`
- branche de départ : `fix/cloud-weight-twilight-autosync-v12-20260927`
- base de branche V14 : `7978ea414065aca582cffd287ccf500da5c78f62`
- checkpoint code + métadonnées V14 avant ce commit documentaire : `fb2f386887f03a62439d806ce00b94edad0481e5`
- worktree Windows recommandé : `E:\_Project\IOS APP\ios-godot-lab\worktrees\cloud-weight-legacy-control-v14`
- `main` hors chantier

À toute reprise, vérifier `git status`, branche, HEAD réel, dernier run CI et artifact exact-SHA. Le commit contenant ce HANDOFF est nécessairement postérieur à `fb2f386...`.

## Version

- app : `0.14.0`
- build : `14`

## Pourquoi V14

Les packs terrain V13 ont montré que la régression est structurelle : le gate relaxé / fallback pouvait créer des ponts, puis les connected components formaient une grande région. Le split V13 pouvait redistribuer les pixels d'un parent géant entre plusieurs IDs, mais ne recréait pas les vrais espaces entre nuages. Les refreshs du cache SegFormer asynchrone étaient aussi associés à de forts changements de masque.

Le pivot historique est le refactor `1039a7cabe76d239726b7e1bf7d1378c1352aa23` (`route analyzer through adaptive pipeline`).

## Architecture V14 contrôle

`CloudAnalyzer.swift` restaure le cœur legacy V8/V11 :

- UCloudNet portrait/paysage ;
- seuil cloud `0.52` ;
- SegFormer ciel calculé sur la même frame ;
- seuil ciel strict `0.55` ;
- géométrie : `cloud >= 0.52 && sky >= 0.55` ;
- cleanup legacy ;
- connected components legacy ;
- maximum 8 régions ;
- pas de cache SegFormer asynchrone dans la géométrie ;
- pas de relaxed-sky gate ;
- pas de strong-cloud fallback ;
- pas de dense topology splitter / seed redistribution.

Le shell moderne est conservé :

- `CameraService` et lifecycle ;
- `CloudTemporalStabilizer` pour les détections/IDs ;
- estimateur de masse angle-aware ;
- diagnostics / telemetry ;
- collection persistante multi-ouvertures ;
- ZIP `ANALYSIS-PACK` ;
- orientation portrait/paysage ;
- updater exact-SHA + iLoader.

Pour cette build contrôle, l'overlay affiché reprend le contour raw legacy afin que la stabilisation ne puisse pas masquer la géométrie à évaluer.

`LegacyAnalyzerCompatibility.swift` adapte seulement les signatures/télémétries modernes au cœur legacy ; il ne doit pas modifier la géométrie.

## Tests / compilation

Les tests V13 dépendant de fonctions topologiques supprimées ont été remplacés/retirés lorsqu'ils ne correspondaient plus au moteur actif.

Cas de régression ajouté : un pixel de forte probabilité cloud mais sans preuve locale de ciel strict ne doit pas relier deux zones ; le gap doit rester un gap.

Attention : le workflow utilise `build-for-testing`. Il compile l'app et la cible XCTest mais n'exécute pas les XCTest. Ne pas dire « tests passés » sans exécution explicite.

## CI connue

Run de contrôle avant stamp V14 final :

- run : `36705513149` (#160)
- SHA : `bef6d05d3a44b78c41d22d05b75adfeecebb1fff`
- conclusion : **SUCCESS**
- compile simulateur + cible de tests : SUCCESS
- build device non signé : SUCCESS
- vérification bundle : SUCCESS
- package IPA exact-SHA : SUCCESS
- upload artifact : SUCCESS

Le commit `fb2f386887f03a62439d806ce00b94edad0481e5` ajoute uniquement l'identité V14 (`0.14.0`, build `14`) et des métadonnées d'artifact cohérentes avec le moteur legacy. Après ce HANDOFF, vérifier la CI du HEAD documentaire final ; ne jamais réutiliser l'artifact #160 comme artifact final V14 si le HEAD a changé.

## Collecte terrain à préserver

Le système persistant issu de `a9ffaca0fe557b59a09526fdc704a9725cf69f7e` reste intact :

- plusieurs ouvertures / fermetures / verrouillages dans une collection ;
- segments persistants ;
- récupération finale en un ZIP ;
- reprise après interruption déjà validée physiquement ;
- aucun nouveau downloader ou mécanisme concurrent.

## Ce qui est validé

- cœur legacy intégré au shell moderne ;
- compilation simulateur de la build contrôle `bef6d05...` ;
- build device non signé `bef6d05...` ;
- packaging/upload IPA exact-SHA `bef6d05...` ;
- métadonnées V14 présentes dans le checkpoint `fb2f386...` ;
- pipeline exact-SHA historique ;
- collecte persistante historique.

## Ce qui n'est PAS encore validé

- CI complète du HEAD documentaire final ;
- installation de V14 sur iPhone ;
- finesse réelle des contours V14 ;
- disparition des fusions massives V14 ;
- faux positifs V14 ;
- stabilité tracking/IDs V14 ;
- latence réelle V14 sur iPhone 13 mini ;
- objectif < 30 ms ;
- thermique longue durée ;
- XCTest réellement exécutés.

## Prochaine étape exacte

1. Vérifier HEAD réel de `fix/cloud-weight-legacy-control-v14-20260930` et la CI correspondante.
2. Exiger une CI complète SUCCESS du même SHA : simulateur/test target + build device + contract + package + upload.
3. Créer/synchroniser le worktree Windows V14 sans écraser les autres worktrees.
4. Utiliser exclusivement `apps/cloud-weight-lab/UPDATE_CLOUD_WEIGHT_LAB.ps1 -OpenFolder` pour récupérer l'IPA exact-SHA.
5. Installer avec iLoader.
6. Test physique ciblé : plusieurs petits/moyens nuages séparés, ciel très couvert, arbres/bâtiments/route/intérieur, mouvements caméra, portrait/paysage, contours, IDs, latence et thermique.
7. Récupérer le pack terrain avec :

```powershell
& {
    $W = 'E:\_Project\IOS APP\ios-godot-lab\worktrees\cloud-weight-legacy-control-v14'
    Set-Location $W
    .\apps\cloud-weight-lab\SYNC_CLOUD_WEIGHT_SESSION.ps1 `
        -KeepFrames `
        -AnalysisPack `
        -OpenFolder
}
```

8. Comparer V14 aux packs précédents avant toute nouvelle optimisation.

## À ne pas modifier

- `main` ;
- autres apps ;
- pipeline exact-SHA / updater / iLoader ;
- collecte persistante ;
- estimateur de masse sans preuve de régression ;
- seuils `0.52` / `0.55` avant le premier test physique V14 ;
- ne pas réintroduire cache SegFormer async, gate relaxé, fallback fort ou splitter topologique avant validation comparative ;
- pas de merge/release sans accord utilisateur.

## Critères de sortie

Le chantier n'est pas considéré terminé tant que :

- CI exact-SHA complète SUCCESS ;
- IPA exact-SHA récupérable et installée ;
- segmentation détaillée validée physiquement ;
- pas de fusion massive systématique ;
- faux positifs acceptables ;
- tracking/IDs acceptables ;
- latence/thermique mesurées ;
- validation iPhone explicitement documentée.
