# ios-godot-lab — état projet consolidé

## But produit

Permettre de créer depuis Windows des applications iPhone Godot qui utilisent autant que possible les capacités publiques de l'iPhone, sans posséder de Mac et avec une chaîne de build/test personnel à coût nul.

## Architecture retenue et désormais prouvée jusqu'à l'IPA

```text
Windows
  Godot 4.7.2 + GDScript
        |
        | git push
        v
GitHub public
        |
        v
GitHub Actions / macOS standard / Xcode
        |
        | export Godot iOS -> Xcode
        | xcodebuild CODE_SIGNING_ALLOWED=NO
        v
IPA unsigned + manifest SHA
        |
        v
SideStore sur iPhone
        |
        | signature Personal Team gratuite
        v
iPhone réel
```

La partie **GitHub -> macOS -> Godot -> Xcode -> IPA unsigned** est validée exactement sur `8899a4bb4ad8addecf20a36d91b8d2055346cef5` (run `34160430197`). La partie **SideStore -> iPhone réel** reste à valider.

## Première preuve iOS durable

- SHA produit : `8899a4bb4ad8addecf20a36d91b8d2055346cef5` ;
- Godot : `4.7.2.stable.official.ed1daf0bf` ;
- Xcode : `26.6` ;
- iPhoneOS SDK : `26.5` ;
- cible : arm64 / iOS 16 minimum ;
- bundle : `com.rzbck.iosgodotlab` ;
- résultat : `BUILD SUCCEEDED` ;
- IPA : `IOSGodotLab-unsigned-8899a4bb4ad8.ipa` ;
- SHA-256 IPA : `40e8b799779de2a9cf6b8b0973e6308875d4006223cbceaa43b4f001c187e14d` ;
- artifact GitHub ID : `10032441877` ;
- signature : volontairement absente avant SideStore.

## Pourquoi cette architecture

- pas d'achat/location de Mac ;
- runners macOS standards gratuits pour repo public ;
- Godot garde la majorité du code cross-platform en GDScript ;
- Xcode n'existe que dans la CI ;
- SideStore enlève la dépendance quotidienne au PC pour le renouvellement 7 jours ;
- les APIs iOS manquantes côté Godot sont ajoutées par plugins natifs dédiés, sans réécrire toute l'app en Swift.

## Politique CI

- `verify-godot.yml` peut tourner automatiquement pour parse/smoke rapide ;
- `build-ios-unsigned.yml` est manuel via `workflow_dispatch` après bootstrap, car un build iOS télécharge Godot + les templates d'export et n'a pas besoin de tourner sur chaque changement documentaire ;
- chaque IPA doit contenir/annoncer le SHA exact de sa source ;
- un PASS d'un SHA ne valide jamais un autre SHA.

## Limites permanentes

### Apple gratuit

Personal Team :

- 10 App IDs maximum ;
- 3 appareils enregistrables ;
- 3 apps maximum par appareil ;
- profils de provisioning 7 jours.

SideStore compte parmi les apps installées.

### SideStore

- nécessite un ordinateur pour l'installation initiale ;
- utilise LocalDevVPN pour installer/rafraîchir ;
- tente des rafraîchissements périodiques en arrière-plan ;
- le scheduling de fond reste contrôlé par iOS, donc prévoir une vérification de l'état/expiration ;
- documentation actuelle : public beta.

### iOS

Une app n'a pas un accès arbitraire au matériel/système. Tout dépend :

- APIs publiques Apple ;
- permissions utilisateur ;
- entitlements/capabilities ;
- modèle exact d'iPhone ;
- restrictions sandbox et background ;
- restrictions de distribution/signature du Personal Team gratuit.

## Politique d'accès matériel

1. Utiliser d'abord l'API Godot officielle.
2. Si absent : écrire/ajouter un plugin iOS natif minimal.
3. Exposer une API GDScript stable, par exemple `IOSBridge.bluetooth_scan()` plutôt que disperser du code Swift partout.
4. Tester chaque capacité sur appareil réel et l'étiqueter séparément dans `docs/IOS_CAPABILITIES.md`.

## État de l'application

Le premier écran `iPhone Lab` est implémenté en portrait et expose déjà :

- build/SHA/plateforme ;
- tactile ;
- accéléromètre ;
- gravité ;
- gyroscope ;
- magnétomètre ;
- adresses réseau locales ;
- vibration handheld ;
- roadmap `IOSBridge`.

Le projet et le pipeline iOS sont buildables ; le comportement de ces fonctions sur matériel Apple reste à valider individuellement.

## Warnings à traiter avant activation caméra/micro/photo

Le premier Xcode build réussit avec des warnings indiquant des descriptions de permission Camera, Microphone et Photo Library vides. Ce n'est pas un blocker pour l'écran actuel, mais ces chaînes devront être renseignées avant de demander ces permissions sur iPhone.

## Réseau futur avec SIGNAL

La connexion avec SIGNAL n'est pas le chantier actuel, mais l'architecture la rend possible : sockets TCP/UDP/WebSocket/HTTP depuis Godot, Bonjour/Network Framework via plugin si découverte locale nécessaire, permissions Local Network iOS à déclarer.
