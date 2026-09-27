# HANDOFF — Cloud Weight Lab

Date : **2026-09-27**

## Objectif

Application iPhone personnelle qui reconnaît les nuages réellement présents dans le ciel, détoure plusieurs régions, suit les détections temporellement et affiche une estimation pédagogique de masse d'eau/glace condensée.

Priorité V8 : **stabiliser les IDs/labels sans fantômes et transformer le diagnostic en session continue récupérable depuis Windows, avec télémétrie incrémentale et séquence d'images légère permettant d'analyser réellement le mouvement**.

## Identité chantier

- repository : `Rzbck/ios-godot-lab` ;
- application : `apps/cloud-weight-lab` ;
- branche active : `fix/cloud-weight-tracking-live-diag-v8-20260927` ;
- base V8 : `f6a7c6fc06abcf8840780da1541bfc4bd1e3412c` (V7 final physiquement testé) ;
- dernier SHA V8 applicatif + scripts validé CI avant ce HANDOFF : `ddff3ecc50ff5d54f01baf5c214b879fc477b01f` ;
- run CI : `36318838656` — **SUCCESS** ;
- version app : `0.8.0` ; build `8` ;
- `main` non modifié ;
- autres applications du monorepo hors chantier ;
- conteneur Windows : `E:\_Project\IOS APP\ios-godot-lab` ;
- worktree principal : `E:\_Project\IOS APP\ios-godot-lab\main` ;
- worktree V8 prévu : `E:\_Project\IOS APP\ios-godot-lab\worktrees\cloud-weight-tracking-live-diag-v8`.

Le commit contenant ce HANDOFF est postérieur au SHA CI ci-dessus. **Vérifier une CI complète verte et un artifact exact-SHA sur le HEAD final avant installation.**

## Historique matériel — source de vérité

- V1 rejetée : bounding box globale, pas de vrai détourage multi-régions.
- V2 rejetée : UCloudNet détoure mais faux positifs hors ciel.
- V3 : garde ciel suffisamment efficace sur murs/sol/objets, mais latence et instabilité.
- V4/V5 : stabilisation/télémétrie ajoutées ; retard encore visible ; workflow `COPIER DIAG` rejeté.
- V6 : API HTTP locale + snapshots + UI compacte + rotation coordinator + modèles portrait/paysage.
- V7 : suppression du vote overlay 3 frames, analyse autorisée jusqu'à ~14,3 Hz, tracker plus réactif, garde scène sombre, rendu plus lisible, télémétrie orientation/scène enrichie.

### Test matériel V7 réellement effectué

Build réellement installé/testé : `f6a7c6fc06abcf8840780da1541bfc4bd1e3412c`.

L'utilisateur a fourni 12 JPEG + `status.json` + `snapshots.json` + 180 mesures de télémétrie.

Observations mesurées :

- pipeline moyen sur l'ensemble : ~`68.6 ms` ; P95 ~`72.6 ms` ;
- sur analyses où UCloudNet tourne : ~`70.6 ms` ;
- cadence moyenne : ~`12.6 Hz` ;
- prétraitement ~`3.2 ms` ;
- SegFormer ciel ~`41.8 ms` ;
- UCloudNet ~`15.9 ms` ;
- post-traitement ~`8.5 ms` ;
- état thermique observé en fin de test : `fair` ;
- scène meuble/jambe correctement rejetée : `0 % ciel`, `0 % nuage`, `0 détection` ;
- scène clavier + partie d'écran de ciel : petit signal résiduel, cohérent avec la partie écran visible ;
- plusieurs transitions rapides provoquent encore de gros `maskChange` ;
- le test nuage était principalement une vidéo de ciel affichée sur un moniteur : utile pour cadence/tracking, mais **ne pas régler les seuils scientifiques sur les artefacts de moiré, bord d'écran ou UI vidéo** ;
- défaut tracker objectivé : certaines frames ont plus de pistes stabilisées que de détections brutes (`raw < stable`), parce que V7 conservait une piste manquée pendant une frame **et la rendait encore visible**.

Ces observations matérielles priment sur les hypothèses théoriques.

## Architecture segmentation — inchangée en V8

```text
caméra AVFoundation
    |
SkyWater SegFormer MiT-B2 384×384
    +
UCloudNet k=2 portrait 304×544 / paysage 544×304
    |
cloud = UCloudNet >= 0.52 ET sky >= 0.55
si ciel confirmé < 5 % => zéro nuage
    |
composantes connexes
    |
tracking temporel V8
    |
overlay + labels compacts
```

