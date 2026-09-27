# HANDOFF — Cloud Weight Lab

Date : **2026-09-27**

## Objectif

Application iPhone personnelle qui reconnaît les nuages réellement présents dans le ciel, détoure plusieurs régions, suit les détections temporellement et affiche une estimation pédagogique de masse d'eau/glace condensée. Priorité V7 : **réduire la latence perceptible et les fantômes sans réintroduire les faux positifs hors ciel, tout en gardant un diagnostic local exploitable depuis Windows**.

## Identité chantier

- repository : `Rzbck/ios-godot-lab` ;
- application : `apps/cloud-weight-lab` ;
- branche active : `fix/cloud-weight-realtime-v7-20260927` ;
- base V7 : `82e86984be1f2ca406a623a21e7d1071059d2426` (V6 + correctif PowerShell diagnostics) ;
- dernier SHA applicatif V7 validé CI avant ce HANDOFF : `b6d1eac53e3333f604a8b65e2e7b6cca39911646` ;
- run CI applicatif : `36316480978` — **SUCCESS** ;
- `main` non modifié ;
- autres applications du monorepo hors chantier ;
- conteneur Windows : `E:\_Project\IOS APP\ios-godot-lab` ;
- worktree principal : `E:\_Project\IOS APP\ios-godot-lab\main` ;
- worktree V7 prévu : `E:\_Project\IOS APP\ios-godot-lab\worktrees\cloud-weight-realtime-v7`.

Le commit contenant ce HANDOFF et le script de synchro V7 est postérieur au SHA applicatif ci-dessus : **vérifier une CI complète verte et un artifact exact-SHA sur le HEAD final avant installation**.

## Historique matériel — source de vérité

- V1 rejetée : bounding box globale, pas de détourage multi-régions.
- V2 rejetée : UCloudNet détourait mais faux positifs hors ciel.
- V3 : garde ciel nettement meilleur sur objets hors ciel, mais latence/instabilité.
- V4/V5 : stabilisation/télémétrie ajoutées mais retard perceptible ; workflow `COPIER DIAG` rejeté par l'utilisateur.
- V6 : API locale + snapshots + UI compacte + rotation coordinator + UCloudNet portrait/paysage. Test réel effectué sur iPhone et diagnostics récupérés par PowerShell.

### Résultats matériels V6 à préserver

Build iPhone réellement testé : `8a20b8007d74764136ddc53f4ae33754ac19e71c`.

Les diagnostics fournis par l'utilisateur montrent :

- pipeline typique environ **60–70 ms** ;
- cadence réelle environ **8–9 Hz** ;
- état thermique observé : **nominal** ;
- SegFormer ciel est le coût principal, typiquement ~35–45 ms ; UCloudNet typiquement ~10–16 ms ;
- certaines transitions de scène produisent de très grands sauts de masque/couverture ;
- sur une scène artificielle presque noire, le garde ciel V6 s'est trompé de manière stable : ~88–99 % ciel et ~35–37 % nuage ;
- lorsque l'iPhone pointe vers le haut, `UIDevice.current.orientation` reste souvent `faceUp`, donc ce signal n'est pas une télémétrie d'orientation caméra fiable ;
- sur un ciel très couvert, le rendu V6 contourne fortement les trous bleus tandis que l'intérieur du masque est très transparent, ce qui peut donner l'impression que l'app détecte les espaces entre nuages ;
- le retard ressenti vient en partie du lissage volontaire : analyse plafonnée à 10 Hz, vote overlay sur 3 analyses et alphas de tracking conservateurs.

Ces observations matérielles priment sur les hypothèses théoriques.

## Architecture conservée

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
tracking temporel
    |
