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
- dernier SHA applicatif V9 validé CI avant ce HANDOFF : `be9eaf5083691eda65379cc952403c37821f0076` ;
- run CI applicatif : `36327352371` — **SUCCESS** ;
- version app V9 : `0.9.0` ; build `9` ;
- `main` non modifié ;
- autres applications du monorepo hors chantier ;
- conteneur Windows : `E:\_Project\IOS APP\ios-godot-lab` ;
- worktree principal : `E:\_Project\IOS APP\ios-godot-lab\main` ;
- worktree V9 prévu : `E:\_Project\IOS APP\ios-godot-lab\worktrees\cloud-weight-sky-preroll-v9`.

Le commit contenant ce HANDOFF est postérieur au SHA applicatif ci-dessus : **valider une CI complète et un artifact exact-SHA sur le HEAD final avant installation**.

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

L'utilisateur a fourni :

- `diagnostic-preview.mp4` ;
- `telemetry.ndjson` / CSV ;
- `status-latest.json` ;
- `snapshots-latest.json`.

Observations :

- tracking et diagnostic sont suffisamment exploitables pour analyser le mouvement ;
- le MP4 rend inutile l'envoi du dossier `frames` dans le chat ;
- test extérieur réel : **un arbre a été confondu avec ciel/nuage** ; ce faux positif matériel est la raison principale du changement V9 ;
- le clip extérieur arbre n'était pas disponible dans le MP4 reçu, car la séquence visuelle V8 ne commençait qu'après appairage ;
- certaines scènes hors ciel passent encore fugitivement avec de fortes couvertures ciel/nuage ;
- le garde ciel V8 (SkyWater SegFormer MiT-B2) reste le coût principal, ~40–45 ms typiques ; UCloudNet ~15–16 ms ; pipeline actif ~70 ms ;
- état thermique observé : `fair` ;
- la télémétrie V8 révélait aussi une erreur de version : le build V8 pouvait encore annoncer `0.6.0` car le workflow stampait une ancienne chaîne.

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
- interface conservée côté Swift : `image_tensor` → `sky_probability` 384×384.

But : laisser passer uniquement les zones réellement classées `sky`, plutôt que demander à un modèle spécialisé ciel/eau/personne de généraliser seul aux arbres et objets hors distribution.

Aucune affirmation de qualité sur arbre réel avant test iPhone V9.

## Diagnostic V9 — pré-roll local

`CloudDiagnosticsStore` capture maintenant localement dès le démarrage de l'analyse, avant appairage réseau :

- ~4 fps (`0.25 s`) ;
- ring de `80` JPEG max ≈ 20 s ;
- dimension max 480 px ;
- qualité JPEG ~0.32 ;
- fichiers temporaires, expiration ~10 min ;
- compression sur queue utility, une seule compression en vol ;
- aucune image ne quitte l'iPhone avant authentification de l'API.

L'API reste protégée par appairage volontaire + Bearer token. Le watcher récupère le ring existant dès qu'il est authentifié : cela permet de voir ce qui s'est passé **avant** la connexion Windows.

Attention : dans cette première passe V9, toucher `API` met brièvement la capture en pause jusqu'à l'appairage ; lancer le watcher puis toucher `API` immédiatement pour conserver le pré-roll le plus complet.

## Workflow diagnostic Windows

Workflow normal :

```powershell
.\apps\cloud-weight-lab\WATCH_CLOUD_WEIGHT_DIAG.ps1 -MakeVideo
```

À partager pour analyse :

- `diagnostic-preview.mp4` ;
- `telemetry.ndjson` ou `telemetry.csv` ;
- `status-latest.json` ;
- `snapshots-latest.json`.

Le dossier `frames` est un intermédiaire de fabrication du MP4 et n'a pas besoin d'être partagé.

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
- génération des deux UCloudNet portrait/paysage ;
- conversion du nouveau SegFormer B0 ADE20K vers Core ML ;
- validation numérique PyTorch ↔ Core ML du garde ciel ;
- génération XcodeGen ;
- compilation Swift app + cible XCTest via `build-for-testing` ;
- build iPhone Release non signé ;
- contrat bundle et présence des 3 modèles `.mlmodelc` ;
- packaging IPA exact-SHA ;
- upload artifact exact-SHA.

