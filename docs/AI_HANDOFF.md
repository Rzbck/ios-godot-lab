# Handoff IA — état courant / reprise immédiate

Date : **2026-09-07**.

État : **première application Godot réelle implémentée ; chaîne Windows -> GitHub Actions macOS -> Godot iOS -> Xcode -> IPA unsigned VALIDÉE sur un SHA exact ; bootstrap local Windows et SideStore en cours ; aucune installation sur iPhone encore validée.**

> Porte d'entrée canonique : `/HANDOFF.md`.

## Git / point exact

- repo : `Rzbck/ios-godot-lab` ;
- `main` publié : `1a7c6e7b947cf2177eb56cbb43e924e7c39fd83f` ;
- branche de travail : `bootstrap/ios-foundation-20260907` ;
- premier écran app : `b530c3b718b19b0bb4468519e6ccba0a75eb9f8e` ;
- premier parse/smoke desktop validé : `bf7bfa29482704408fad7b994d4772b573480e49` ;
- **dernier produit BUILD IOS VALIDÉ : `8899a4bb4ad8addecf20a36d91b8d2055346cef5`** ;
- run iOS exact : `34160430197` ;
- artifact : `ios-unsigned-8899a4bb4ad8addecf20a36d91b8d2055346cef5` ;
- artifact ID : `10032441877` ;
- IPA : `IOSGodotLab-unsigned-8899a4bb4ad8.ipa` ;
- SHA-256 IPA : `40e8b799779de2a9cf6b8b0973e6308875d4006223cbceaa43b4f001c187e14d` ;
- **le HEAD courant de la branche n'est jamais auto-figé dans ce fichier** : toujours re-fetcher GitHub avant reprise, car des commits de documentation/tooling peuvent être postérieurs au dernier produit iOS validé.

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
2. Godot 4.7.2 stable = moteur verrouillé au bootstrap CI ; Godot local Windows existant peut servir au développement/smoke tant que la compatibilité est vérifiée.
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

## Bootstrap local Windows — état réel

Arborescence locale retenue :

```text
E:\_Project\IOS APP\
├── _Tools\
└── ios-godot-lab\
    ├── main\
    └── worktrees\
        └── bootstrap-ios-foundation\
```

État observé le 2026-09-07 :

- `main` local : `E:\_Project\IOS APP\ios-godot-lab\main` ;
- worktree actif : `E:\_Project\IOS APP\ios-godot-lab\worktrees\bootstrap-ios-foundation` ;
- branche du worktree : `bootstrap/ios-foundation-20260907` ;
- worktree synchronisé et CLEAN au moment du test ;
- Godot local réutilisé, **aucune réinstallation** : `C:\Godot\Godot_v4.7.1-stable_win64_console.exe` ;
- version locale observée : `4.7.1.stable.official.a13da4feb` ;
- import local : PASS ;
- `tests/smoke_project.gd` : `SMOKE_PASS` / PASS.

### Incident PowerShell interactif reproduit

Un gros bloc collé directement dans PowerShell avec `if { ... }` puis `else { ... }` sur des unités interactives distinctes a conduit PowerShell à exécuter le `if` avant de recevoir le `else`, puis à interpréter `else` comme une commande : `else: The term 'else' is not recognized...`.

Règle désormais permanente : tout gros bloc interactif avec `if / elseif / else`, `try / catch / finally`, fonctions ou boucles doit être enveloppé dans `& { ... }`. Voir `docs/POWERSHELL_WORKTREE_WORKFLOW.md`.

Deux autres pièges observés pendant ce bootstrap :

- Git peut renvoyer un chemin avec `/` alors que PowerShell utilise `\` : normaliser avant comparaison ;
- sous `Set-StrictMode`, certaines entrées registre n'ont pas `DisplayName` : tester l'existence de la propriété avant accès.

## Bootstrap SideStore — état réel

Sur l'iPhone :

- `LocalDevVPN` installé ;
- tunnel LocalDevVPN connecté.

Sur Windows :

- iTunes `12.13.10.3` a été téléchargé depuis le package `Apple.iTunes` via winget, installer Apple officiel ;
- hash de l'installer validé par winget ;
- installation iTunes annoncée réussie ;
- immédiatement après installation, `Apple Mobile Device Service` n'était pas encore visible avec `Get-Service` ;
- le script s'est arrêté volontairement à ce point avant iLoader ;
- **iloader n'est donc pas encore considéré installé/validé par cette session**.

Prochaine reprise SideStore : diagnostiquer la présence réelle de `Apple Mobile Device Service`/Apple Mobile Device Support après l'installation iTunes. Apple recommande un redémarrage Windows dans le diagnostic AMDS ; ne pas réinstaller iTunes à l'aveugle avant vérification. Une fois le support USB Apple visible et l'iPhone reconnu, reprendre l'installation officielle d'iloader puis SideStore.

## VALIDÉ

- **VALIDÉ DOC / ARCHITECTURE** : chaîne Windows/Godot/GitHub/SideStore documentée ; contraintes Apple gratuites documentées.
- **BUILD CI VALIDÉ (DESKTOP/HEADLESS)** : Godot 4.7.2 import/parse + smoke PASS.
- **BUILD IOS VALIDÉ** : `8899a4bb4ad8addecf20a36d91b8d2055346cef5`, run `34160430197`, export Godot PASS, Xcode Release iphoneos PASS, app confirmée unsigned, IPA créée et artifact uploadé.
- **VALIDÉ LOCAL WINDOWS** : Godot local 4.7.1 importe le projet et exécute le smoke test avec succès dans le worktree actif.
- **VALIDÉ SUR IPHONE** : rien pour l'instant.

## Incidents de bootstrap résolus

1. export Apple bloqué par la validation textures -> activation `textures/vram_compression/import_etc2_astc=true` ;
2. export iOS sans icône -> ajout `assets/icon.svg` + `application/config/icon` ;
3. Xcode 26.6 avec `-derivedDataPath` exige un scheme -> ajout `-scheme IOSGodotLab` + `generic/platform=iOS`.

Ces incidents sont résolus dans le SHA iOS validé.

## Limites / prochain nettoyage

Le build Xcode réussi contient encore des warnings non bloquants : descriptions Camera/Microphone/Photo Library vides et warning de template Godot sur le splash. Avant d'activer réellement caméra/micro/photo, renseigner les textes de permission et valider les prompts sur iPhone.

## PROCHAIN TEST

1. terminer le bootstrap SideStore Windows : vérifier AMDS/support USB Apple, puis installer iLoader officiel ;
2. installer/configurer SideStore sur l'iPhone ;
3. récupérer l'artifact exact du run `34160430197` ;
4. signer/installer `IOSGodotLab-unsigned-8899a4bb4ad8.ipa` ;
5. vérifier que l'app lance et affiche le SHA `8899a4bb4ad8` ;
6. tester tactile, mouvement réel (accéléromètre/gravity/gyro/magnétomètre) et vibration ;
7. seulement après, classer les capacités réellement observées en **VALIDÉ SUR IPHONE**.
