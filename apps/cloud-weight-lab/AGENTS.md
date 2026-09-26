# Collaboration IA — Cloud Weight Lab

Ces règles s'appliquent uniquement à `apps/cloud-weight-lab`.

Avant toute modification :

1. lire `HANDOFF.md` ;
2. vérifier la branche et son HEAD réel ;
3. lire `TESTING_STRATEGY.md` et `.github/workflows/cloud-weight-lab-build.yml` ;
4. conserver ce chantier indépendant de `apps/watch-sensor-lab`.

Règles :

- 1 chantier actif = 1 branche/worktree dédié ;
- aucun merge dans `main` sans accord utilisateur ;
- une CI verte valide le code compilé, pas le comportement réel sur iPhone ;
- les mesures affichées sont des estimations physiques et doivent conserver une fourchette d'incertitude ;
- ne jamais remplacer une estimation par une fausse précision ;
- le moteur de segmentation doit rester interchangeable : la V1 heuristique locale peut être remplacée par Core ML sans réécrire l'UI ni l'estimateur ;
- préserver une cadence faible d'analyse (environ 6–10 Hz) et laisser la prévisualisation caméra fluide à sa cadence native.