Important : `build-for-testing` compile les tests XCTest mais ne les exécute pas. Ne pas dire qu'ils ont été exécutés/passés.

## NON VALIDÉ PHYSIQUEMENT EN V9

À ne pas annoncer comme validé avant nouveau test iPhone :

- arbre/feuillage réellement rejeté ;
- mur, peau, meubles, bâtiments rejetés sans régression ;
- vrai ciel bleu/cumulus/ciel couvert conservés ;
- seuil `sky >= 0.55` adapté au nouveau modèle générique ;
- cadence réelle du SegFormer B0 sur l'iPhone ;
- gain ou régression de latence vs MiT-B2 ;
- pré-roll de ~20 s réellement récupéré avant appairage ;
- stabilité thermique prolongée ;
- tracking V8 sur scène extérieure réelle.

## Performance — étape suivante, séparée

La parallélisation/sky-cache n'est PAS implémentée dans cette V9.

Après validation physique du nouveau garde ciel :

1. mesurer `skyInferenceMilliseconds` avec B0 sur iPhone ;
2. comparer pipeline V8 vs V9 ;
3. si le garde ciel reste le goulot, expérimenter sur branche dédiée : prédictions Core ML concurrentes, masque ciel moins fréquent/caché, invalidation immédiate lors de pan/rotation/changement de scène ;
4. ne jamais réutiliser un masque ciel stale si la géométrie ou la scène change fortement.

Objectif performance à mesurer, pas à promettre : rapprocher le chemin fréquent de ~25–30 ms sans réintroduire les faux positifs hors ciel.

## Télémétrie globale VPS — idée future

L'utilisateur souhaite à terme un système réutilisable pour plusieurs apps iPhone et autres apps : télémétrie vers son VPS, utilisable aussi en 4G/Tailscale, avec stockage central puis partage/analyse depuis un repo privé ou export.

Cette infrastructure est **volontairement hors scope V9**. Ne pas la mélanger à Cloud Weight tant que le garde ciel/tracking local n'est pas validé. Quand elle sera ouverte, prévoir authentification forte, HTTPS, schémas versionnés par app, rétention bornée, consentement explicite pour médias et aucun secret dans les repos publics.

## Pipeline Windows / IPA

Le script existant accepte `-ExpectedBranch`. Tant que son défaut n'a pas été basculé sur V9, utiliser :

```powershell
.\apps\cloud-weight-lab\UPDATE_CLOUD_WEIGHT_LAB.ps1 `
    -ExpectedBranch 'fix/cloud-weight-sky-preroll-v9-20260927' `
    -OpenFolder
```

Puis installation de l'IPA exact-SHA via iLoader.

## Test matériel prioritaire V9

1. installer l'IPA exact-SHA finale ;
2. **avant de lancer le watcher**, viser dehors un vrai arbre + ciel pendant 5–10 s ;
3. lancer ensuite le watcher Windows, toucher `API` dès qu'il le demande ;
4. confirmer que le MP4 récupéré commence avant l'appairage et contient l'arbre ;
5. arbre/feuillage : attendu hors masque ciel/nuage ;
6. enchaîner bâtiment, main/peau, mur ;
7. revenir sur vrai ciel/cumulus/ciel couvert ;
8. pan lent puis rapide, plusieurs nuages, portrait/paysage ;
9. laisser tourner au moins 30–60 s ;
10. arrêter le watcher, produire MP4 et comparer temps/Hz/tracking au V8.

## À ne pas modifier

- `main` sans accord explicite ;
- autres applications/workflows du monorepo ;
- seuils UCloudNet/ciel avant diagnostic matériel V9 ;
- ne pas automatiser l'upload de médias/télémétrie vers GitHub public ;
- ne pas implémenter le VPS global dans cette branche V9.

## Prochaine étape exacte

1. vérifier la CI complète du HEAD final contenant ce HANDOFF ;
2. vérifier branche/HEAD/artifact exacts ;
3. récupérer l'IPA exact-SHA via le script Windows ;
4. installer via iLoader ;
5. exécuter le protocole extérieur V9 avec pré-roll ;
6. analyser MP4 + télémétrie ;
7. seulement après validation, ouvrir la branche performance sky-cache/concurrence.
