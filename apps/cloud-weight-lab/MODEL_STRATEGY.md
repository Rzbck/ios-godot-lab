# Model strategy

## V1 livrée

Le moteur `CloudAnalyzer` utilise une segmentation déterministe légère basée sur luminance, saturation et neutralité des pixels après réduction à 160×120. Ce choix rend la première version immédiatement compilable et testable, sans dépendance externe ni gros modèle.

## V2 Core ML

Le point d'extension prévu est un moteur qui produit le même `CloudFrameAnalysis` depuis un masque sémantique Core ML.

Critères avant ajout d'un modèle externe :

- licence compatible avec un usage personnel ;
- provenance et poids identifiés ;
- taille raisonnable pour l'iPhone 13 mini ;
- conversion Core ML reproductible ;
- benchmark sur appareil réel : latence, chauffe, mémoire et énergie ;
- fallback automatique vers le moteur léger si le modèle n'est pas chargé.

Les jeux de données ou modèles académiques peuvent être utilisés pour ce projet personnel, mais la licence et la source doivent rester documentées avec le modèle exact retenu.
