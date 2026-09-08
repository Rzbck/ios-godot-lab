# Handoff IA — état courant / reprise immédiate

Date : **2026-09-08**.

> Porte d'entrée canonique : `/HANDOFF.md`. Toujours re-fetcher les HEADs et la dernière activité GitHub avant toute conclusion.

## État global

Le bootstrap Windows -> GitHub Actions macOS -> Godot iOS -> Xcode -> IPA unsigned -> iLoader -> iPhone fonctionne réellement.

Une première IPA Godot a été installée et lancée sur l'iPhone. Le retour utilisateur sur cette première version : l'app est bien présente et utilisable, les probes principaux « ont l'air de fonctionner », mais le scroll vertical est mauvais car il ne démarre correctement que dans certaines zones hors cartes. Cette observation a déclenché la V2.

La V2 est maintenant un capability lab beaucoup plus complet : navigation, GPS/carte, réseau générique, bridge iOS natif, télémétrie live vers PowerShell, design dark terminal et correction de la propagation du scroll. Ces capacités restent **IMPLÉMENTÉES / BUILD CI VALIDÉES**, pas encore **VALIDÉES SUR IPHONE** tant que l'IPA V2 exacte n'a pas été installée et observée physiquement.

## Git / branches

- repo : `Rzbck/ios-godot-lab` ;
- `main` reste non promu pendant la validation ;
- branche produit V2 : `feat/iphone-lab-v2-20260908` ;
- branche tooling transitoire créée pour le workflow artifact local : `feat/iphone-lab-v2-artifact-sync-20260908` ;
- ne jamais supposer que le SHA écrit ici est le HEAD courant : toujours re-fetcher.

## Premier build réellement installé sur iPhone

Build baseline :

- SHA produit : `8899a4bb4ad8addecf20a36d91b8d2055346cef5` ;
- run iOS : `34160430197` ;
- IPA : `IOSGodotLab-unsigned-8899a4bb4ad8.ipa` ;
- SHA-256 : `40e8b799779de2a9cf6b8b0973e6308875d4006223cbceaa43b4f001c187e14d`.

Validation utilisateur :

- installation via iLoader : PASS ;
- présence de l'app sur iPhone : PASS ;
- lancement de l'app : PASS ;
- retour utilisateur : probes principaux semblent réagir ;
- scroll : défaut UX reproduit par l'utilisateur ;
- ne pas classer individuellement GPS/BLE/caméra/micro/etc. sur ce build : ils n'existaient pas encore dans la baseline.

## V2 — portée implémentée

Branche `feat/iphone-lab-v2-20260908` :

- menu `Overview / Telemetry / Sensors / GPS / Network / Device` ;
- design near-black / terminal compact / navigation glass contrôlée ;
- drag vertical autorisé depuis les cartes et labels, contrôles interactifs en propagation `PASS` ;
- splash/logo Godot désactivé côté projet ;
- touch/drag, accelerometer, gravity, gyro, magnetometer, haptics ;
- caméra Godot ;
- microphone avec niveau RMS uniquement ;
- bridge natif `IOSLab` : CoreLocation, CoreBluetooth BLE, batterie, ARKit availability, LiDAR availability, NFC availability ;
- GPS avec carte OpenStreetMap et handoff Apple Maps ;
- réseau générique : HTTP/HTTPS, WebSocket/WSS, UDP, OSC ;
- destination libre : LAN, Tailscale, TouchDesigner, SIGNAL, Python ou autre service atteignable.

## Télémétrie live vers PowerShell

La V2 contient une télémétrie **opt-in** conçue pour le debug temps réel sans repo privé ni cloud obligatoire.

Transport recommandé : **WebSocket**. HTTP POST reste fallback.

Flux cible :

`iPhone -> LAN/Tailscale -> PowerShell Windows -> copier/coller le log dans ChatGPT -> diagnostic`

Le service envoie notamment :

- exact build identity ;
- page active + FPS ;
- touch/drag ;
- accéléromètre / gravity / gyro / magnétomètre ;
- dernière position CoreLocation + précision ;
- BLE state / dernier peripheral ;
- ARKit / LiDAR / NFC availability ;
- batterie / plateforme / modèle / locale / écran / adresses locales ;
- événements diagnostiques réseau et device.

Chaque packet a un `seq`; le receiver PowerShell répond avec un ACK et l'app calcule le RTT.

Aucune destination n'est hard-codée. Rien n'est envoyé avant `START STREAM`.

Exclusions de confidentialité : Apple ID, UDID, pairing/signing material, presse-papiers, frames caméra, audio micro.

Receiver versionné : `tools/Receive-IOSLabTelemetry.ps1`.

## BUILD IOS V2 validé avant artifact-sync

