# ios-godot-lab — journal IA compact

Ce fichier conserve uniquement les décisions et résultats nécessaires à une reprise. Pas de transcription complète des chats.

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

BUILD CI VALIDÉ : non.

VALIDÉ SUR IPHONE : non.

PROCHAIN TEST : clone/worktree Windows -> projet Godot minimal -> workflow unsigned -> IPA -> SideStore -> lancement iPhone exact-SHA.
