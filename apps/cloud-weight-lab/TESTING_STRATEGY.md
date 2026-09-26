# Testing Strategy — Cloud Weight Lab

## CI

Le workflow doit au minimum :

- compiler la cible iPhone et la cible de tests pour simulateur ;
- compiler une app iPhone `Release` sans signature ;
- vérifier le bundle identifier et la déclaration caméra ;
- produire un IPA et un SHA-256 liés au SHA Git exact.

## Tests purs

`CloudMassEstimatorTests` vérifie :

- ordre `low < midpoint < high` ;
- croissance de la masse avec la taille angulaire ;
- classification déterministe des profils nuageux principaux.

## Test matériel obligatoire

La CI ne valide pas :

- l'orientation exacte du masque sur la preview ;
- la qualité réelle de la détection ciel/nuage ;
- la chauffe sur iPhone 13 mini ;
- la cadence perçue ;
- la qualité esthétique en extérieur ;
- la plausibilité de l'estimation face à de vrais nuages.

Ces points exigent l'IPA exact-SHA installée sur l'iPhone.

## Budget de performance V1

- preview caméra : cadence native ;
- analyse : maximum environ 8 images/s ;
- résolution analyse : 160×120 ;
- aucun réseau requis ;
- aucune accumulation non bornée d'images ou de masques.