overlay + labels compacts
```

Les seuils Core ML V3/V6 n'ont PAS été modifiés dans V7.

## Changements V7

### Réactivité

- `minimumAnalysisInterval` : `0.10 s` → `0.07 s` ; plafond logiciel ~14,3 analyses/s si le matériel suit ;
- `CloudOverlayStabilizer.historyLimit` : `3` → `1`, suppression du vote majoritaire de 3 frames qui ajoutait du retard visuel ;
- tracker plus réactif : géométrie alpha `0.56/0.84`, mesures alpha `0.40/0.62` ;
- conservation d'un seul miss toujours présente pour éviter les clignotements ponctuels ;
- changement de type de nuage toujours confirmé sur 3 analyses.

### Reset lors d'un changement de scène

`CameraService` réinitialise le tracker et l'overlay si :

- les dimensions du buffer caméra changent (rotation/geometry), ou
- la couverture nuage brute saute de plus de 30 points de pourcentage.

But : ne pas faire traîner des labels/masques de l'ancienne scène après un pan rapide, une rotation ou une coupure vidéo.

### Garde scène sombre

Nouveau `SceneSanityGate.swift` : échantillonnage léger de luminance avant les réseaux.

Rejet uniquement si :

- luminance moyenne < `0.08`, ET
- plus de `72 %` des échantillons ont une luminance < `0.08`.

Le but est de couvrir le faux positif matériel V6 sur image presque noire, sans modifier les seuils ciel/nuage. Les scènes nocturnes très sombres sont donc volontairement hors cible pour l'instant.

### Rendu overlay

- vote temporel 3 frames supprimé ;
- remplissage intérieur augmenté (`alpha 28` → `52`) ;
- contour légèrement réduit (`238` → `232`).

But : rendre explicite quelle surface est considérée comme nuage et éviter de faire visuellement dominer les contours des trous bleus dans un ciel très couvert.

### Télémétrie orientation / scène

`CloudTelemetrySnapshot` ajoute :

- `deviceOrientation` ;
- `captureWidth`, `captureHeight` ;
- `captureRotationDegrees` issu du `AVCaptureDevice.RotationCoordinator` ;
- `sceneLuminancePercent` ;
- `sceneRejected`.

Le champ `orientation` représente maintenant le format réel du buffer (`portrait`/`landscape`) et non plus directement `UIDevice.current.orientation`.

## Diagnostic local / confidentialité

Le mécanisme V6 est conservé : API HTTP locale LAN sur port `8765`, appairage volontaire via le bouton `API`, jeton local Windows, snapshots temporaires bornés.

- aucun upload automatique vers GitHub/Internet ;
- snapshots max : 12 ;
- intervalle ~2 s pendant session appairée ;
- 640 px max ;
- JPEG qualité ~0,45 ;
- expiration ~10 min ;
- historique télémétrie max : 180 ;
- token Windows : `%LOCALAPPDATA%\CloudWeightLab\diagnostics-session.json`.

Script :

```powershell
.\apps\cloud-weight-lab\PULL_CLOUD_WEIGHT_DIAG.ps1 -OpenFolder
```

Le bug PowerShell V6 sur une liste de snapshots vide a été corrigé au SHA de base V7 `82e86984be1f2ca406a623a21e7d1071059d2426`.

## Validation CI V7 applicative

SHA : `b6d1eac53e3333f604a8b65e2e7b6cca39911646`

Run : `36316480978` — **SUCCESS**.

Validé par ce run :

- trois modèles Core ML générés ;
- génération XcodeGen ;
- compilation Swift app + cible XCTest via `build-for-testing` ;
- compilation du nouveau garde sombre et de sa cible de tests ;
- build iPhone Release non signé ;
- contrat bundle ;
- IPA exact-SHA ;
- upload artifact exact-SHA.

Important : `build-for-testing` **compile** la cible XCTest mais n'exécute pas les tests. Ne jamais dire que les tests XCTest ont été exécutés/passés.

## NON VALIDÉ PHYSIQUEMENT EN V7

À ne pas annoncer comme validé avant nouveau test iPhone :

- faux positif de la scène presque noire réellement supprimé ;
- absence de régression sur vrais nuages/ciel ;
- cadence réelle après plafond `0.07 s` ;
- sensation de latence après suppression du vote 3 frames ;
- stabilité du tracker plus réactif ;
- reset correct lors d'un pan/rotation/changement de scène ;
- alignement preview / masque / labels portrait et paysages ;
- lisibilité du nouveau remplissage sur ciel couvert ;
- comportement thermique sur test prolongé ;
- robustesse sur scènes hors distribution lumineuses (mur/écran clair, végétation, etc.).

## Test matériel prioritaire V7

1. installer l'IPA exact-SHA finale ;
2. reproduire la même scène noire/artificielle de V6 : attendu `0 nuage`, `sceneRejected=true` ;
3. viser de vrais nuages : vérifier aucune régression ;
4. pan rapide puis retour sur un nuage : vérifier disparition des fantômes ;
5. portrait → paysage gauche/droite : vérifier preview, masque, labels ;
6. ciel très couvert : vérifier que la couleur remplit clairement la zone nuageuse ;
7. laisser tourner 20–30 s ;
8. récupérer diagnostics via PowerShell ;
9. analyser `pipeline`, `effectiveHz`, `maskChange`, `captureWidth/Height`, `captureRotationDegrees`, `sceneLuminancePercent`, `sceneRejected`, drops/throttle/thermal avant toute nouvelle optimisation.

## Pipeline Windows / IPA

`UPDATE_CLOUD_WEIGHT_LAB.ps1` vise désormais :

`fix/cloud-weight-realtime-v7-20260927`

Commande normale depuis le worktree V7 :

```powershell
.\apps\cloud-weight-lab\UPDATE_CLOUD_WEIGHT_LAB.ps1 -OpenFolder
```

Puis installation de l'IPA exact-SHA via iLoader.

## À ne pas modifier

- `main` sans accord explicite ;
- autres apps/workflows du monorepo ;
- modèles/seuils ciel-nuage sans nouveau diagnostic matériel qui le justifie ;
- ne jamais automatiser l'upload des snapshots, tokens ou données iPhone vers le repo public.

## Prochaine étape exacte

1. attendre la CI complète du HEAD final contenant ce HANDOFF + script V7 ;
2. vérifier branche/HEAD exact et artifact ;
3. récupérer l'IPA exact-SHA via `UPDATE_CLOUD_WEIGHT_LAB.ps1` ;
4. installer via iLoader ;
5. exécuter le protocole matériel V7 ;
6. récupérer JSON/JPEG avec `PULL_CLOUD_WEIGHT_DIAG.ps1` et comparer objectivement V6→V7.
