# HANDOFF — Cloud Weight Lab V11

## Objectif

Application iPhone temps réel qui segmente les nuages, suit des régions persistantes et estime la masse d'eau/glace condensée. V11 vise deux causes racines mesurées sur V10 : instabilité du type/masse et géométrie trop heuristique.

## Dépôt / branche

- dépôt : `Rzbck/ios-godot-lab`
- app : `apps/cloud-weight-lab`
- branche : `fix/cloud-weight-stability-physics-v11-20260927`
- base V11 : `477647b22a80f1d6c751b282287d1e09ddd69365`
- commit applicatif V11 validé CI : `ef2599e03e2d500035f0e9a1d1e6b7caaae0243f`
- CI du commit applicatif : run `36335724091` — SUCCESS
- le commit qui contient ce HANDOFF/versioning est postérieur au commit applicatif ci-dessus et doit lui aussi être validé exact-SHA avant installation.
- worktree Windows prévu : `E:\_Project\IOS APP\ios-godot-lab\worktrees\cloud-weight-stability-physics-v11`
- `main` reste hors chantier.

## V10 matériel — source du changement

Build V10 physiquement testé : `1a955d01632557f3247bb49c858f8c96f3aeaf27`.

Résultats observés :

- recorder persistant iPhone validé, y compris récupération après interruption ;
- pipeline typique ~31–35 ms, environ 25–30 Hz après suppression du throttle 70 ms ;
- gros IDs de tracks nettement plus stables ;
- même track pouvant encore osciller `Cumulus <-> Stratocumulus`, avec fortes variations de masse parce que les priors changent ;
- garde hors-ciel amélioré ; soleil/reflets/glare restent des cas difficiles ;
- recorder V10 déclenchait trop de bursts (track created/missed) ;
- manifest `interrupted` pouvait conserver des compteurs périmés ;
- thermique observé `nominal -> fair` sur la session d'environ 2 min 22 s.

## V11 — stabilité type / masse

`CloudTemporalStabilizer` :

- changement de type confirmé seulement après 15 observations consécutives au lieu de 3 ;
- tant qu'un nouveau type n'est pas confirmé, son estimation de masse brute n'est pas injectée dans le track stable ;
- lissage masse plus lent que géométrie ;
- un changement de type confirmé converge progressivement au lieu de sauter instantanément ;
- tracking ID / prédiction vitesse / piste cachée pendant un miss restent conservés.

But matériel : vérifier qu'un même nuage ne saute plus en masse à cause de `Cumulus <-> Stratocumulus`.

## V11 — estimation physique angle-aware

`CloudMassEstimator` utilise maintenant :

- FOV horizontal du format caméra actif ;
- CoreMotion / gravity pour estimer l'élévation de l'axe caméra ;
- position du track dans l'image pour l'élévation centrale ;
- projection pinhole des bords de bounding box pour largeur/hauteur angulaires ;
- plage d'altitude du type comme prior de distance ;
- fraction remplie du masque pour l'aire projetée ;
- profondeur probabiliste liée à la taille projetée ;
- plage de contenu en eau/glace condensée pour la masse.

La télémétrie de chaque détection enregistre désormais low/mid/high mass + angle, distance, largeur, hauteur, profondeur, aire projetée, volume et confiance.

IMPORTANT : une seule caméra RGB ne mesure pas directement distance, hauteur de base, profondeur 3D ni contenu en eau. V11 est plus physique et traçable, mais reste une estimation avec incertitude. Ne pas présenter la valeur médiane comme une pesée exacte.

## V11 — recorder

- schema manifest : 2 ;
- baseline image : ~1 fps ;
- burst : ~4 fps, durée ~2.5 s ;
- `track_missed` reste loggé mais ne déclenche plus de burst visuel ;
- `track_created` ne déclenche un burst que si la couverture est significative ;
- mask/glare demandent un seuil plus fort pour le burst ;
- récupération d'une session `interrupted` recompte réellement telemetry/events/visuals et JPEG bytes, puis renseigne `endedAt` à partir des fichiers présents.

Le stockage reste local, borné et exclu de la sauvegarde iCloud. Pas d'upload automatique.

## Version

- version app V11 : `0.11.0`
- build : `11`
- pipeline : `.github/workflows/cloud-weight-lab-build.yml`
- récupération Windows : `apps/cloud-weight-lab/UPDATE_CLOUD_WEIGHT_LAB.ps1`
- synchro session : `apps/cloud-weight-lab/SYNC_CLOUD_WEIGHT_SESSION.ps1`

## Ce qui est validé

Sur `ef2599e03e2d500035f0e9a1d1e6b7caaae0243f` :

- conversion des 3 modèles Core ML : SUCCESS ;
- génération Xcode : SUCCESS ;
- `build-for-testing` simulateur : SUCCESS (cible XCTest compilée, tests NON exécutés) ;
- build iPhone Release unsigned : SUCCESS ;
- contrat bundle et 3 `.mlmodelc` : SUCCESS ;
- package/upload IPA : SUCCESS.

## Ce qui N'EST PAS encore validé

- V11 non testé physiquement ;
- signe/valeur de l'élévation CoreMotion non validés sur iPhone en portrait/paysage ;
- stabilité réelle de type/masse V11 non validée ;
- nouvelles valeurs de masse angle-aware non confrontées à une référence météo ;
- cadence/chauffe V11 non mesurées ;
- réduction effective des bursts V11 non mesurée ;
- XCTest compilés seulement, pas exécutés par CI.

## Test matériel exact

1. Installer l'IPA exact-SHA V11 via le workflow existant + iLoader.
2. Viser un nuage identifiable 20–30 s en gardant le téléphone relativement fixe ; surveiller stabilité ID/type/masse.
3. Garder le même nuage et incliner progressivement le téléphone : la géométrie ne doit pas exploser et la télémétrie `centerElevationDegrees` doit évoluer dans le bon sens.
4. Tester portrait puis paysage.
5. Tester ciel + arbres/bâtiments + soleil/reflets pour non-régression du garde.
6. Faire 2–5 min puis fermer/revenir et synchroniser avec `SYNC_CLOUD_WEIGHT_SESSION.ps1`.
7. Comparer manifest aux nombres de lignes réels et vérifier la baisse des frames `event`.

## Prochaine étape précision

Après validation du signe CoreMotion et de la stabilité V11 : intégrer de façon optionnelle un contexte météo réel pour réduire la plage de hauteur de base (température/point de rosée pour cumulus convectif et/ou données cloud-base/ceilomètre lorsqu'elles existent). C'est cette information externe qui peut réellement resserrer la masse ; la caméra RGB seule ne peut pas résoudre la distance avec précision.

## À ne pas modifier sans nouvelle mesure

- ne pas changer les seuils UCloudNet / sky gate uniquement pour améliorer un cas isolé ;
- ne pas paralléliser les modèles avant d'avoir re-mesuré V11 ; V10 est déjà ~25–30 Hz ;
- ne pas supprimer le recorder local ni le workflow exact-SHA ;
- ne pas modifier `main` ou une autre app du dépôt ;
- ne pas annoncer la masse comme exacte ou physiquement mesurée.
