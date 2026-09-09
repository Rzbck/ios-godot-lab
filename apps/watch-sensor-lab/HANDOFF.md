# HANDOFF — Watch Sensor Lab

Date : **2026-09-09**

## Objectif

Créer une **nouvelle application** iPhone + Apple Watch, indépendante de `IOSGodotLab`, centrée sur la collecte, la synchronisation et l'enregistrement des données disponibles publiquement sur les deux appareils.

Premier usage produit visé : **tracking / recorder** d'une session réelle avec route, temps, distance, vitesse, altitude et données de mouvement, puis enrichissement progressif avec les données Apple Watch autorisées, par exemple la fréquence cardiaque pendant une session HealthKit.

Ce chantier ne doit pas reproduire l'UX, les pages ni la logique produit de `IOSGodotLab`. Seules les méthodes d'infrastructure déjà éprouvées peuvent servir de référence : GitHub Actions macOS, build exact-SHA, IPA unsigned, récupération Windows et installation iLoader.

## Identité chantier

- repository : `Rzbck/ios-godot-lab` ;
- application : `apps/watch-sensor-lab` ;
- branche : `feat/watch-sensor-lab-bootstrap-20260909` ;
- worktree Windows : `E:\_Project\IOS APP\ios-godot-lab\worktrees\watch-sensor-lab` ;
- base initiale : `main` au SHA `1a7c6e7b947cf2177eb56cbb43e924e7c39fd83f` ;
- dernier HEAD application avant cette mise à jour HANDOFF : `f539fe4105df43670158f980aab37fb19a1e560e` ;
- après cette mise à jour HANDOFF, toujours re-fetcher Git/GitHub avant modification.

## Architecture cible

```text
Apple Watch native watchOS
  Core Motion / Core Location / HealthKit selon permissions
                 |
                 | WatchConnectivity
                 v
iPhone native bridge
  Core Motion / Core Location / autres APIs iOS
                 |
                 v
Godot iPhone
  session recorder + visualisation + stockage/export
```

Principe de données : chaque échantillon doit être horodaté et identifier sa source (`iphone`, `watch`, `derived`) afin de pouvoir fusionner proprement les flux.

## État build / packaging validé

### Bootstrap séparé

SHA `3a16a663aee99f13ff21759c233ae5a2c056c637` : **BUILD CI VALIDÉ**.

- import/parse Godot : PASS ;
- export Godot iOS : PASS ;
- build Xcode iPhone unsigned : PASS ;
- build Xcode watchOS unsigned : PASS.

### Companion intégré

Le pipeline a ensuite été étendu pour produire une IPA iPhone unique contenant réellement :

```text
Payload/WatchSensorLab.app/Watch/WatchSensorLabWatch.app
```

Identités de base :

- iPhone `CFBundleIdentifier` : `com.rzbck.watchsensorlab` ;
- Watch `CFBundleIdentifier` : `com.rzbck.watchsensorlab.watchkitapp` ;
- Watch `WKCompanionAppBundleIdentifier` : `com.rzbck.watchsensorlab` ;
- Watch `WKRunsIndependentlyOfCompanionApp` : `false`.

L'app watchOS est un **single-target watchOS app** moderne et doit avoir :

```text
WKApplication = true
```

Correction application au SHA `f539fe4105df43670158f980aab37fb19a1e560e` : `WKApplication: true` ajouté dans la config Watch, avec garde-fou CI sur le `Info.plist` final.

## Historique des erreurs matérielles et corrections

### 1. Erreur `InvalidWatchKitApp`

Première installation sur vrai iPhone via iLoader :

```text
InvalidWatchKitApp
Found WatchKit 2.0 app .../WatchSensorLab.app/Watch/WatchSensorLabWatch.app
but it does not have a WKWatchKitApp or WKApplication key set to true in its Info.plist
```

Ce test a prouvé que l'app Watch était bien présente et détectée dans l'IPA.

Correction : `WKApplication = true` côté app Watch.

### 2. Erreur `InvalidCompanionAppBundleIdentifier`

Après correction `WKApplication`, iLoader a re-signé l'app iPhone en modifiant son bundle ID :

```text
com.rzbck.watchsensorlab
->
com.rzbck.watchsensorlab.<TEAM_ID>
```

mais l'app Watch gardait :

```text
WKCompanionAppBundleIdentifier = com.rzbck.watchsensorlab
```

Rejet réel observé :

```text
InvalidCompanionAppBundleIdentifier
... expected companion app bundle identifier com.rzbck.watchsensorlab.<TEAM_ID>
```

Conclusion : limitation dans `isideload`/iLoader, pas dans la structure IPA application.

## Chantier séparé iLoader / isideload

