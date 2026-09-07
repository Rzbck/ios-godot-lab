# ios-godot-lab

Laboratoire iPhone développé depuis **Windows + Godot**, compilé sur **GitHub Actions macOS**, puis installé sur un iPhone personnel sans posséder de Mac.

## Objectif

Chaîne cible :

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

## Décisions bootstrap

- moteur cible : **Godot 4.7.2 stable** ;
- repo public pour utiliser gratuitement les runners macOS standards GitHub Actions ;
- build iOS en CI, pas de Mac local requis ;
- IPA de développement non signé puis re-signé/installé via **SideStore** ;
- SideStore retenu devant AltStore/Sideloadly pour le rafraîchissement périodique en arrière-plan sans PC après l'installation initiale ;
- compte Apple gratuit : profils 7 jours, 3 apps max par appareil, 10 App IDs ;
- `main` = état publié ; tout changement réel passe par branche dédiée ;
- 1 chantier = 1 branche = 1 worktree local.

## Reprise

Commencer par [`HANDOFF.md`](HANDOFF.md).

## Sources de référence

- Godot iOS export : https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_ios.html
- Godot iOS plugins : https://docs.godotengine.org/en/4.7/tutorials/platform/ios/
- GitHub-hosted runners : https://docs.github.com/en/actions/reference/runners/github-hosted-runners
- Apple free developer account limits : https://developer.apple.com/help/account/basics/about-your-developer-account
- SideStore FAQ : https://docs.sidestore.io/docs/faq
