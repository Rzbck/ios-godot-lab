# HANDOFF — Cloud Weight Lab V13 WIP

## Objectif actuel

Application iPhone temps réel qui segmente les nuages, suit des régions persistantes et estime leur masse.

Priorités actuelles :

1. retrouver la finesse de segmentation et la stabilité visuelle des anciennes bonnes versions ;
2. éviter les gros « pâtés » / fusions de nuages distincts ;
3. contenir les faux positifs sans rogner les vrais contours ;
4. tracking stable et IDs cohérents ;
5. latence réelle < 30 ms sur iPhone 13 mini ;
6. conserver le workflow collecte longue durée + ZIP diagnostic + exact-SHA IPA.

Ne jamais confondre compilation/CI, IPA générée, installation iLoader et validation physique iPhone.

## Dépôt / worktree / branche

- dépôt : `Rzbck/ios-godot-lab`
- app : `apps/cloud-weight-lab`
- branche active : `fix/cloud-weight-twilight-autosync-v12-20260927`
- worktree Windows attendu : `E:\_Project\IOS APP\ios-godot-lab\worktrees\cloud-weight-twilight-autosync-v12`
- `main` hors chantier
- base V11 historique : `c69a673e9dc00355ae744a651341ae5379c9029f`
- dernier build terrain V12 avec collecte persistante : `a9ffaca0fe557b59a09526fdc704a9725cf69f7e`
- **checkpoint code V13 courant avant le commit documentaire de ce HANDOFF** : `978aa8337ba3b6ead8f127df1150deb691f473ad`
- commit code : `feat(cloud-weight-lab): refine dense cloud fields for v13`

À la reprise, vérifier immédiatement branche, HEAD, git status local, dernier run CI et artifact exact-SHA. Le commit contenant ce HANDOFF sera nécessairement postérieur au checkpoint code `978aa833...`.

## Version au checkpoint `978aa833...`

- app : `0.13.0`
- build : `13`

## État CI actuel — IMPORTANT

GitHub Actions :