Deux forks dédiés ont été créés ; ils ne font pas partie du code produit Watch Sensor Lab et doivent rester séparés :

### `Rzbck/isideload`

- local : `E:\_Project\IOS APP\_Tools\iloader-watch\isideload`
- branche : `feat/watch-companion-support-20260909`
- baseline exact utilisée par iLoader 2.3.1 : `3d42025ecac97a2548d5b88aefc8028307e369c1`
- patch Watch code validé au SHA : `04d25c73742d29c2b8936c6f95741f22640ef6da`
- CI run : `34366333338`
- résultat : **SUCCESS macOS + Linux + Windows**, tests + builds + artifacts.

Patch générique :

- détecte `Watch/*.app` ;
- réécrit `CFBundleIdentifier` Watch ;
- réécrit `WKCompanionAppBundleIdentifier` ;
- inclut la Watch dans App-ID registration/provisioning ;
- persiste les `Info.plist` réécrits avant signature ;
- ajoute un test de régression de la réécriture coordonnée main app / Watch.

Un `HANDOFF.md` dédié existe maintenant dans ce fork et doit être lu avant reprise du chantier tooling.

### `Rzbck/iloader`

- local : `E:\_Project\IOS APP\_Tools\iloader-watch\iloader`
- branche : `feat/watch-companion-support-20260909`
- baseline iLoader 2.3.1 : `8547013c50b86087fb542bc14aafa4c6c60e6638`
- code iLoader testé : `2f026f437e973577c4ea0431b5206fb5a2156fe0`
- dépendance pin exacte vers `Rzbck/isideload` SHA `04d25c73742d29c2b8936c6f95741f22640ef6da`
- CI run : `34367071071`
- résultat : **SUCCESS**, y compris Windows `Build` + `Upload Windows EXE`.

Artifact Windows :

- `windows-exe`
- artifact id `10110888972`
- setup `nsis/iloader_2.3.1_x64-setup.exe`
- setup SHA-256 vérifié : `cd1d4d2ebf58754ecf734a8702e210cf26925b218cce92f7b69d8e43c6ce5eb4`.

Un `HANDOFF.md` dédié existe maintenant dans ce fork.

## Validation matérielle actuelle

Avec **iLoader patché** + l'IPA Watch Sensor Lab corrigée :

### iPhone

- iLoader affiche que la signature/installation est terminée ;
- l'app Watch Sensor Lab est **installée sur le vrai iPhone** ;
- l'utilisateur confirme que l'app iPhone **se lance/fonctionne**.

Classification : **IPHONE PHYSICALLY VALIDATED FOR INSTALL/LAUNCH**.

### Apple Watch

La companion apparaît côté Watch, mais :

- elle n'a pas encore d'icône correcte ;
- quand l'utilisateur tente de l'installer/lancer sur la vraie montre, watchOS affiche :

> Impossible d'installer Watch Sensor Lab — cette app ne peut pas être installée car son intégrité n'a pas pu être vérifiée.

Donc : **APPLE WATCH INSTALLATION NOT YET VALIDATED**.

Le fait que l'erreur précédente `InvalidCompanionAppBundleIdentifier` ne soit plus observée après le patch iLoader est un progrès matériel réel, mais ne prouve pas encore que le provisioning Watch est correct.

## Hypothèse actuelle sur l'échec d'intégrité Watch — À CONFIRMER

Inspection du flow `isideload` : `Sideloader::install_app()` enregistre actuellement uniquement l'appareil directement connecté, donc l'iPhone, via `IdeviceInfo::from_device(device_provider)` puis `ensure_device_registered(...)`.

Le patch Watch actuel ne découvre/enregistre pas encore explicitement l'UDID de l'Apple Watch jumelée avant de télécharger le provisioning profile Watch.

Hypothèse principale :

- iPhone enregistré dans le compte Apple Developer : oui ;
- App ID Watch/profil Watch créé : probablement oui via le patch ;
- Apple Watch physique incluse comme device autorisé dans le provisioning profile Watch : **non vérifié et probablement manquant** ;
- résultat potentiel : rejet watchOS « intégrité non vérifiée ».

Ne pas présenter cette hypothèse comme prouvée tant que l'UDID Watch et le contenu du profil n'ont pas été inspectés.

## Developer Mode Apple Watch

Observation utilisateur réelle :

```text
Watch > Réglages > Confidentialité et sécurité
```

`Mode développeur` est **absent**, pas simplement désactivé.

Sans Mac/Xcode, un chemin Windows-only est recherché pour initier/inspecter la relation de développement avec la Watch.

## Investigation Windows `pymobiledevice3` en cours

But : utiliser l'iPhone USB comme pont vers les companion devices afin de :