SHA V2 ayant passé parse/smoke + Xcode :

- `c3c85f2df18ca8078b9e1319469effb183764ebd` ;
- workflow iOS run `34168444588` : `success` ;
- Xcode : `BUILD SUCCEEDED` ;
- artifact ID : `10034961677` ;
- IPA : `IOSGodotLab-unsigned-c3c85f2df18c.ipa` ;
- SHA-256 IPA : `08172a0883fecf96a4dcccfa3c7f20e65657402ad0bf957406165ed36ab85f6c` ;
- classification : **BUILD IOS VALIDÉ**, pas encore **VALIDÉ SUR IPHONE**.

## Règle permanente — plus de liens GitHub Actions pour les IPA

Le téléchargement manuel par lien GitHub Actions est abandonné comme workflow utilisateur : il a été peu fiable dans l'UI utilisée.

Le repo contient maintenant `UPDATE_IOS_LAB.ps1`.

Workflow canonique :

1. ouvrir PowerShell dans le worktree de la branche à tester ;
2. lancer `.\UPDATE_IOS_LAB.ps1 -OpenFolder` ;
3. le script exige un worktree CLEAN ;
4. `git fetch origin --prune` ;
5. fast-forward strict de la branche courante seulement ;
6. recherche d'un workflow iOS `success` pour **le HEAD exact** ;
7. téléchargement GitHub CLI de `ios-unsigned-<SHA exact>` ;
8. vérification `BUILD-METADATA.json.sha == HEAD` ;
9. vérification SHA-256 de l'IPA ;
10. rangement local dans `E:\_Project\IOS APP\ios-godot-lab\artifacts\<sha-court>\` ;
11. `LATEST.json` et `LATEST_IPA.txt` donnent le dernier artifact exact vérifié.

Si aucun build iOS réussi n'existe pour le HEAD exact : **STOP**, ne jamais récupérer silencieusement un autre SHA.

## Windows / arborescence canonique

```text
E:\_Project\IOS APP\
├── _Tools\
│   └── iloader\
└── ios-godot-lab\
    ├── main\
    ├── worktrees\
    └── artifacts\
```

Règle : 1 chantier = 1 branche = 1 worktree dédié.

Pour un gros bloc collé directement dans une console PowerShell interactive et contenant `if/else`, `try/catch`, fonctions ou boucles : envelopper tout le bloc dans `& { ... }`.

## SideStore / iLoader

- iLoader v2.3.1 installé et fonctionnel sur Windows ;
- l'iPhone est reconnu en USB ;
- SideStore Stable a été installé par iLoader ;
- profil développeur approuvé / SideStore vérifié ;
- Developer Mode actif ;
- LocalDevVPN actif quand nécessaire ;
- login SideStore bloque actuellement avec `The data couldn’t be read because it isn’t in the correct format` après le 2FA ; plusieurs serveurs Anisette ont déjà été testés ;
- classification : blocker upstream probable SideStore/Apple ; ne pas perdre du temps à boucler sur les serveurs ;
- iLoader `Import IPA` est le fallback actuellement utilisé pour signer/installer nos IPA exactes.

## VALIDÉ / NON VALIDÉ

**VALIDÉ UTILISATEUR / IPHONE — baseline 8899** : installation iLoader, présence et lancement de l'app.

**BUILD IOS VALIDÉ — V2 c3c85** : parse/smoke, plugin `IOSLab`, export Godot, Xcode iphoneos, paquet IPA unsigned.

**IMPLÉMENTÉ MAIS NON VALIDÉ SUR IPHONE — V2** : nouveau scroll, GPS/carte, BLE, caméra, micro, ARKit/LiDAR/NFC availability, HTTP/WS/UDP/OSC, télémétrie live et nouveau design.

## PROCHAIN TEST

1. intégrer/synchroniser le workflow `UPDATE_IOS_LAB.ps1` sur la branche V2 produit ;
2. attendre un build iOS `success` du HEAD exact qui contient ce workflow ;
3. sur Windows, créer/réutiliser le worktree V2 CLEAN ;
4. lancer `.\UPDATE_IOS_LAB.ps1 -OpenFolder` ;
5. installer l'IPA exacte affichée avec iLoader ;
6. vérifier le SHA visible dans l'app ;
7. tester d'abord le scroll sur les cartes ;
8. tester GPS + carte, BLE, caméra, micro et réseau ;
9. lancer `tools/Receive-IOSLabTelemetry.ps1 -Port 8787`, puis `Telemetry -> WebSocket -> <IP PC/Tailscale>:8787 -> START STREAM` ;
10. copier le log PowerShell dans ChatGPT et continuer les corrections à partir de télémétrie réelle.
