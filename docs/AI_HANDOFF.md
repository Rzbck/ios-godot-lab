# Handoff IA — état courant / reprise immédiate

Date : **2026-09-07**.

État : **première application Godot réelle implémentée et validée mécaniquement par CI Godot 4.7.2 ; aucun build iOS/macOS ni test iPhone encore validé.**

> Porte d'entrée canonique : `/HANDOFF.md`.

## Git / point exact

- repo : `Rzbck/ios-godot-lab` ;
- `main` publié : `1a7c6e7b947cf2177eb56cbb43e924e7c39fd83f` ;
- branche de travail : `bootstrap/ios-foundation-20260907` ;
- premier écran app : `b530c3b718b19b0bb4468519e6ccba0a75eb9f8e` ;
- CI parse/smoke ajoutée : `bf7bfa29482704408fad7b994d4772b573480e49` ;
- run GitHub Actions `34159830420` : `Parse and smoke` = PASS sur `bf7bfa29...` ;
- le HEAD courant de branche doit toujours être re-fetché avant reprise.

## Décisions retenues

1. Windows = machine de développement principale.
2. Godot 4.7.2 stable = moteur verrouillé au bootstrap.
3. GitHub public = source + CI.
4. GitHub Actions standard macOS = Mac cloud gratuit visé pour export/compilation iOS.
5. Pipeline visé = export Godot -> projet Xcode -> `xcodebuild` sans signature -> paquet `.ipa` -> artifact GitHub.
6. SideStore = sideload principal gratuit, pour rafraîchissement périodique des profils 7 jours après installation initiale.
7. TestFlight/App Store ne font pas partie de la chaîne 0 €.
8. Accès iPhone = APIs Godot natives quand disponibles + un bridge iOS natif ciblé pour les frameworks Apple publics supplémentaires.

## Application actuelle

`project.godot` lance `scenes/main.tscn` / `scripts/main.gd` en portrait.

L'écran `iPhone Lab` contient déjà :

- identité build/version/plateforme ;
- compteur tactile et dernière position d'input ;
- accélération, gravité, gyroscope et magnétomètre en live ;
- adresses réseau locales exposées ;
- test de vibration handheld ;
- roadmap visible des capacités directes et futures via `IOSBridge`.

Le build local lit `config/build_info.json`. La CI iOS devra remplacer ce manifeste de façon éphémère avec le SHA exact avant export.

## VALIDÉ

- **VALIDÉ DOC / ARCHITECTURE** : chaîne Windows/Godot/GitHub/SideStore documentée ; contraintes Apple gratuites documentées.
- **BUILD CI VALIDÉ (DESKTOP/HEADLESS)** : Godot 4.7.2 téléchargé, version vérifiée, import/parse PASS, `tests/smoke_project.gd` PASS sur `bf7bfa29482704408fad7b994d4772b573480e49`.
- **VALIDÉ SUR IPHONE** : rien pour l'instant.
- **BUILD IOS VALIDÉ** : rien pour l'instant.

## BLOCKERS / données encore nécessaires

- définir un bundle identifier durable ;
- produire un preset iOS Godot 4.7.2 correct ;
- résoudre proprement le Team ID exigé ou non par chaque étape de l'export unsigned ;
- ajouter puis exécuter le workflow macOS/Xcode exact-SHA ;
- produire la première IPA unsigned ;
- installer/configurer SideStore sur l'iPhone ;
- signer/installer la première IPA et valider lancement + tactile + capteurs réels.

## PROCHAIN TEST

Sur Windows : créer/réutiliser le worktree dédié de `bootstrap/ios-foundation-20260907`, ouvrir le projet avec Godot 4.7.2 et vérifier visuellement l'UI. En parallèle repo : préparer le preset iOS minimal et le workflow macOS unsigned, sans promotion `main` avant preuve.
