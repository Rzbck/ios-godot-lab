# Build iOS gratuit + sideload — stratégie retenue

Date de recherche initiale : 2026-09-07.

## Solution principale

**Windows + Godot + GitHub Actions macOS + IPA unsigned + SideStore.**

## État : chaîne jusqu'à l'IPA réellement validée

La partie build n'est plus théorique. Elle est **BUILD IOS VALIDÉE** sur le SHA exact :

`8899a4bb4ad8addecf20a36d91b8d2055346cef5`

Preuve :

- GitHub Actions run `34160430197` ;
- Godot `4.7.2.stable.official.ed1daf0bf` ;
- Xcode `26.6` (`17F113`) ;
- iPhoneOS SDK `26.5` ;
- cible `arm64-apple-ios16.0` ;
- `BUILD SUCCEEDED` ;
- app volontairement unsigned, vérifiée par la CI ;
- IPA `IOSGodotLab-unsigned-8899a4bb4ad8.ipa` ;
- SHA-256 IPA `40e8b799779de2a9cf6b8b0973e6308875d4006223cbceaa43b4f001c187e14d` ;
- artifact GitHub `ios-unsigned-8899a4bb4ad8addecf20a36d91b8d2055346cef5`, ID `10032441877`.

Cette preuve ne vaut **pas** `VALIDÉ SUR IPHONE` tant que cette IPA exacte n'a pas été signée/installée/lancée sur le vrai téléphone.

## Pipeline désormais utilisé

Le workflow `.github/workflows/build-ios-unsigned.yml` est déclenché manuellement via `workflow_dispatch` après le bootstrap.

Il effectue :

1. checkout du SHA exact ;
2. identité du runner macOS/Xcode/SDK ;
3. téléchargement de Godot 4.7.2 + templates correspondants ;
4. stamp éphémère de `config/build_info.json` avec le SHA exact ;
5. import Godot ;
6. export iOS project-only vers Xcode ;
7. `xcodebuild` Release, scheme `IOSGodotLab`, `generic/platform=iOS` ;
8. `CODE_SIGNING_ALLOWED=NO`, `CODE_SIGNING_REQUIRED=NO`, identité/team vides ;
9. assertion que `codesign --verify` échoue ;
10. empaquetage `Payload/*.app` en IPA ;
11. génération `BUILD-METADATA.json` + SHA-256 ;
12. upload artifact GitHub.

Le preset Godot contient `application/app_store_team_id="0000000000"` uniquement comme **placeholder non secret** pour satisfaire le validateur d'export Godot. Ce n'est pas un Team ID Apple réel et Xcode compile ensuite avec team/signature vides.

## Correctifs découverts par le vrai build

### ETC2/ASTC

L'export Apple Embedded refusait initialement la configuration. Le projet fixe maintenant :

`textures/vram_compression/import_etc2_astc=true`

### Icône iOS

L'export iOS exigeait une source d'icône. `assets/icon.svg` est versionné et référencé par `application/config/icon`; Godot génère ensuite les variantes AppIcon.

### Xcode 26.6

Avec `-derivedDataPath`, Xcode 26.6 exige un scheme explicite. Le workflow utilise donc `-scheme IOSGodotLab` et `-destination 'generic/platform=iOS'`.

## Warnings non bloquants actuels

Le premier build réussi signale encore :

- `NSCameraUsageDescription` vide ;
- `NSMicrophoneUsageDescription` vide ;
- `NSPhotoLibraryUsageDescription` vide ;
- warning de template Godot sur `application/boot_splash/fullsize` ;
- warning `#pragma once` dans le dummy header généré.

Les warnings de template n'empêchent pas le build. Les descriptions Camera/Micro/Photo devront être renseignées **avant d'activer et tester ces permissions sur iPhone**.

## Pourquoi GitHub Actions

GitHub documente que les runners standards sont gratuits pour les repositories publics. Les runners macOS Apple Silicon standards sont disponibles, avec Xcode préinstallé.

Source : https://docs.github.com/en/actions/reference/runners/github-hosted-runners

## Pourquoi un IPA unsigned

Le compte Apple gratuit est utilisé au moment du sideload, pas dans la CI. Aucun certificat Apple privé n'a donc besoin d'être stocké sur GitHub.

## Godot

Version de base choisie : **4.7.2 stable** (maintenance release du 18 août 2026).

Godot demande officiellement macOS + Xcode pour l'export iOS. Notre runner GitHub remplit cette exigence.

Sources :

- https://godotengine.org/article/maintenance-release-godot-4-7-2/
- https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_ios.html

## SideStore — choix retenu

SideStore re-signe les apps avec un certificat de développement personnel et documente un rafraîchissement périodique en arrière-plan afin de conserver la période de développement de 7 jours.

Avantage clé : après installation initiale, le PC n'est normalement plus nécessaire pour les refresh.

Contraintes :

- SideStore inclus dans la limite de 3 apps ;
- LocalDevVPN nécessaire lors des opérations d'installation/refresh ;
- iOS décide du scheduling réel en arrière-plan ; contrôler l'expiration dans l'app SideStore ;
- utiliser de préférence anisette v3 officiel ou auto-hébergé.

Sources :

- https://docs.sidestore.io/docs/faq
- https://docs.sidestore.io/docs/installation/prerequisites
- https://docs.sidestore.io/docs/advanced/anisette

## Limites Apple gratuites

Apple Personal Team :

- 10 App IDs, expiration 7 jours ;
- jusqu'à 3 appareils, expiration 7 jours ;
- jusqu'à 3 apps installées par appareil ;
- provisioning profile 7 jours.

Source : https://developer.apple.com/help/account/basics/about-your-developer-account

## Alternatives écartées comme défaut

### Sideloadly

Bon outil Windows, mais le rafraîchissement dépend davantage du PC. À garder en fallback/debug.

### AltStore Classic

Solide, mais l'expérience habituelle dépend d'AltServer sur le PC pour les refresh. SideStore est mieux adapté à l'objectif « ne rien faire tous les 7 jours ».

### TestFlight

Excellent pour bêta/distribution, mais nécessite l'Apple Developer Program payant ; hors objectif 0 €.

### Mac cloud payant / AWS EC2 Mac / MacStadium

Inutile pour le bootstrap car le repo public donne accès aux runners standards macOS GitHub gratuitement.

## Prochaine étape

SideStore -> récupérer l'artifact exact -> signer/installer l'IPA -> lancer -> vérifier le SHA affiché -> tester tactile/capteurs/haptique -> seulement alors marquer les capacités observées **VALIDÉ SUR IPHONE**.
