# HANDOFF — Cloud Weight Lab V12 WIP

## Objectif

Application iPhone temps réel qui segmente les nuages, suit des régions persistantes et estime leur masse avec une géométrie angle-aware.

Priorités actuelles, dans cet ordre de contrainte :

1. **latence totale réelle < 30 ms sur iPhone** — priorité haute ;
2. tracking stable, réactif et conservation des IDs ;
3. segmentation précise des vrais nuages ;
4. suppression des faux positifs route/sol/voitures/arbres/bâtiments/écran/edges ;
5. stabilité thermique et cadence élevée ;
6. diagnostic/sync rapide, compact et exploitable.

Ne pas considérer V12/V13 satisfaisante tant que le `<30 ms` n'est pas **mesuré physiquement sur iPhone**. Ne jamais confondre compilation/CI avec validation matérielle.

## Dépôt / worktree / branche

- dépôt : `Rzbck/ios-godot-lab`
- app : `apps/cloud-weight-lab`
- branche : `fix/cloud-weight-twilight-autosync-v12-20260927`
- worktree Windows attendu : `E:\_Project\IOS APP\ios-godot-lab\worktrees\cloud-weight-twilight-autosync-v12`
- base V11 : `c69a673e9dc00355ae744a651341ae5379c9029f`
- **checkpoint code courant avant le commit documentaire de ce HANDOFF** : `087c9612a1d375d8a7bb4a54b3784113dde913ef`
- commit code : `fix(cloud-weight-lab): restore tracking continuity`
- `main` reste hors chantier.

Le commit contenant ce HANDOFF est nécessairement postérieur au checkpoint code ci-dessus. À la reprise, vérifier `branch`, `HEAD`, `git status`, dernier run CI et artifact exact-SHA avant toute modification.

## Version

- app : `0.12.0`
- build : `12`

Toujours vérifier contre le HEAD réel avant installation.

## CI du checkpoint code `087c9612...`

GitHub Actions :

