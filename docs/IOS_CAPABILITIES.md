# Capacités iPhone depuis Godot — matrice d'accès

## Réponse courte

**On peut utiliser énormément de l'iPhone, mais pas littéralement « tout ».**

Une app Godot iOS peut utiliser :

1. les fonctions exposées directement par Godot ;
2. les frameworks publics Apple via un plugin iOS natif ;
3. uniquement ce qu'iOS autorise avec permissions/entitlements/sandbox.

Godot documente les plugins iOS comme moyen d'ajouter des fonctions spécifiques iOS et bibliothèques tierces. Ils sont exposables à GDScript via `Engine.get_singleton()`.

Source : https://docs.godotengine.org/en/4.7/tutorials/platform/ios/

## Matrice initiale

| Capacité | Faisable | Chemin prévu | Notes |
|---|---|---|---|
| Touch / multi-touch | Oui | Godot Input | natif moteur |
| Accéléromètre | Oui | `Input.get_accelerometer()` | iOS natif Godot |
| Gyroscope | Oui | `Input.get_gyroscope()` | iOS natif Godot |
| Gravité / orientation mouvement | Oui | Godot + Core Motion plugin si besoin avancé | Core Motion donne attitude/rotation/gravity |
| Magnétomètre | Oui | `Input.get_magnetometer()` | selon hardware |
| Caméra | Oui | CameraServer / module caméra | permission utilisateur requise |
| Micro / audio | Oui | Godot audio / AVFoundation si besoin avancé | permission micro |
| Réseau Internet | Oui | HTTP/WebSocket/TCP/UDP | règles iOS standard |
| Réseau local | Oui | Godot sockets ou Network/Bonjour plugin | permission Local Network ; Bonjour à déclarer |
| Bluetooth LE | Oui | plugin CoreBluetooth | pas une API GDScript standard complète |
| Bluetooth Classic | Partiel / encadré | CoreBluetooth / ExternalAccessory selon usage | dépend profils/accessoires/MFi |
| NFC | Oui, selon appareil/usage | plugin CoreNFC | entitlement + sessions/règles Apple |
| GPS / localisation | Oui | plugin CoreLocation | permission ; background fortement encadré |
| ARKit | Oui | plugin iOS / intégration AR | appareil compatible |
| LiDAR | Oui si appareil équipé | ARKit/native plugin | pas présent sur tous les iPhone |
| Baromètre | Oui si matériel disponible | Core Motion native plugin | disponibilité à tester |
| Haptics | Oui | Godot/native Core Haptics | capacités variables |
| Photos / fichiers utilisateur | Oui | APIs iOS / picker / plugin | sandbox + permissions/pickers |
| Notifications locales | Oui | plugin UserNotifications | permissions |
| Push notifications | Oui techniquement | APNs + entitlements + backend | peut dépasser le scope Personal Team gratuit selon capability |
| HealthKit | API publique mais capability contrôlée | plugin natif | entitlement, politique Apple, données sensibles |
| HomeKit | API/capability contrôlée | plugin natif | entitlement et règles Apple |
| Nearby Interaction / UWB | Selon modèle/capability | plugin natif | hardware + entitlement/API Apple |
| Boutons de volume | Pas comme « boutons libres » standard | plugin/approches iOS limitées | iOS garde le contrôle système ; ne pas compter dessus comme input universel |
| Bouton latéral / Home | Non comme input arbitraire d'app | — | réservé au système |
| Interrupteur silence / fonctions système privées | Non en accès arbitraire | — | pas d'API publique générale |
| Scan arbitraire de tous les réseaux Wi-Fi | Non | — | iOS restreint fortement l'accès Wi-Fi bas niveau |
| IMEI / secrets système / autres apps | Non | — | sandbox / confidentialité |

## Mouvement du téléphone

Oui. Godot expose directement plusieurs capteurs sur Android/iOS. Pour des données plus avancées, Core Motion fournit notamment :

- accélération ;
- gyroscope ;
- magnétomètre ;
- attitude/orientation 3D ;
- vecteur de gravité ;
- rotation ;
- selon appareil : pédomètre/baromètre et autres données de mouvement.

Sources :

- https://docs.godotengine.org/en/stable/classes/class_input.html
- https://developer.apple.com/documentation/coremotion/

## Caméra

Godot `CameraServer` est implémenté sur iOS ; il faut activer le module caméra à l'export. L'utilisateur doit autoriser caméra/microphone selon l'usage.

Sources :

- https://docs.godotengine.org/en/4.7/classes/class_cameraserver.html
- https://developer.apple.com/documentation/AVFoundation/requesting-authorization-to-capture-and-save-media

## Bluetooth

BLE est accessible via CoreBluetooth. Notre convention sera d'écrire un plugin `IOSBridge` minimal si une fonction Godot standard ne suffit pas.

Source : https://developer.apple.com/documentation/corebluetooth

## Wi-Fi / réseau local

Une app peut communiquer sur le LAN, découvrir des services Bonjour et parler à une machine comme SIGNAL. iOS demande l'autorisation Local Network pour de nombreuses opérations ; Bonjour nécessite aussi les déclarations `NSBonjourServices` appropriées.

Source : https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy

## NFC

Core NFC peut lire/écrire plusieurs types de tags sur appareil compatible. Cela demande les déclarations/capabilities Apple correspondantes.

Source : https://developer.apple.com/documentation/corenfc

## Règle d'architecture

Ne pas créer un plugin différent par écran. À terme :

```text
GDScript
   |
IOSBridge
   |-- Motion
   |-- Bluetooth
   |-- Network discovery
   |-- Camera extras
   |-- NFC
   |-- Haptics
   `-- autres frameworks publics Apple
```

Chaque capability est marquée `NON TESTÉE`, `BUILD OK`, puis `VALIDÉE SUR IPHONE` séparément.