1. lister l'iPhone ;
2. lister la Watch jumelée ;
3. récupérer un identifiant/UDID Watch si exposé ;
4. étudier ensuite le chemin Developer Mode / provisioning, sans mutation prématurée.

Dossier local :

```text
E:\_Project\IOS APP\_Tools\pymobiledevice3-watch
```

Un venv Python a été créé/tenté et :

```text
pip install -U pymobiledevice3
```

a été lancé.

État actuel exact : nombreuses erreurs réseau/DNS intermittentes :

```text
getaddrinfo failed
```

contre PyPI / l'index NVIDIA configuré, mais certaines métadonnées/packages ont commencé à être téléchargés ensuite. **Ne pas considérer `pymobiledevice3` comme installé tant que la commande n'a pas fini avec succès.**

Commandes read-only prévues une fois installé :

```text
pymobiledevice3 usbmux list
pymobiledevice3 companion list
```

## Icône Watch

L'app Watch apparaît actuellement sans icône correcte. C'est un problème séparé d'assets/catalogue watchOS. Ne pas le confondre avec l'erreur d'intégrité. À corriger après ou en parallèle une fois la chaîne d'installation Watch validée.

## Synchronisation Windows de l'IPA produit

Script :

```text
apps/watch-sensor-lab/UPDATE_WATCH_SENSOR_LAB.ps1
```

Il reste le workflow normal pour récupérer l'IPA exact-SHA Watch Sensor Lab :

- worktree/branche vérifiés ;
- refuse DIRTY ;
- fast-forward strict ;
- workflow exact HEAD ;
- artifact exact-SHA ;
- metadata + SHA-256 vérifiés ;
- cache dédié `artifacts/watch-sensor-lab/...`.

Ne pas créer un second downloader concurrent.

## Données visées progressivement

### iPhone
- position GPS, précision, altitude ;
- vitesse, précision vitesse, course/cap ;
- accéléromètre, gyroscope, gravity, attitude/device motion ;
- magnétomètre et baromètre/altimètre quand disponibles ;
- informations de session et état appareil utiles au diagnostic.

### Apple Watch
- accéléromètre, gyroscope, device motion ;
- pedometer / cadence / mouvement quand exposés et pertinents ;
- altitude/baromètre quand disponibles ;
- position/vitesse quand disponible et pertinente ;
- fréquence cardiaque et métriques workout via HealthKit uniquement après autorisation utilisateur.

### Dérivées
- distance cumulée ;
- durée ;
- vitesse instantanée/moyenne/max ;
- allure ;
- dénivelé positif/négatif ;
- route / trace ;
- qualité des mesures et trous de données ;
- statistiques de synchronisation Watch <-> iPhone.

## PAS encore validé

- installation réussie de Watch Sensor Lab sur la vraie Apple Watch ;
- lancement réel sur Apple Watch ;
- Developer Mode visible/actif sur la Watch ;
- récupération de l'UDID Watch depuis Windows ;
- présence effective de l'UDID Watch dans le provisioning profile ;
- cause exacte du message d'intégrité ;
- icône Watch correcte ;
- bridge WatchConnectivity côté iPhone/Godot ;
- données réelles Watch -> iPhone -> Godot ;
- tracking réel complet ;
- HealthKit.

## Prochaine étape exacte

1. terminer ou relancer l'installation `pymobiledevice3` si le DNS a interrompu `pip` ;
2. iPhone USB connecté/déverrouillé + Watch proche/déverrouillée ;
3. lancer les commandes read-only `usbmux list` puis `companion list` ;
4. vérifier si la Watch et son identifiant/UDID sont visibles ;
5. déterminer le chemin Windows sûr pour Developer Mode ;
6. confirmer ou infirmer l'hypothèse de provisioning Watch sans UDID ;
7. si confirmé, patcher **le fork `Rzbck/isideload`**, pas l'app produit, pour enregistrer/provisionner aussi la Watch ;
8. CI exact-SHA ;
9. rebuild `Rzbck/iloader` exact-SHA ;
10. retest réel iPhone + Apple Watch ;
11. seulement après installation/lancement Watch réel, poursuivre WatchConnectivity/recorder et préparer éventuellement un PR upstream tooling.

## Ne pas modifier depuis ce chantier

- `iphone-lab-v2` ;
- `feat/iphone-lab-v2-20260908` ;
- workflow/artifacts/`UPDATE_IOS_LAB.ps1` de l'ancienne application ;
- upstream `nab138/isideload` / `nab138/iloader` directement ;
- `main` sans accord explicite ;
- ne jamais hard-coder le Team ID utilisateur dans l'app ou les outils génériques.
