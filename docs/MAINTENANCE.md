# Maintenance

1. Regarder les échecs Actions après le 3 du mois. Un échec laisse les publications précédentes disponibles.
2. Si l’ANFR change ses colonnes, adapter le mapping dans ANFRImport, puis lancer les tests et une importation complète avant de publier.
3. Si le catalogue change, vérifier l’organisation ANFR et le jeu officiel avant de remplacer l’identifiant. Ne pas utiliser une API de tiers non vérifiée.
4. Sur un nouveau Mac, Xcode suffit. L’importeur utilise Foundation et SQLite système.
5. Garder le dépôt privé tant que souhaité. Les Releases héritent de cette visibilité. Les workflows planifiés peuvent être retardés par GitHub ; le lancement manuel reste disponible.
6. Avant TestFlight : vérifier la localisation autorisée/refusée, VoiceOver, grande taille de texte, modes clair/sombre, import invalide, mise à jour réelle et fonctionnement hors ligne sur un iPhone. Choisir une équipe Apple et finaliser les métadonnées App Store.

La base fournie couvre la France métropolitaine et l’outre-mer tels que présents dans la source. Le fond de carte est Apple Plans. Les relevés et favoris sont locaux et peuvent être inclus dans les sauvegardes de l’appareil. Supprimer l’app efface ses données locales selon le comportement d’iOS.

## Schéma 2 et base embarquée

La 2G est incluse. Conserver les supports distincts et fusionner les azimuts quand la même station/bande apparaît sur plusieurs lignes. Les tests couvrent ce cas réel ANFR.

Après reconstruction locale, compresser le fichier pour le bundle : `gzip -c App/Resources/antennas.sqlite > App/Resources/antennas.sqlite.gz`. Le SQLite brut reste ignoré par Git. Lors d’un remplacement du fichier embarqué dans une nouvelle version de l’app, changer aussi la clé de cache `bundledDatabase` dans AppStore pour éviter de garder l’ancienne copie décompressée.

Le workflow mensuel télécharge la dernière publication pour comparer les identifiants, seulement si son schéma est compatible. Une copie de schéma 1 ne permet pas de calculer les apparitions 2G. Ne pas transformer `emr_dt` en date d’ajout au catalogue. Les supports sont comptés distinctement sur toute la table supports, pas seulement via le repère principal de chaque station.

Avant de changer les couleurs, garder SFR en majuscules dans operatorDisplayName et vérifier les marqueurs simples, les groupes multicolores et les légendes des graphiques.

La carte utilise MKMapView et ses regroupements natifs pour conserver les gestes de zoom fluides. Les requêtes sont décalées de 300 ms après la fin du mouvement ; les flèches sont limitées à 12 stations individuelles et 48 directions dans une seule couche de dessin. Leur taille est constante à l’écran et ne représente pas une portée radio.

### Orientations et fluidité

Les orientations de la carte sont désormais dessinées dans une seule couche légère, avec des flèches de 30 points et un trait de 1,6 point, indépendants du niveau de zoom. Elles s’effacent pendant le mouvement et reviennent après 360 ms de repos. Seuls les marqueurs individuels visibles sont concernés, avec au plus 12 stations et 48 flèches au total (six directions maximum par station sur la carte). Les directions complètes restent consultables dans la fiche.

Les mises à jour de marqueurs sont différées pendant un geste. Les images de regroupement sont réutilisées dans un cache borné à 200 entrées. Le plan d’orientations est testé pour sa limite, son ordre de proximité et l’élimination des doublons/angles invalides.