- run : `36610852240` (#153)
- SHA : `978aa8337ba3b6ead8f127df1150deb691f473ad`
- branche : `fix/cloud-weight-twilight-autosync-v12-20260927`
- conclusion : **FAILURE**
- job : `109551583813`
- étapes Core ML : SUCCESS
- génération projet Xcode : SUCCESS
- étape `Compile app and unit tests for simulator` : **FAILURE**
- build device : SKIPPED
- package IPA : SKIPPED
- upload artifact : SKIPPED

**Il n'existe donc pas encore d'IPA V13 valide pour `978aa833...`.**

Ne jamais dire que V13 est compilée ou testée tant qu'un nouveau SHA n'a pas une CI complète SUCCESS et un artifact exact-SHA.

## Pourquoi V13 a été créée

Les tests physiques récents ont montré une forte régression de qualité par rapport aux anciennes bonnes versions :

- gros blocs/fusions au lieu de contours détaillés ;
- plusieurs structures nuageuses réunies en une seule région ;
- instabilité du masque / changements brusques ;
- faux positifs ;
- classification parfois stale (ex. un track initialement Cumulus reste Cumulus alors que sa région grossit fortement) ;
- performance qui se dégrade quand la couverture nuageuse devient très grande.

Le pack terrain `a9ffaca0...` avait confirmé notamment :

- forte proportion de frames couvertes avec 1 seul composant géant ;
- corrélation très forte entre couverture et coût de post-traitement ;
- refresh SegFormer associé à davantage de changements de masque / créations de tracks ;
- comportement terrain collecte multi-ouvertures et récupération ZIP validé physiquement.

## Changements V13 au checkpoint `978aa833...`

### Segmentation / géométrie

`CloudAnalyzer.swift` a été refactoré pour :

- utiliser une connectivité 4-voisins au lieu de ponts diagonaux 8-voisins ;
- cleanup cardinal qui ne remplit plus les gaps diagonaux ;
- calculer aire/statistiques pendant l'extraction sans conserver un énorme tableau de pixels par composant ;
- détecter les composants denses et variables via `probabilityStdDev` ;
- tenter de découper un gros composant à partir de plusieurs noyaux UCloudNet haute confiance séparés ;
- reconstruire les labels après split ;
- échantillonner les statistiques couleur au lieu de reparcourir chaque pixel de gros composants ;
- classifier avec couverture + aspect + fill + variance UCloudNet + variance de luminosité ;
- traiter un champ très couvrant comme Stratus/Stratocumulus plutôt qu'un énorme Cumulus.

### Stabilisation sémantique

Le cache SegFormer reste asynchrone. V13 ajoute un lissage seulement lorsque la différence de carte sémantique est faible ; les gros changements de scène sont appliqués immédiatement pour éviter de mélanger une vieille carte avec une nouvelle vue caméra.

### Tracking / type

`CloudTemporalStabilizer.swift` :

- rejette comme continuité un match où une petite région est soudain absorbée dans une très grosse région ;
- détecte les changements majeurs de géométrie ;
- raccourcit fortement l'hystérésis de type lors d'un changement géométrique majeur ;
- changement immédiat de type lors du passage d'un objet discret vers une large couche afin d'éviter le « giant stale Cumulus » observé sur le terrain.

### Masse

`CloudMassEstimator.swift` conserve l'estimateur angle-aware, mais baisse la confiance physique pour les régions très couvrantes : une couche de ciel couvert peut être visible, mais ne doit pas être présentée avec la même confiance qu'un nuage discret.

### Tests ajoutés/modifiés

Des cas de tracking couvrent notamment la croissance importante de couverture afin d'éviter qu'un Cumulus stale reste affiché après transformation en grande couche.

Attention : le workflow actuel compile la cible XCTest avec `build-for-testing`; il ne faut pas parler de tests exécutés tant qu'ils ne sont pas réellement lancés.

## État historique / branches à ne pas confondre

Une branche d'essai `fix/cloud-weight-legacy-quality-v12-20260929` existe avec le SHA `c1ce3f932d40040c3327071b13853ba2eeb507cb` et le run #152 en échec. Elle servait à un replay historique V8/V11/SkyWater, mais **ce n'est pas le chantier actif actuel**.

Ne pas revenir automatiquement dessus ni présenter son état comme celui de la branche V13 actuelle.

## Pipeline exact-SHA à conserver

Workflow normal :

1. modifier uniquement la branche active dédiée ;
2. commit/push ;
3. GitHub Actions exact-SHA ;
4. seulement si CI complète SUCCESS : récupérer l'artifact via `apps/cloud-weight-lab/UPDATE_CLOUD_WEIGHT_LAB.ps1` ;
5. installer l'IPA avec iLoader ;
6. valider physiquement sur iPhone ;
7. récupérer les diagnostics avec `SYNC_CLOUD_WEIGHT_SESSION.ps1 -AnalysisPack`.

Le script updater existant doit rester le workflow normal. Ne pas inventer un second downloader concurrent.

## Collecte terrain validée à conserver

Le système de collection persistante introduit à `a9ffaca0...` est important et ne doit pas être cassé :

- plusieurs ouvertures/fermetures/verrouillages de l'app rejoignent la même collection ;
- segments persistants ;
- récupération finale en un seul `ANALYSIS-PACK-collection-....zip` ;
- récupération d'une session interrompue validée sur un test terrain d'environ 98 minutes ;
- lifecycle background/active et reset tracking/overlay déjà intégrés.

## Ce qui est validé

- workflow exact-SHA historique ;
- collecte multi-segments et ZIP terrain sur `a9ffaca0...` ;
- modèle terrain ayant fourni des diagnostics exploitables ;
- changements V13 présents dans Git au checkpoint `978aa833...` ;
- compilation/build des modèles Core ML dans la CI #153.

## Ce qui n'est PAS validé

- compilation Swift V13 ;
- build device V13 ;
- IPA V13 ;
- installation V13 ;
- finesse de segmentation V13 sur iPhone ;
- stabilité V13 ;
- faux positifs V13 ;
- performance V13 <30 ms ;
- thermique longue durée V13 ;
- tests XCTest réellement exécutés.

## Prochaine étape EXACTE

1. Vérifier HEAD réel de `fix/cloud-weight-twilight-autosync-v12-20260927` et ne pas supposer qu'il est encore `978aa833...` après le commit HANDOFF.
2. Ouvrir le log du job GitHub Actions `109551583813`, run #153, et extraire la/les erreur(s) Swift de l'étape `Compile app and unit tests for simulator`.
3. Corriger **uniquement** l'erreur de compilation ; ne pas modifier la géométrie/segmentation V13 tant qu'elle n'a pas été testée physiquement.
4. Commit/push sur la même branche dédiée.
5. Attendre une CI complète SUCCESS : compile simulator/test target + build device + contract + package IPA + artifact exact-SHA.
6. Mettre à jour ce HANDOFF avec le nouveau SHA/run/artifact.
7. Utiliser `UPDATE_CLOUD_WEIGHT_LAB.ps1 -OpenFolder`, puis iLoader.
8. Test physique ciblé :
   - ciel avec plusieurs petits/moyens nuages séparés ;
   - ciel très couvert/complexe ;
   - arbres/bâtiments/route/intérieur pour faux positifs ;
   - mouvements de caméra + portrait/paysage ;
   - vérifier stabilité des contours et IDs ;
   - vérifier que plusieurs structures ne deviennent plus un seul gros pâté ;
   - mesurer analyse P50/P95 et thermique.
9. Récupérer un seul ZIP avec :

```powershell
& {
    $W = 'E:\_Project\IOS APP\ios-godot-lab\worktrees\cloud-weight-twilight-autosync-v12'
    Set-Location $W
    .\apps\cloud-weight-lab\SYNC_CLOUD_WEIGHT_SESSION.ps1 `
        -KeepFrames `
        -AnalysisPack `
        -OpenFolder
}
```

10. Comparer V13 au pack terrain précédent avant tout nouveau changement de seuil/modèle.

## À ne pas modifier

- `main` ;
- autres apps du dépôt ;
- pipeline exact-SHA / updater / iLoader ;
- collecte persistante déjà validée ;
- estimateur angle-aware hors correction prouvée ;
- seuils/modèles au hasard ;
- pas de merge/release sans accord utilisateur.

## Critères de sortie

Le chantier n'est pas prêt tant que :

- CI exact-SHA complète SUCCESS ;
- IPA exact-SHA récupérable ;
- segmentation physiquement détaillée et stable ;
- plus de fusion massive systématique des nuages complexes ;
- faux positifs contenus ;
- tracking stable ;
- latence réelle mesurée sur iPhone idéalement <30 ms ;
- thermique acceptable ;
- validation matérielle explicitement documentée.
