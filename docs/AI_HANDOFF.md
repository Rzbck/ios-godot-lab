# Handoff IA — état courant / reprise immédiate

Date : **2026-09-07**.

État : **bootstrap de l'architecture du projet en cours sur branche dédiée ; aucun build iOS ni test iPhone encore validé.**

> Porte d'entrée canonique : `/HANDOFF.md`.

## Git / point exact

- repo : `Rzbck/ios-godot-lab` ;
- `main` bootstrap : `1a7c6e7b947cf2177eb56cbb43e924e7c39fd83f` au moment de la création de cette branche ;
- branche de travail : `bootstrap/ios-foundation-20260907` ;
- le HEAD de branche doit toujours être re-fetché avant reprise.

## Décisions retenues

1. Windows = machine de développement principale.
2. Godot = moteur principal.
3. GitHub public = source + CI.
4. GitHub Actions standard macOS = Mac cloud gratuit pour export/compilation iOS.
5. Pipeline visé = export Godot -> projet Xcode -> `xcodebuild` sans signature -> paquet `.ipa` -> artifact GitHub.
6. SideStore = sideload principal gratuit, pour rafraîchissement périodique 7 jours sans PC après installation initiale.
7. TestFlight/App Store ne font pas partie de la chaîne 0 €.
8. Accès iPhone = APIs Godot natives quand disponibles + plugins iOS natifs pour CoreBluetooth/CoreMotion/AVFoundation/CoreNFC/ARKit/etc. si nécessaire.

## VALIDÉ

- **VALIDÉ DOC / ARCHITECTURE** : runners macOS GitHub standards gratuits sur repo public ; contraintes Apple Personal Team 7 jours / 3 apps / 10 App IDs ; SideStore documente le refresh périodique en arrière-plan.
- **VALIDÉ SUR IPHONE** : rien pour l'instant.
- **BUILD CI VALIDÉ** : rien pour l'instant.

## BLOCKERS / données encore nécessaires

- créer le projet Godot minimal ;
- définir un bundle identifier ;
- résoudre proprement le Team ID requis par l'exporteur Godot iOS ;
- ajouter puis exécuter le workflow iOS unsigned exact-SHA ;
- installer/configurer SideStore sur l'iPhone ;
- installer la première IPA et valider le lancement réel.

## PROCHAIN TEST

Créer sur Windows un clone/worktree dédié de cette branche via PowerShell, générer l'app Godot minimale, puis faire le premier build GitHub Actions iOS unsigned.
