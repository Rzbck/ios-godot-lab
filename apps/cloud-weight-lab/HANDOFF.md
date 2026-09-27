# HANDOFF — Cloud Weight Lab

Date : **2026-09-27**

## Objectif

Application iPhone personnelle qui reconnaît le ciel, détoure plusieurs nuages, stabilise leurs IDs dans le temps et affiche une estimation pédagogique de masse d'eau/glace condensée.

Priorité V9 : **réduire les faux positifs hors ciel (notamment arbres) avec un garde sémantique générique et garantir un pré-roll visuel local avant la connexion du watcher diagnostic**.

## Identité chantier

- repository : `Rzbck/ios-godot-lab` ;
- application : `apps/cloud-weight-lab` ;
- branche active : `fix/cloud-weight-sky-preroll-v9-20260927` ;
- base V9 : `c1c10b167466de6c5ab5ec17f84e1b6f2d0a4c40` (V8 final CI, physiquement testé) ;
- dernier SHA applicatif V9 validé CI avant les commits de workflow/HANDOFF : `be9eaf5083691eda65379cc952403c37821f0076` ;
- run CI applicatif : `36327352371` — **SUCCESS** ;
- version app V9 : `0.9.0` ; build `9` ;
- `main` non modifié ;
- autres applications du monorepo hors chantier ;
- conteneur Windows : `E:\_Project\IOS APP\ios-godot-lab` ;
- worktree principal : `E:\_Project\IOS APP\ios-godot-lab\main` ;
- worktree V9 prévu : `E:\_Project\IOS APP\ios-godot-lab\worktrees\cloud-weight-sky-preroll-v9`.

Le commit contenant ce HANDOFF et les scripts Windows est postérieur au SHA applicatif ci-dessus : **valider une CI complète et un artifact exact-SHA sur le HEAD final avant installation**.

## Historique matériel — source de vérité

- V1 rejetée : bounding box globale, pas de vrai détourage multi-régions.
- V2 rejetée : UCloudNet détoure mais faux positifs hors ciel.
- V3 : garde ciel spécialisé nettement meilleur, mais latence/instabilité.
- V4/V5 : stabilisation/télémétrie ; workflow manuel `COPIER DIAG` rejeté.
- V6 : API HTTP locale, snapshots, UI compacte, rotation portrait/paysage.
- V7 : suppression du vote overlay 3 frames, ~12–13 Hz mesurés, tracking plus réactif, garde scène sombre.
- V8 : association globale des tracks + IDs persistants, pistes ratées cachées, watcher Windows continu, séquence JPEG ~4 fps et MP4 diagnostic.

### Test matériel V8 réellement effectué

Build installé/testé : `c1c10b167466de6c5ab5ec17f84e1b6f2d0a4c40`.

L'utilisateur a fourni `diagnostic-preview.mp4`, télémétrie NDJSON/CSV, status et liste de snapshots.

Observations :

- tracking et diagnostic suffisamment exploitables pour analyser le mouvement ;
- le MP4 rend inutile l'envoi du dossier `frames` dans le chat ;
- test extérieur réel : **un arbre a été confondu avec ciel/nuage** ; ce faux positif matériel motive le garde V9 ;
- le passage extérieur arbre n'était pas présent dans le MP4 reçu car la séquence V8 ne commençait qu'après appairage ;
- certaines scènes hors ciel peuvent encore passer fugitivement avec forte couverture ciel/nuage ;
- garde V8 SkyWater MiT-B2 : ~40–45 ms typiques ; UCloudNet ~15–16 ms ; pipeline actif ~70 ms ;
- état thermique observé : `fair` ;
- erreur d'identité V8 : certains diagnostics annonçaient encore `0.6.0` à cause du stamping du workflow.

Ces observations matérielles priment sur les hypothèses théoriques.

## Architecture V9

