# Handoff IA — état courant / reprise immédiate

Date : **2026-09-07**.

État : **première application Godot réelle implémentée ; chaîne Windows -> GitHub Actions macOS -> Godot iOS -> Xcode -> IPA unsigned VALIDÉE sur un SHA exact ; aucune installation sur iPhone encore validée.**

> Porte d'entrée canonique : `/HANDOFF.md`.

## Git / point exact

- repo : `Rzbck/ios-godot-lab` ;
- `main` publié : `1a7c6e7b947cf2177eb56cbb43e924e7c39fd83f` ;
- branche de travail : `bootstrap/ios-foundation-20260907` ;
- **HEAD documentaire/tooling au moment de ce handoff : `e4da527dfbfbc07ff8a238dae8f841a551b16486`** ;
- premier écran app : `b530c3b718b19b0bb4468519e6ccba0a75eb9f8e` ;
- premier parse/smoke desktop validé : `bf7bfa29482704408fad7b994d4772b573480e49` ;
- **dernier produit BUILD IOS VALIDÉ : `8899a4bb4ad8addecf20a36d91b8d2055346cef5`** ;
- run iOS exact : `34160430197` ;
- artifact : `ios-unsigned-8899a4bb4ad8addecf20a36d91b8d2055346cef5` ;
- artifact ID : `10032441877` ;
- IPA : `IOSGodotLab-unsigned-8899a4bb4ad8.ipa` ;
- SHA-256 IPA : `40e8b799779de2a9cf6b8b0973e6308875d4006223cbceaa43b4f001c187e14d` ;
- toujours re-fetcher le HEAD courant de branche avant toute reprise : des commits de documentation/tooling peuvent être postérieurs au dernier produit iOS validé.

## Toolchain iOS réellement validée

- runner : `macos-26` / Apple Silicon ;
- macOS runner observé : `26.6.2` ;
- Godot : `4.7.2.stable.official.ed1daf0bf` ;
- Xcode : `26.6` (`17F113`) ;
- iPhoneOS SDK : `26.5` ;
- cible Xcode : `arm64-apple-ios16.0` ;
- bundle identifier : `com.rzbck.iosgodotlab` ;
- signature Xcode : désactivée volontairement (`CODE_SIGNING_ALLOWED=NO`) ;
- résultat Xcode : `BUILD SUCCEEDED` ;
- assertion CI : le `.app` doit échouer à `codesign --verify`, sinon le job échoue ;
- packaging : `Payload/IOSGodotLab.app` -> `.ipa` -> SHA-256 -> artifact GitHub.

Le `application/app_store_team_id="0000000000"` du preset est un **placeholder non secret** utilisé uniquement pour satisfaire le validateur d'export Godot avant la compilation unsigned. Il n'est jamais présenté comme un vrai Team ID Apple.

## Décisions retenues

1. Windows = machine de développement principale.
2. Godot 4.7.2 stable = moteur verrouillé au bootstrap.
3. GitHub public = source + CI.
4. GitHub Actions standard macOS = Mac cloud gratuit pour export/compilation iOS.
5. Pipeline validé = export Godot -> projet Xcode -> `xcodebuild` sans signature -> paquet `.ipa` -> artifact GitHub.
6. Le workflow iOS est **manuel (`workflow_dispatch`)** après validation du bootstrap, pour ne pas lancer un Mac sur chaque petit commit.
7. SideStore = sideload principal gratuit, pour signature Personal Team et rafraîchissement périodique des profils 7 jours après installation initiale.
8. TestFlight/App Store ne font pas partie de la chaîne 0 €.
9. Accès iPhone = APIs Godot natives quand disponibles + un bridge iOS natif ciblé pour les frameworks Apple publics supplémentaires.

## Application actuelle

`project.godot` lance `scenes/main.tscn` / `scripts/main.gd` en portrait.

L'écran `iPhone Lab` contient déjà :

- identité build/version/plateforme ;
- compteur tactile et dernière position d'input ;
- accélération, gravité, gyroscope et magnétomètre en live ;
- adresses réseau locales exposées ;
- test de vibration handheld ;
- roadmap visible des capacités directes et futures via `IOSBridge` ;
- icône d'application versionnée dans `assets/icon.svg`.

La CI iOS remplace éphémèrement `config/build_info.json` avec le SHA exact avant export ; ce SHA est donc visible dans l'application construite.

## VALIDÉ

- **VALIDÉ DOC / ARCHITECTURE** : chaîne Windows/Godot/GitHub/SideStore documentée ; contraintes Apple gratuites documentées.
- **BUILD CI VALIDÉ (DESKTOP/HEADLESS)** : Godot 4.7.2 import/parse + smoke PASS.
- **BUILD IOS VALIDÉ** : `8899a4bb4ad8addecf20a36d91b8d2055346cef5`, run `34160430197`, export Godot PASS, Xcode Release iphoneos PASS, app confirmée unsigned, IPA créée et artifact uploadé.
- **VALIDÉ SUR IPHONE** : rien pour l'instant.

## Incidents de bootstrap résolus

1. export Apple bloqué par la validation textures -> activation `textures/vram_compression/import_etc2_astc=true` ;
2. export iOS sans icône -> ajout `assets/icon.svg` + `application/config/icon` ;
3. Xcode 26.6 avec `-derivedDataPath` exige un scheme -> ajout `-scheme IOSGodotLab` + `generic/platform=iOS`.

Ces incidents sont résolus dans le SHA iOS validé.

## Limites / prochain nettoyage

Le build Xcode réussi contient encore des warnings non bloquants : descriptions Camera/Microphone/Photo Library vides et warning de template Godot sur le splash. Avant d'activer réellement caméra/micro/photo, renseigner les textes de permission et valider les prompts sur iPhone.

## PROCHAIN TEST

1. installer/configurer SideStore sur l'iPhone ;
2. récupérer l'artifact exact du run `34160430197` ;
3. signer/installer `IOSGodotLab-unsigned-8899a4bb4ad8.ipa` ;
4. vérifier que l'app lance et affiche le SHA `8899a4bb4ad8` ;
5. tester tactile, mouvement réel (accéléromètre/gravity/gyro/magnétomètre) et vibration ;
6. seulement après, classer les capacités réellement observées en **VALIDÉ SUR IPHONE**.
