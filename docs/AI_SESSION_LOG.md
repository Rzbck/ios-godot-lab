# ios-godot-lab — journal IA compact

Ce fichier conserve uniquement les décisions et résultats nécessaires à une reprise. Pas de transcription complète des chats.

---

### 2026-09-07 — première IPA iPhone unsigned BUILD IOS VALIDÉ

CANDIDAT : `bootstrap/ios-foundation-20260907 @ 8899a4bb4ad8addecf20a36d91b8d2055346cef5`.

PIPELINE : Windows/GitHub source -> `macos-26` -> Godot `4.7.2.stable.official.ed1daf0bf` -> export projet Xcode -> Xcode `26.6` / SDK iPhoneOS `26.5` -> Release `arm64-apple-ios16.0` -> signature désactivée -> IPA.

PREUVE : GitHub Actions run `34160430197`, job `101860944255`, toutes les étapes PASS ; Xcode affiche `BUILD SUCCEEDED`.

UNSIGNED GATE : `codesign --verify --deep --strict` doit échouer ; gate PASS, donc l'app produite est volontairement non signée avant SideStore.

IPA : `IOSGodotLab-unsigned-8899a4bb4ad8.ipa`.

SHA-256 IPA : `40e8b799779de2a9cf6b8b0973e6308875d4006223cbceaa43b4f001c187e14d`.

ARTIFACT : `ios-unsigned-8899a4bb4ad8addecf20a36d91b8d2055346cef5`, ID `10032441877`, upload PASS.

CLASSIFICATION : **BUILD IOS VALIDÉ exact-SHA**. Cela ne vaut PAS `VALIDÉ SUR IPHONE` tant que cette IPA exacte n'a pas été signée/installée/lancée sur le vrai téléphone.

INCIDENTS RÉSOLUS AVANT PASS : activation ETC2/ASTC requise par export Apple ; icône iOS fallback absente ; Xcode 26.6 exigeait `-scheme` avec `-derivedDataPath`.

DÉCISION CI : après validation du bootstrap, le workflow iOS passe en `workflow_dispatch` manuel pour éviter un Mac build à chaque petit commit.

MAIN : inchangé à `1a7c6e7b947cf2177eb56cbb43e924e7c39fd83f`.

PROCHAIN : SideStore -> signature Personal Team -> installation IPA exacte -> lancement/touch/capteurs/haptique sur iPhone.

---

### 2026-09-07 — première app Godot + premier smoke CI PASS

CHANTIER : `bootstrap/ios-foundation-20260907`.

APP : `project.godot` + `scenes/main.tscn` + `scripts/main.gd` ajoutés à `b530c3b718b19b0bb4468519e6ccba0a75eb9f8e`.

ÉCRAN : portrait `iPhone Lab` avec tactile, position dernier input, accéléromètre, gravité, gyroscope, magnétomètre, réseau local, vibration et roadmap IOSBridge.

BUILD ID : `config/build_info.json` fournit un fallback local ; la CI iOS stamp le SHA exact avant export.

CI : `.github/workflows/verify-godot.yml` + `tests/smoke_project.gd` ajoutés à `bf7bfa29482704408fad7b994d4772b573480e49`.

GODOT : `4.7.2-stable` verrouillé ; download officiel, identité moteur, import/parse et smoke exécutés sur GitHub Actions.

PREUVE : run `34159830420`, job `Parse and smoke` = **PASS** ; toutes les étapes sont success.

CLASSIFICATION : **BUILD CI VALIDÉ (DESKTOP/HEADLESS)** pour le SHA `bf7bfa29...`. Cela ne vaut ni BUILD IOS VALIDÉ ni VALIDÉ SUR IPHONE.

MAIN : inchangé à `1a7c6e7b947cf2177eb56cbb43e924e7c39fd83f`.

---

### 2026-09-07 — bootstrap architecture / gouvernance

REPO : `Rzbck/ios-godot-lab`, public.

MAIN INITIAL : routeur `HANDOFF.md` créé sur `main @ 1a7c6e7b947cf2177eb56cbb43e924e7c39fd83f`.

CHANTIER : `bootstrap/ios-foundation-20260907` créé depuis ce main.

RÉFÉRENCE MÉTHODE : audit lecture seule du HANDOFF/Git workflow/multi-worktree de SIGNAL ; aucune écriture dans SIGNAL.

DÉCISION : reprendre routeur HANDOFF + état courant + état consolidé + journal compact + discipline branches/worktrees, en version allégée adaptée à ce repo.

STACK RETENUE : Windows + Godot 4.7.2 + repo GitHub public + Actions macOS/Xcode + IPA unsigned + SideStore.

SIDELOAD : SideStore retenu pour refresh périodique en arrière-plan ; Apple gratuit reste 7 jours / 3 apps / 10 App IDs.

IPHONE APIs : pas d'« accès total » arbitraire ; Godot direct + plugins iOS natifs donnent accès aux frameworks publics Apple autorisés.