```text
caméra AVFoundation
    |
SegFormer B0 ADE20K générique 384×384
  classe sky (ADE20K index 2)
    +
UCloudNet k=2 portrait 304×544 / paysage 544×304
    |
cloud = UCloudNet >= 0.52 ET sky >= 0.55
si ciel confirmé < 5 % => zéro nuage
    |
composantes connexes
    |
tracker temporel V8
    |
overlay + labels compacts
```

Les seuils UCloudNet/ciel ne sont PAS modifiés dans V9 avant test matériel.

## Nouveau garde ciel V9

Le garde spécialisé SkyWater MiT-B2 est remplacé par :

- modèle : `nvidia/segformer-b0-finetuned-ade-512-512` ;
- dataset/classes : ADE20K / scene_parse_150 ;
- classe utilisée pour autoriser le nuage : `sky`, index `2` ;
- le modèle générique distingue notamment aussi `wall`, `building`, `tree`, `person`, etc. ;
- revision épinglée : `489d5cd81a0b59fab9b7ea758d3548ebe99677da` ;
- SHA-256 des poids safetensors : `6ae39addd01de6b1b8bde2cf677d43a5cd733424b8d186de3f95d1c51fee23f9` ;
- licence : NVIDIA Source Code License for SegFormer, usage non-commercial recherche/évaluation ; compatible avec l'usage personnel/non-commercial déclaré pour ce projet ;
- conversion Core ML : iOS 17, ML Program, FLOAT16 ;
- interface Swift conservée : `image_tensor` → `sky_probability` 384×384.

But : autoriser UCloudNet seulement sur les zones réellement classées `sky`, plutôt que demander à un modèle spécialisé ciel/eau/personne de généraliser seul aux arbres et objets hors distribution.

Aucune affirmation de qualité sur arbre réel avant test iPhone V9.

## Diagnostic V9 — pré-roll local

`CloudDiagnosticsStore` capture localement dès le démarrage de l'analyse, avant appairage réseau :

- ~4 fps (`0.25 s`) ;
- ring `80` JPEG max ≈ 20 s ;
- dimension max 480 px ;
- JPEG ~0.32 ;
- expiration ~10 min ;
- queue utility et une seule compression en vol ;
- aucune image ne quitte l'iPhone avant authentification de l'API.

Le watcher récupère le ring existant dès authentification. Cela permet de capturer un faux positif observé **avant** le lancement/appairage Windows.

Dans cette première passe V9, toucher `API` suspend brièvement la capture jusqu'à l'appairage ; lancer le watcher puis toucher `API` immédiatement.

## Workflow diagnostic Windows V9

Commande normale :

```powershell
.\apps\cloud-weight-lab\WATCH_CLOUD_WEIGHT_DIAG.ps1 -MakeVideo
```

Avec `ffmpeg` et création MP4 réussie :