- run : `36390974274` (#119)
- SHA : `087c9612a1d375d8a7bb4a54b3784113dde913ef`
- conclusion : **SUCCESS**
- artifact exact-SHA : `cloud-weight-lab-087c9612a1d375d8a7bb4a54b3784113dde913ef`
- artifact ID : `10956616649`
- taille : `7,617,905` bytes
- digest : `sha256:1dd0db387d4740e263a23b3cace656c478603703f6efb844105b3ca70b869f3e`

Le workflow utilise `build-for-testing` : la cible XCTest est **compilée mais pas exécutée**. Ne jamais écrire « tests passés » pour ce run.

## Pipeline exact-SHA à conserver

Workflow normal :

1. commit/push sur la branche V12 ;
2. GitHub Actions exact-SHA ;
3. `apps/cloud-weight-lab/UPDATE_CLOUD_WEIGHT_LAB.ps1` attend la CI si nécessaire, récupère l'artifact du HEAD exact et vérifie SHA/métadonnées ;
4. installation IPA avec iLoader ;
5. validation physique iPhone ;
6. `SYNC_CLOUD_WEIGHT_SESSION.ps1` pour récupérer la session exacte.

Ne pas remplacer ce pipeline par un second workflow concurrent.

## État fonctionnel actuel

### Sync diagnostic active sans fermer l'app — implémenté et validé

Le workflow manuel fermeture/réouverture a été supprimé.

Si la session sélectionnée est encore `recording` :

- le script appelle l'API `/api/v1/sessions/{id}/seal` ;
- l'iPhone termine la session active ;
- une nouvelle session démarre immédiatement ;
- le PC télécharge l'ancienne session devenue immuable.

Ce comportement a été validé physiquement sur les builds précédents : les sessions récupérées arrivent `completed`, avec compteurs telemetry/events/visual cohérents et `SYNC = OK + VALIDÉ`.

Le token API reste persistant via Keychain côté iPhone et fichier d'état côté Windows ; pas de bouton API à presser.

### Garde sémantique

- UCloudNet reste le détecteur de nuages.
- SegFormer ADE20K sert de couche anti-faux-positifs.
- `blocker_probability` inclut maintenant les classes négatives importantes ajoutées dans V12 : bâtiments, arbres, personnes, plantes, murs, sol/floor, route, herbe, trottoir, terre et voitures.
- Le garde ciel utilise hystérésis + fallback twilight/low-light.
- `sky_probability` n'est plus un veto absolu.

### Géométrie / faux positifs sous horizon

`CloudMassEstimator` ne transforme plus une détection clairement sous l'horizon en énorme nuage en clampant silencieusement son élévation vers `+3°` : une région clairement sous l'horizon avec motion fiable est rejetée pour l'estimation de masse.

Important : le masque visuel de segmentation peut rester visible pour diagnostic même si la géométrie rejette toutes les masses. Ceci permet de tester une image de nuages affichée sur un écran sans réintroduire de faux poids physiques.

### Tracking

Checkpoint `087c9612...` :

- `CloudTemporalStabilizer.maximumMisses = 3` ;
- un track peut donc survivre à trois analyses manquées et retrouver son ID ;
- le quatrième miss le détruit ;
- objectif : éviter les IDs recréés en permanence lors de trous courts de segmentation.

Cette modification est **CI validée mais pas encore validée physiquement** au moment de ce HANDOFF.

### Blocker / contours

Le premier élargissement sémantique utilisait un max-filter `radius: 2`, efficace contre certains halos/faux positifs mais trop agressif sur les bords de vrais nuages.

Checkpoint `087c9612...` :

- blocker max-filter ramené à `radius: 1` ;
- les classes road/car/ground/etc. restent présentes ;
- objectif : conserver la protection anti-sol tout en récupérant les contours de vrais nuages.

Cette modification est **CI validée mais pas encore validée physiquement**.

## Dernière session matérielle analysée

Dernier build réellement analysé physiquement avant `087c9612...` :

- SHA : `17fb26cde17edc4a26846fdcd305d2a97a1e0817`
- session : `session-1790579143015-17fb26cd`
- état : `completed`
- telemetry : `2647 / 2647`
- events : `107 / 107`
- visual : `245 / 245`
- vidéo diagnostic créée ; sync complète.

Observations :

- gros faux positifs route/sol nettement mieux contrôlés que la V12 précédente ;
- blocker `radius: 2` trop agressif sur certains vrais contours ;
- tracking fonctionnel mais IDs encore trop facilement recréés lors de trous courts ;
- vidéo diagnostic beaucoup plus compacte que l'ancienne, mais une petite fin noire/inutile restait ;
- pas de régression de performance mesurée sur ce test.

## Performance matérielle connue

### Ancienne V10

Baseline ancienne : environ `31–35 ms` dans certaines sessions, ~`25–30 Hz`, mais cette baseline ne contenait pas le SegFormer actuel à chaque analyse et n'est donc pas directement comparable au pipeline V12 actuel.

### V12 récente, build `17fb26cd...`

Sur les portions où l'IA tourne réellement :

- analyse complète typique : ~`77–82 ms` ;
- cadence observée : ~`11–12 Hz` ;
- UCloudNet : ~`18–20 ms` ;
- SegFormer / sky semantic : ~`67–71 ms` ;
- exécution parallèle confirmée quand thermique nominal/fair ;
- la latence murale est dominée par SegFormer ;
- cette session n'a pas reproduit le passage `thermalState = serious` observé sur une session précédente.

**Conclusion performance : la cible `<30 ms total` n'est PAS atteinte.**

### Priorité optimisation suivante

Après validation physique de `087c9612...`, travailler explicitement sur le coût SegFormer sans casser la précision :

- mesurer P50/P95 des timings sur scène utile ;
- envisager cadence sémantique plus basse que UCloudNet avec cache/reprojection du masque sémantique ;
- évaluer une résolution d'entrée SegFormer inférieure ;
- évaluer un modèle sémantique plus léger si nécessaire ;
- conserver UCloudNet à cadence plus haute ;
- mesurer CPU/GPU/thermal et dropped/throttled frames avant/après ;
- ne pas annoncer `<30 ms` avant mesure iPhone réelle.

Ne pas simplement remonter/baisser des seuils pour masquer le problème de performance.

## Diagnostic visuel compact

Le recorder a été modifié pour ne plus capturer systématiquement 1 frame/s pendant les périodes inutiles.

La capture visuelle est maintenant orientée vers :

- détections validées ;
- masque cloud sémantiquement pertinent ;
- changements importants de masque ;
- transitions/événements utiles.

Checkpoint `087c9612...` ajoute encore :

- un burst n'est plus suffisant à lui seul pour créer une frame ;
- une frame semantic nécessite aussi un minimum de ciel ;
- la construction MP4 exclut les events seuls sans cloud/ciel pertinent.

But : éviter les longues fins noires et réduire fortement le temps d'analyse des diagnostics.

Cette dernière amélioration doit encore être validée sur la prochaine session `087c9612...`.

## Ce qui est validé

- branche/workflow exact-SHA ;
- CI complète SUCCESS sur `087c9612...` ;
- artifact exact-SHA présent ;
- compilation app + cible XCTest ;
- build device / package / IPA ;
- auto-seal sync sans fermeture manuelle validé sur matériel sur builds précédents ;
- récupération session complète et cohérente ;
- pipeline diagnostic exploitable ;
- segmentation/semantic blocker améliorés par rapport aux premières V12 sur les faux positifs sol/route.

## Ce qui n'est PAS encore validé

- comportement physique du checkpoint `087c9612...` ;
- tracking avec `maximumMisses = 3` sur iPhone ;
- blocker `radius = 1` sur vrais nuages/arbres/route ;
- disparition complète des dernières frames noires du diagnostic ;
- performance `<30 ms` ;
- stabilité thermique longue durée avec la future optimisation performance ;
- XCTest réellement exécutés.

## Prochaine étape exacte

1. Vérifier HEAD/worktree/status après ce commit documentaire.
2. Vérifier que l'IPA installée/testée correspond bien au **checkpoint code `087c9612a1d375d8a7bb4a54b3784113dde913ef`**, pas simplement au HEAD documentaire plus récent.
3. Test matériel ciblé :
   - vrais nuages en mouvement ;
   - petits trous de segmentation pour observer conservation de l'ID ;
   - arbres/bâtiments/route/voitures ;
   - bords de nuage contre arbres/horizon ;
   - portrait/paysage et mouvements rapides ;
   - quelques minutes pour thermique/cadence.
4. Sans fermer l'app : lancer `SYNC_CLOUD_WEIGHT_SESSION.ps1`.
5. Analyser `diagnostic-preview.mp4`, `telemetry.ndjson`, `events.ndjson`, `manifest.json`, `SYNC-REPORT.json`.
6. Si tracking/segmentation sont satisfaisants, **attaquer immédiatement la priorité performance `<30 ms total`**, SegFormer étant le goulot dominant.
7. Comparer avant/après avec mesures réelles, puis seulement poursuivre vers V13/finalisation.

## Fichiers à partager après test

- `diagnostic-preview.mp4`
- `telemetry.ndjson`
- `events.ndjson`
- `manifest.json`
- `SYNC-REPORT.json`

Le dossier complet des JPEG n'est normalement pas nécessaire. Demander seulement `visual/visual.ndjson` ou quelques frames précises si une corrélation exacte image/télémétrie est nécessaire.

## Estimation de masse

Conserver l'estimateur angle-aware V11 : FOV + CoreMotion + taille angulaire + priors altitude/profondeur/LWC avec fourchette d'incertitude.

Une caméra RGB seule ne mesure pas directement distance, altitude de base, profondeur 3D ou contenu eau/glace. Ne jamais présenter la masse comme une pesée exacte.

## À ne pas modifier

- `main` ;
- les autres apps ;
- le pipeline exact-SHA / iLoader ;
- le recorder persistant hors corrections diagnostic ciblées ;
- les seuils/modèles au hasard sans données avant/après ;
- aucune release / merge main sans accord explicite utilisateur.

## Critères de sortie

Le chantier n'est pas considéré prêt tant que :

- CI exact-SHA complète SUCCESS ;
- IPA exact-SHA récupérable ;
- sync auto-seal réellement stable ;
- vrais nuages segmentés proprement ;
- faux positifs route/sol/objets fortement contenus ;
- tracking stable sans IDs qui sautent inutilement ;
- diagnostic compact sans longues plages noires/inutiles ;
- **latence totale mesurée sur iPhone < 30 ms ou décision explicite documentée si la cible s'avère physiquement incompatible avec le modèle retenu** ;
- thermique/cadence mesurées ;
- validation matérielle explicitement séparée de la CI.
