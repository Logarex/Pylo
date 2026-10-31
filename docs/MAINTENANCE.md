# Maintenance

1. Regarder les échecs Actions après le 3 du mois. Un échec laisse les publications précédentes disponibles.
2. Si l’ANFR change ses colonnes, adapter le mapping dans ANFRImport, puis lancer les tests et une importation complète avant de publier.
3. Si le catalogue change, vérifier l’organisation ANFR et le jeu officiel avant de remplacer l’identifiant. Ne pas utiliser une API de tiers non vérifiée.
4. Sur un nouveau Mac, Xcode suffit. L’importeur utilise Foundation et SQLite système.
5. Garder le dépôt privé tant que souhaité. Les Releases héritent de cette visibilité. Les workflows planifiés peuvent être retardés par GitHub ; le lancement manuel reste disponible.
6. Avant TestFlight : vérifier la localisation autorisée/refusée, VoiceOver, grande taille de texte, modes clair/sombre, import invalide, mise à jour réelle et fonctionnement hors ligne sur un iPhone. Choisir une équipe Apple et finaliser les métadonnées App Store.

La base fournie couvre la France métropolitaine et l’outre-mer tels que présents dans la source. Le fond de carte est Apple Plans. Les relevés et favoris sont locaux et peuvent être inclus dans les sauvegardes de l’appareil. Supprimer l’app efface ses données locales selon le comportement d’iOS.