- crée `diagnostic-preview.mp4` ;
- supprime automatiquement `frames\` et `frames.ffconcat` ;
- conserve télémétrie/status/snapshots ;
- `-KeepFrames` permet explicitement de conserver les JPEG si nécessaire ;
- si ffmpeg manque ou échoue, les JPEG sont conservés pour ne perdre aucune donnée.

À partager normalement pour analyse :

- `diagnostic-preview.mp4` ;
- `telemetry.ndjson` ou `telemetry.csv` ;
- `status-latest.json` ;
- `snapshots-latest.json`.

## Version / identité build

V9 corrige le stamping incohérent V8 :

- `CFBundleShortVersionString = 0.9.0` ;
- `CFBundleVersion = 9` ;
- `BuildInfo.version = 0.9.0` en CI ;
- `BUILD-METADATA.json` = `0.9.0`.

Toujours vérifier le SHA exact dans l'artifact et dans le status diagnostic.

## Validation CI V9 applicative

SHA : `be9eaf5083691eda65379cc952403c37821f0076`

Run : `36327352371` — **SUCCESS**.

Validé par ce run :

- téléchargement épinglé + SHA des poids ADE20K ;
- génération UCloudNet portrait/paysage ;
- conversion SegFormer B0 ADE20K Core ML ;
- validation numérique PyTorch ↔ Core ML ;
- XcodeGen ;
- compilation Swift app + cible XCTest via `build-for-testing` ;
- build iPhone Release non signé ;
- contrat bundle + trois modèles `.mlmodelc` ;
- packaging et upload IPA exact-SHA.

Important : `build-for-testing` compile les tests XCTest mais ne les exécute pas.

## NON VALIDÉ PHYSIQUEMENT EN V9

- arbre/feuillage réellement rejeté ;
- mur, peau, meubles, bâtiments rejetés sans régression ;
- vrai ciel bleu/cumulus/ciel couvert conservés ;
- seuil `sky >= 0.55` adapté au nouveau modèle ;
- cadence réelle du SegFormer B0 sur iPhone ;
- gain/régression de latence vs MiT-B2 ;
- pré-roll ~20 s réellement récupéré avant appairage ;
- tracking V8 sur scène extérieure réelle ;
- stabilité thermique prolongée.

## Performance — étape suivante séparée

La parallélisation/sky-cache n'est PAS implémentée en V9.

Après validation physique :

1. mesurer `skyInferenceMilliseconds` du B0 ;
2. comparer V8 vs V9 ;
3. si nécessaire, ouvrir une branche dédiée avec prédictions Core ML concurrentes et/ou masque ciel rafraîchi moins souvent ;
4. invalider immédiatement tout cache ciel sur pan/rotation/changement fort de scène.

Objectif à mesurer, jamais à promettre : rapprocher le chemin fréquent de ~25–30 ms sans réintroduire les faux positifs hors ciel.

## Télémétrie globale VPS — chantier futur

L'utilisateur souhaite un système réutilisable pour plusieurs apps iPhone/autres apps via son VPS, utilisable aussi en 4G/Tailscale, avec stockage central puis partage/analyse via export ou repo privé.

Hors scope V9. Quand ce chantier sera ouvert : HTTPS/auth forte, schémas versionnés par app, rétention bornée, médias opt-in, aucun secret dans repo public.

## Pipeline Windows / IPA

`UPDATE_CLOUD_WEIGHT_LAB.ps1` vise désormais directement :

`fix/cloud-weight-sky-preroll-v9-20260927`

Commande normale depuis le worktree V9 :

```powershell
.\apps\cloud-weight-lab\UPDATE_CLOUD_WEIGHT_LAB.ps1 -OpenFolder
```

Puis installation de l'IPA exact-SHA via iLoader.

## Test matériel prioritaire V9

1. installer l'IPA exact-SHA finale ;
2. avant le watcher, viser dehors un vrai arbre + ciel pendant 5–10 s ;
3. lancer le watcher, toucher `API` dès sa demande ;
4. confirmer que le MP4 commence avant l'appairage et contient l'arbre ;
5. arbre/feuillage : attendu hors masque ciel/nuage ;
6. enchaîner bâtiment, main/peau, mur ;
7. revenir sur vrai ciel/cumulus/ciel couvert ;
8. pan lent/rapide, plusieurs nuages, portrait/paysage ;
9. laisser tourner 30–60 s ;
10. arrêter et comparer temps/Hz/tracking au V8.

## À ne pas modifier

- `main` sans accord explicite ;
- autres apps/workflows ;
- seuils UCloudNet/ciel avant diagnostic matériel V9 ;
- aucun upload automatique de médias/télémétrie vers GitHub public ;
- ne pas implémenter le VPS global dans cette branche.

## Prochaine étape exacte

1. valider CI complète du HEAD final contenant HANDOFF + scripts ;
2. vérifier branche/HEAD/artifact exacts ;
3. récupérer IPA via `UPDATE_CLOUD_WEIGHT_LAB.ps1` ;
4. installer via iLoader ;
5. exécuter test extérieur V9 avec pré-roll ;
6. analyser MP4 + télémétrie ;
7. ensuite seulement ouvrir la branche performance sky-cache/concurrence.
