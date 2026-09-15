# HANDOFF — Fusion auto-pause terrain — 2026-09-15

## Observation matérielle qui motive ce candidat

Lors d'une séance immobile, la Watch alternait `pause → reprise → pause`.
La position, la vitesse GPS, la distance et les pas restaient fixes ; seule une
cadence de 113 spm persistait. Cette valeur pouvait être antérieure à la pause.

## Candidat

- dépôt : `Rzbck/ios-godot-lab`
- application : `apps/watch-sensor-lab`
- branche : `fix/watch-auto-pause-fusion-20260915`
- worktree : `E:\_Project\IOS APP\ios-godot-lab\worktrees\watch-auto-pause-fusion`
- base : `9e6ab5d290affa64c0a94eddb17c7cdda2a32f0c`

Ce document ne désigne pas encore d'IPA ni de SHA validé matériellement.

## Correctif

- auto-pause peut se déclencher au démarrage d'une activité réellement immobile,
  après son court délai interne de stabilisation ;
- une pause auto efface explicitement cadence et mouvement antérieurs ;
- Core Motion et CMPedometer portent l'horodatage natif de la mesure, pas
  l'heure de réception du callback ;
- la reprise GPS exige deux fixes récents, précis, mobiles et temporellement
  cohérents, avec une précision de vitesse acceptable ;
- sans cette preuve GPS, la reprise exige l'accord de deux sources fraîches :
  mouvement non stationnaire et cadence ; une cadence seule, un callback motion
  isolé, un GPS ancien ou imprécis ne suffisent jamais ;
- la chaîne générée est contrôlée par un invariant fail-closed afin qu'un futur
  changement ne reconnecte pas les valeurs brutes à la reprise.

Le démarrage Auto neutre, la fusion Auto-sport, la correction finale du sport
et l'autorité Watch/iPhone existants sont conservés.

## Vérifications attendues avant test physique

1. chaîne générée exécutée deux fois ;
2. préflight et invariants produits ;
3. XCTest iPhone et watchOS ;
4. builds unsigned iPhone et companion Watch du même SHA.

Le test physique restant doit vérifier : démarrer immobile et rester en pause,
puis reprendre une marche/course/vélo réelle sans oscillation. Aucun merge dans
`main`, publication ou installation matérielle n'est autorisé par ce handoff.