Les modèles et seuils ciel/nuage **ne sont pas modifiés en V8**. `minimumAnalysisInterval` reste `0.07 s`.

## Tracking V8

`CloudTemporalStabilizer.swift` a été repris à partir des problèmes mesurés V7.

### Changements

- association globale gloutonne basée sur tous les couples piste↔détection, au lieu de laisser l'ordre du tableau des pistes décider ;
- score : IoU + distance au centroïde prédit + ratio de couverture + petit bonus de type ;
- prédiction du prochain centroïde par une vitesse lissée ;
- une piste ratée reste en mémoire **une seule analyse** pour pouvoir récupérer son ID, mais elle n'est **plus affichée** pendant ce miss ;
- les petites nouvelles composantes (< 2 % de l'image) doivent être confirmées sur deux analyses avant affichage ; les grosses restent immédiates ;
- géométrie plus réactive : alpha `0.70` normal / `0.90` mouvement rapide ;
- mesures/masse : alpha `0.52` normal / `0.72` mouvement rapide ;
- changement de type toujours confirmé sur 3 analyses ;
- télémétrie tracking ajoutée : pistes actives, visibles, matchées, créées, cachées pour miss.

But : conserver les IDs sans créer de labels fantômes et réduire les permutations entre nuages voisins.

## Diagnostic local V8 — session continue

Le workflow ponctuel `PULL_CLOUD_WEIGHT_DIAG.ps1` reste disponible, mais le workflow normal V8 devient :

```powershell
.\apps\cloud-weight-lab\WATCH_CLOUD_WEIGHT_DIAG.ps1
```

ou, pour ouvrir le dossier une seule fois et fabriquer un aperçu vidéo si `ffmpeg` est disponible :

```powershell
.\apps\cloud-weight-lab\WATCH_CLOUD_WEIGHT_DIAG.ps1 -OpenFolder -MakeVideo
```

### Fonctionnement Windows

- appairage API une seule fois puis réutilisation du jeton local ;
- une seule session/dossier diagnostic par lancement ;
- polling continu, défaut `500 ms`, jusqu'à `Ctrl+C` ou `-DurationSeconds` ;
- télémétrie récupérée incrémentalement avec `after=<timestamp>` ;
- écrit en continu :
  - `status-latest.json` ;
  - `snapshots-latest.json` ;
  - `telemetry.ndjson` ;
  - `telemetry.csv` ;
  - `frames\frame-*.jpg` ;
- console live : pipeline ms, Hz, variation masque, ciel/nuage, pistes visibles/actives/cachées, nombre d'images, thermique ;
- `-OpenFolder` n'ouvre Explorer qu'une seule fois ;
- `-MakeVideo` crée `diagnostic-preview.mp4` au shutdown si `ffmpeg` existe ; sinon la séquence JPEG reste exploitable et le script ne doit pas échouer pour cette raison.

### Séquence visuelle bornée sur iPhone

Pendant une session API appairée :

- ~`4 fps` (`0.25 s`) ;
- 48 images max dans le ring, soit ~12 s de mouvement récent ;
- dimension max `480 px` ;
- JPEG qualité ~`0.32` ;
- expiration ~10 min ;
- compression sur queue utility ;
- `snapshotCaptureInFlight` interdit l'accumulation d'une file de compressions : si l'encodeur est occupé, la capture suivante est simplement sautée ;
- télémétrie locale max : 900 records ;
- chaque record contient maintenant aussi les détections/IDs/centroïdes/bounds afin de reconstruire le mouvement des pistes dans le temps.

## Confidentialité

- API uniquement locale LAN sur port `8765` ;
- appairage volontaire via bouton `API` ;
- Bearer token stocké uniquement sous `%LOCALAPPDATA%\CloudWeightLab\diagnostics-session.json` ;
- aucune image, télémétrie ou token envoyé automatiquement vers GitHub, Internet ou ChatGPT ;
- les JPEG peuvent contenir l'environnement filmé : ne jamais automatiser leur publication dans le repo public.

## Performance / parallélisation — conclusion V7, exploration future

Les mesures matérielles V7 montrent approximativement :

```text
prétraitement   ~  3.2 ms
SegFormer ciel  ~ 41.8 ms
UCloudNet       ~ 15.9 ms
post-traitement ~  8.5 ms
pipeline actif  ~ 70.6 ms
```

Faire simplement SegFormer + UCloudNet en parallèle sur la **même frame** ne peut donc pas garantir `<30 ms` avec les modèles actuels : même avec un chevauchement parfait, SegFormer ciel prend déjà ~42 ms, avant pré/post-traitement. Une borne optimiste sur les mesures actuelles est plutôt ~53–54 ms.

Piste V9 à tester séparément après validation V8 :

1. utiliser l'API de prédiction Core ML asynchrone/concurrente ;
2. découpler la fréquence du garde ciel et d'UCloudNet : UCloudNet à haute fréquence, masque ciel rafraîchi en parallèle moins souvent ;
3. réutiliser un masque ciel seulement s'il est suffisamment frais et si aucun pan/rotation/changement de scène important n'est détecté ;
4. invalider immédiatement le cache ciel lors d'un changement fort pour ne pas réintroduire de faux positifs hors ciel ;
5. profiler sur iPhone le mapping réel CPU/GPU/Neural Engine et le coût de chaque modèle ;
6. si SegFormer reste le goulot, tester un garde ciel plus léger / résolution réduite / modèle compressé sur branche expérimentale.

Ne pas mélanger cette expérimentation performance avec V8 avant les mesures tracking/mouvement.

## Validation CI V8 avant HANDOFF

SHA : `ddff3ecc50ff5d54f01baf5c214b879fc477b01f`

Run : `36318838656` — **SUCCESS**.

Validé :

- trois modèles Core ML générés ;
- XcodeGen ;
- compilation Swift app + cible XCTest via `build-for-testing` ;
- nouveau tracker et nouvelles structures telemetry compilés ;
- API incrémentale compilée ;
- stockage séquence diagnostic compilé ;
- build iPhone Release non signé ;
- vérification contrat bundle ;
- packaging IPA exact-SHA ;
- upload artifact exact-SHA.

Important : `build-for-testing` **compile** les tests XCTest mais ne les exécute pas. Les nouveaux tests tracker sont donc compilés, pas exécutés.

Le script `WATCH_CLOUD_WEIGHT_DIAG.ps1` est versionné mais **n'a pas encore été exécuté sur le Windows réel de l'utilisateur**.

## NON VALIDÉ PHYSIQUEMENT EN V8

- disparition réelle des fantômes pendant un miss ;
- récupération stable du même ID après un miss ;
- stabilité des IDs quand deux nuages proches changent de taille/ordre ;
- effet des nouveaux alphas sur jitter vs retard ;
- coût thermique/perf de la capture diagnostic ~4 fps ;
- fonctionnement réel de `WATCH_CLOUD_WEIGHT_DIAG.ps1` sur PowerShell Windows ;
- génération facultative MP4 avec `ffmpeg` ;
- comportement sur vrai ciel extérieur ;
- parallélisation / architecture sky-cache : **pas implémentée en V8**.

## Pipeline Windows / IPA

`UPDATE_CLOUD_WEIGHT_LAB.ps1` vise :

`fix/cloud-weight-tracking-live-diag-v8-20260927`

Depuis le worktree V8 :

```powershell
.\apps\cloud-weight-lab\UPDATE_CLOUD_WEIGHT_LAB.ps1 -OpenFolder
```

Puis installation de l'IPA exact-SHA avec iLoader.

## Test matériel prioritaire V8

1. installer l'IPA exact-SHA finale ;
2. appairer API si nécessaire ;
3. lancer `WATCH_CLOUD_WEIGHT_DIAG.ps1` une seule fois ;
4. faire 30–60 s de test : téléphone fixe, pan lent, pan rapide, nuages voisins, hors ciel, portrait/paysage ;
5. arrêter avec `Ctrl+C` ;
6. conserver `telemetry.csv/ndjson` + séquence `frames` (+ MP4 si généré) ;
7. comparer IDs/centroïdes/bounds et images pour quantifier jitter, swaps et retard ;
8. faire au moins un test sur **vrai ciel extérieur** avant de modifier les seuils du modèle ;
9. seulement après, ouvrir une V9 performance pour async/concurrence/sky-cache.

## À ne pas modifier

- `main` sans accord explicite ;
- autres apps/workflows du monorepo ;
- modèles et seuils ciel/nuage tant que le test V8 ne justifie pas une modification ;
- ne jamais automatiser l'upload des diagnostics vers le repo public.

## Prochaine étape exacte

1. valider la CI complète du commit final contenant ce HANDOFF ;
2. vérifier branche/HEAD exact et artifact ;
3. récupérer IPA via le script exact-SHA ;
4. installer avec iLoader ;
5. tester le watcher continu sur Windows ;
6. faire une session de mouvement V8 ;
7. analyser les trajectoires/frames ;
8. lancer ensuite la branche V9 de performance concurrente si les données confirment que tracking V8 est suffisamment propre.
