# ios-godot-lab

Laboratoire iPhone développé depuis **Windows + Godot**, compilé gratuitement sur **GitHub Actions macOS**, puis destiné au sideload personnel sur iPhone via SideStore.

## État actuel

- moteur : **Godot 4.7.2 stable** ;
- plateforme de développement : **Windows** ;
- CI rapide : parse/import/smoke Godot ;
- CI iOS : export Godot -> Xcode -> Release `iphoneos` ARM64 -> IPA unsigned ;
- premier **BUILD IOS VALIDÉ** : `8899a4bb4ad8addecf20a36d91b8d2055346cef5` ;
- première IPA : `IOSGodotLab-unsigned-8899a4bb4ad8.ipa` ;
- installation/lancement sur iPhone : **pas encore validés**.

## Application actuelle

Le premier écran `iPhone Lab` est un banc de test réel pour :

- tactile ;
- accéléromètre ;
- gravité ;
- gyroscope ;
- magnétomètre ;
- réseau local ;
- vibration/haptique ;
- identité exacte du build.

Les capacités iOS absentes de l'API Godot standard seront regroupées dans un futur bridge natif `IOSBridge` plutôt que dispersées dans l'application.

## Chaîne retenue

```text
Windows + Godot
      -> GitHub public
      -> GitHub Actions macOS + Xcode
      -> IPA unsigned exact-SHA
      -> SideStore
      -> signature Apple ID gratuite
      -> iPhone
```

La priorité est une chaîne **0 €**, reproductible, traçable par SHA et facile à reprendre entre conversations/IA.

## Build iOS

Le workflow `.github/workflows/build-ios-unsigned.yml` est volontairement manuel (`workflow_dispatch`). Chaque build :

1. checkout le SHA exact ;
2. utilise Godot 4.7.2 ;
3. exporte un projet Xcode ;
4. compile pour `iphoneos` sans signature ;
5. vérifie que l'app est bien unsigned ;
6. fabrique l'IPA ;
7. produit un manifeste et un SHA-256 ;
8. upload l'ensemble comme artifact GitHub.

## Discipline projet

- `main` = état publié ; tout changement réel passe par branche dédiée ;
- **1 chantier = 1 branche = 1 worktree local** ;
- un build/test ne valide que son SHA exact ;
- le handoff ne s'auto-déclare jamais HEAD : le HEAD réel est toujours re-fetché ;
- SideStore retenu pour le rafraîchissement périodique en arrière-plan après installation initiale ;
- compte Apple gratuit : profils 7 jours, 3 apps max par appareil, 10 App IDs.

## Reprise

Commencer par [`HANDOFF.md`](HANDOFF.md), puis suivre l'ordre canonique vers les règles, l'état courant et le journal compact.

## Sources de référence

- Godot iOS export : https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_ios.html
- Godot iOS plugins : https://docs.godotengine.org/en/4.7/tutorials/platform/ios/
- GitHub-hosted runners : https://docs.github.com/en/actions/reference/runners/github-hosted-runners
- Apple free developer account limits : https://developer.apple.com/help/account/basics/about-your-developer-account
- SideStore FAQ : https://docs.sidestore.io/docs/faq
