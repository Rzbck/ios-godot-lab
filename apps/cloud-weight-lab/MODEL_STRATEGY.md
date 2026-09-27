# Model strategy

## Segmentation actuelle

Le pipeline iPhone utilise deux modèles Core ML épinglés :

- SegFormer B0 ADE20K pour confirmer les pixels de ciel et rejeter une partie des arbres, bâtiments, personnes et autres scènes hors ciel ;
- UCloudNet k=2 pour segmenter les nuages dans les pixels confirmés comme ciel.

La sortie est suivie temporellement avec des IDs persistants. Le type de nuage reste une classification heuristique à partir de la forme/couverture/couleur et ne doit pas être présenté comme une identification météorologique certaine.

## V11 — estimation physique angle-aware

La masse affichée est la masse estimée d'eau/glace condensée, pas la masse totale de l'air contenu dans le nuage.

V11 remplace l'ancienne géométrie qui supposait une élévation fixe de 55° par :

1. champ de vision horizontal réel du format caméra AVFoundation ;
2. élévation de l'axe optique estimée par CoreMotion/gravity ;
3. position du nuage dans l'image pour obtenir son élévation centrale ;
4. largeur/hauteur angulaires obtenues par projection pinhole à partir des bords de la bounding box ;
5. distance de ligne de visée déduite d'une plage d'altitude propre au type supposé ;
6. aire projetée corrigée par la fraction réellement remplie par le masque ;
7. profondeur probabiliste liée à la racine carrée de l'aire projetée ;
8. volume multiplié par une plage de contenu en eau/glace condensée.

Le résultat expose low/mid/high ainsi que distance, angle, largeur, hauteur, profondeur, aire, volume et confiance pour la télémétrie.

## Limite fondamentale

Une seule image RGB d'un iPhone ne mesure pas directement :

- la distance au nuage ;
- la hauteur réelle de sa base ;
- son épaisseur 3D ;
- son contenu réel en eau/glace.

V11 est donc une estimation physique mieux contrainte, pas une pesée exacte. Il ne faut pas transformer la valeur médiane en fausse précision.

## Voies pour augmenter réellement la précision

Ordre de priorité après validation V11 :

1. vérifier physiquement le signe et la stabilité de l'élévation CoreMotion en portrait/paysage ;
2. utiliser le FOV corrigé de distorsion si le format caméra actif le permet ;
3. ajouter un contexte météo facultatif pour réduire fortement l'incertitude de hauteur de base (température/point de rosée pour cumulus convectif, ou donnée météo/ceilomètre lorsqu'elle existe) ;
4. conserver une plage de LWC/IWC et de profondeur, plutôt qu'un nombre arbitrairement exact ;
5. comparer les estimations sur plusieurs frames d'un même track avant de resserrer une plage ;
6. ne resserrer la confiance qu'après validation sur scènes réelles connues.

Toute donnée réseau/météo future doit rester optionnelle et séparée du fonctionnement caméra local ; aucun secret ne doit être ajouté au dépôt public.
