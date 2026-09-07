# Build iOS gratuit + sideload — stratégie retenue

Date de recherche initiale : 2026-09-07.

## Solution principale

**Windows + Godot + GitHub Actions macOS + IPA unsigned + SideStore.**

### Pourquoi GitHub Actions

GitHub documente que les runners standards sont gratuits pour les repositories publics. Les runners macOS Apple Silicon standards sont disponibles, avec Xcode préinstallé.

Source : https://docs.github.com/en/actions/reference/runners/github-hosted-runners

### Pourquoi un IPA unsigned

Le compte Apple gratuit est utilisé au moment du sideload, pas dans la CI. La CI doit pouvoir compiler sans certificat Apple privé stocké sur GitHub.

Pattern `xcodebuild` à valider sur notre projet :

```bash
xcodebuild archive \
  -project build/ios/MyApp.xcodeproj \
  -scheme MyApp \
  -archivePath build/ios/App.xcarchive \
  -configuration Release \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO
```

Puis :

```bash
mkdir -p Payload
cp -R App.xcarchive/Products/Applications/*.app Payload/
zip -r MyApp.ipa Payload
```

Ce pattern existe dans des pipelines communautaires Godot unsigned ; il doit être **validé chez nous avant d'être classé BUILD CI VALIDÉ**.

## Godot

Version de base choisie : **4.7.2 stable** (maintenance release du 18 août 2026).

Godot demande officiellement macOS + Xcode pour l'export iOS. Notre runner GitHub remplit cette exigence.

L'exporteur demande notamment :

- bundle identifier ;
- App Store Team ID au format 10 caractères.

Le traitement propre du Team ID pour notre build unsigned reste un point à résoudre/valider avant premier build.

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
