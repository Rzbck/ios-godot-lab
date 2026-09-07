# ios-godot-lab — état projet consolidé

## But produit

Permettre de créer depuis Windows des applications iPhone Godot qui utilisent autant que possible les capacités publiques de l'iPhone, sans posséder de Mac et avec une chaîne de build/test personnel à coût nul.

## Architecture retenue

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

## Pourquoi cette architecture

- pas d'achat/location de Mac ;
- runners macOS standards gratuits pour repo public ;
- Godot garde la majorité du code cross-platform en GDScript ;
- Xcode n'existe que dans la CI ;
- SideStore enlève la dépendance quotidienne au PC pour le renouvellement 7 jours ;
- les APIs iOS manquantes côté Godot sont ajoutées par plugins natifs dédiés, sans réécrire toute l'app en Swift.

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

## Réseau futur avec SIGNAL

La connexion avec SIGNAL n'est pas le chantier actuel, mais l'architecture la rend possible : sockets TCP/UDP/WebSocket/HTTP depuis Godot, Bonjour/Network Framework via plugin si découverte locale nécessaire, permissions Local Network iOS à déclarer.
