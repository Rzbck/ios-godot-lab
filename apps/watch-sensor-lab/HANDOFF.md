# HANDOFF — Watch Sensor Lab

Date : **2026-09-09**.

## Objectif

Créer une **nouvelle application** iPhone + Apple Watch, indépendante de `IOSGodotLab`, centrée sur la collecte, la synchronisation et l'enregistrement des données disponibles publiquement sur les deux appareils.

Premier usage produit visé : **tracking / recorder** d'une session réelle avec route, temps, distance, vitesse, altitude et données de mouvement, puis enrichissement progressif avec les données Apple Watch autorisées, par exemple la fréquence cardiaque pendant une session HealthKit.

Ce chantier ne doit pas reproduire l'UX, les pages ni la logique produit de `IOSGodotLab`. Seules les méthodes d'infrastructure déjà éprouvées peuvent servir de référence : GitHub Actions macOS, build exact-SHA, IPA unsigned, récupération Windows et installation iLoader.

## Identité chantier

- repository : `Rzbck/ios-godot-lab` ;
- application : `apps/watch-sensor-lab` ;
- branche : `feat/watch-sensor-lab-bootstrap-20260909` ;
- worktree Windows : `E:\\_Project\\IOS APP\\ios-godot-lab\\worktrees\\watch-sensor-lab` ;
- base initiale : `main` au SHA `1a7c6e7b947cf2177eb56cbb43e924e7c39fd83f` ;
- HEAD courant : toujours re-fetcher Git/GitHub avant modification.

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

## État CI validé

### Bootstrap séparé

SHA `3a16a663aee99f13ff21759c233ae5a2c056c637` : **BUILD CI VALIDÉ**.

- import/parse Godot : PASS ;
- export Godot iOS : PASS ;
- build Xcode iPhone unsigned : PASS ;
- build Xcode watchOS unsigned : PASS.

### Companion intégré avant validation matérielle

SHA `fc484f61a27e6cca9e6f255c75194402ad3e4291` : **BUILD CI VALIDÉ**.

- workflow run : `34360880180` ;
- build iPhone : PASS ;
- build watchOS : PASS ;
- assemblage companion : PASS ;
- packaging IPA : PASS ;
- artifact : `watch-sensor-lab-companion-fc484f61a27e6cca9e6f255c75194402ad3e4291` ;
- IPA : `WatchSensorLab-companion-unsigned-fc484f61a27e.ipa` ;
- SHA-256 IPA : `7369f40a19f6f74e322d1620c81351feb3ca6fe6cdfebc07d7d0fdb9d968a31e`.

Inspection de l'artifact confirmée :

```text
Payload/WatchSensorLab.app/Watch/WatchSensorLabWatch.app/Info.plist
```

Identités vérifiées :

- iPhone `CFBundleIdentifier` : `com.rzbck.watchsensorlab` ;
- Watch `CFBundleIdentifier` : `com.rzbck.watchsensorlab.watchkitapp` ;
- Watch `WKCompanionAppBundleIdentifier` : `com.rzbck.watchsensorlab` ;
- Watch `WKRunsIndependentlyOfCompanionApp` : `false`.

Classification : **CI ASSEMBLED COMPANION - HARDWARE NOT VALIDATED**.

## Résultat matériel iLoader

Test utilisateur réel : iLoader a bien importé l'IPA et l'installation a atteint `installd` sur l'iPhone, mais l'installation a été refusée avec :

```text
InvalidWatchKitApp
Found WatchKit 2.0 app .../WatchSensorLab.app/Watch/WatchSensorLabWatch.app
but it does not have a WKWatchKitApp or WKApplication key set to true in its Info.plist
```

Conclusion :

- l'app Watch embarquée est bien détectée par iOS ;
- le blocker courant est structurel dans le `Info.plist` watchOS ;
- la Watch app est un **single-target watchOS app**, donc la correction retenue est `WKApplication = true` ;
- le workflow doit maintenant vérifier explicitement cette clé avant de produire une IPA.

Ce test matériel **ne valide pas encore** la signature imbriquée ni l'installation finale sur Apple Watch ; il valide seulement que l'IPA a atteint le validateur d'installation iOS et que le rejet actuel est précisément identifié.

## Synchronisation Windows dédiée

Script :

```text
apps/watch-sensor-lab/UPDATE_WATCH_SENSOR_LAB.ps1
```

Il reprend la discipline du updater iOS déjà validé sans modifier celui de l'ancienne app :

- exige le worktree/branche Watch Sensor Lab ;
- refuse un worktree DIRTY ;
- fast-forward strict seulement ;
- cherche ou déclenche le workflow pour le HEAD exact ;
- télécharge uniquement `watch-sensor-lab-companion-<SHA exact>` ;
- vérifie `BUILD-METADATA.json` ;
- exige `watch_companion_integrated_in_ipa = true` ;
- vérifie le SHA-256 de l'IPA ;
- range les fichiers dans `artifacts/watch-sensor-lab/<sha-court>/` ;
- prépare `LATEST.json` et `LATEST_IPA.txt` pour iLoader.

Le script a été utilisé par l'utilisateur pour récupérer l'IPA testée avec iLoader ; le prochain test doit utiliser le nouveau SHA corrigé.

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

`Tout récupérer` signifie : exploiter au maximum les APIs publiques réellement disponibles sur les appareils, avec leurs permissions et limites. Cela ne signifie pas accès arbitraire aux données privées/système.

## PAS encore validé

- CI du correctif `WKApplication = true` ;
- signature iLoader des bundles imbriqués jusqu'au bout ;
- installation de l'IPA corrigée sur iPhone ;
- apparition/installation de la companion app dans l'app Watch de l'iPhone ;
- lancement réel sur Apple Watch ;
- bridge WatchConnectivity côté iPhone/Godot ;
- données réelles Watch -> iPhone -> Godot ;
- tracking réel sur appareil ;
- HealthKit.

## Prochaine étape exacte

1. obtenir un CI vert avec `WKApplication = true` présent dans le `Info.plist` watchOS final ;
2. synchroniser le worktree Windows au nouveau HEAD exact ;
3. lancer `apps\\watch-sensor-lab\\UPDATE_WATCH_SENSOR_LAB.ps1 -OpenFolder` ;
4. signer/installer l'IPA exacte avec iLoader ;
5. vérifier que la nouvelle app iPhone se lance ;
6. ouvrir l'app Watch sur l'iPhone et vérifier si `Watch Sensor Lab` apparaît comme companion installable ;
7. installer/lancer sur la vraie Apple Watch ;
8. si ce jalon matériel passe, implémenter le receiver WatchConnectivity iPhone -> Godot ;
9. ensuite construire le recorder GPS/motion puis HealthKit.

## Ne pas modifier depuis ce chantier

- `iphone-lab-v2` ;
- `feat/iphone-lab-v2-20260908` ;
- le workflow/artifacts/`UPDATE_IOS_LAB.ps1` de cette ancienne application, sauf demande utilisateur explicite distincte.
