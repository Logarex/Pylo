# Maintenance de Pylo

## Publication des données

Le workflow `.github/workflows/anfr.yml` vérifie le catalogue officiel chaque jour à 07:23 UTC. `workflow_dispatch` permet un lancement manuel, avec `force` si une reconstruction est souhaitée malgré une source identique. L’ANFR déclare une fréquence hebdomadaire ; ne pas supposer une publication le premier ou le troisième jour du mois.

Le workflow choisit une ressource précise et garde sa sélection pendant l’import, même si le catalogue change entre-temps. Il télécharge la base précédente, compare les identifiants, prépare et valide la nouvelle base, puis crée une Release avec une URL immuable. Seulement après l’envoi des fichiers, il remplace `data/manifest.json` via l’API GitHub. Un échec antérieur laisse le manifeste et les applications sur la publication précédente. Aucun secret supplémentaire n’est nécessaire : le GITHUB_TOKEN du workflow est limité à ce dépôt.

Dans GitHub Actions, activer les notifications d’échec pour surveiller les changements de format ou les interruptions de source. Après un changement de colonnes, adapter le mapping et lancer les tests ainsi qu’un import complet avant publication.

## Mise à jour dans l’app

Le contrôle automatique a lieu à l’ouverture/retour dans l’app ou au rétablissement du Wi-Fi, au maximum une fois par 24 h après une vérification réussie. Il n’y a pas de promesse de réveil en arrière-plan d’une application fermée. Les téléchargements de bases sont limités au Wi-Fi hors mode données réduites. Le bouton Vérifier maintenant permet une lecture du manifeste à la demande.

DataUpdates contrôle le schéma, l’hôte et le chemin du dépôt, la taille compressée, le SHA-256, la taille décompressée, l’intégrité SQLite et la date source. La base est préparée à côté de la destination puis remplacée atomiquement. Une erreur garde la copie précédente. Les favoris sont dans un stockage distinct.

Test complet de la publication publique sur Mac :

```sh
swift run anfr-import --verify-update /tmp/pylo-update-check.sqlite
```

## Source et copie embarquée

Les données incluent la 2G. Conserver les supports distincts et fusionner les azimuts lorsque la même station/bande apparaît plusieurs fois. Les dates `emr_dt` ne sont pas des dates d’ajout au catalogue. Une base de schéma 1, qui excluait la 2G, n’est pas comparable à une base de schéma 2 pour compter les apparitions.

Après une reconstruction locale de la copie embarquée :

```sh
gzip -c App/Resources/antennas.sqlite > App/Resources/antennas.sqlite.gz
```

Le SQLite brut est ignoré par Git. Changer la clé de cache `bundledDatabase` dans AppStore quand une nouvelle copie embarquée remplace l’ancienne dans une version de l’app.

## Carte et interface

MapKit gère les regroupements et réutilise les repères. Les orientations sont dessinées dans un UIView transparent, à partir de la tête des marqueurs, avec une projection MapKit qui respecte la rotation et l’inclinaison. Au maximum 12 stations et 48 flèches, masquées pendant les gestes puis restaurées après 360 ms de repos. Les azimuts des supports principaux sont lus dans une seule requête pour toutes les stations chargées.

AccentColor gère l’interface neutre. FreeOperator est noir en clair, blanc en sombre ; son symbole utilise la couleur opposée. Les groupes doivent être redessinés avec les traits du thème courant. Les autres couleurs opérateur restent dans Palette.operatorColor. Garder SFR en majuscules dans operatorDisplayName.

Les logos sont à fond perdu, sans cadre ni coins arrondis pré-dessinés : iOS applique son propre masque. Dans la page Le projet, un masque SwiftUI arrondit le logo ; le README utilise les variantes autonomes de `docs/images/`.

## Favoris et réseau

Les favoris sont recherchés par identifiant indexé, en lots de 500, hors du fil principal. Une liste vide n’ouvre pas la base. Les tâches annulées ne remplacent pas les résultats courants.

Le suivi distingue le chemin internet NWPath de la technologie CoreTelephony. Ne pas transformer une information radio absente en absence de réseau. Le bouton d’actualisation relit les deux sources, et les notifications radio ainsi que le retour au premier plan actualisent l’état.

## Recherche et Field Test

Afficher `*3001#12345#*` avec Text(verbatim:) pour conserver les astérisques. Le code copié doit être identique.

MKLocalSearchCompleter intervient après deux caractères et 250 ms de pause. Les requêtes obsolètes sont annulées ; une sélection passe à MKLocalSearch.Request(completion:). Les suggestions sont limitées à cinq dans une liste défilante.

Avant une distribution, vérifier sur iPhone la localisation autorisée/refusée, la boussole, VoiceOver, les grandes tailles de texte, les deux thèmes, l’usage hors ligne, les gestes de carte, un téléchargement réel et un échec de téléchargement. Sélectionner une équipe Apple pour la signature et finaliser les métadonnées de distribution.

## Champs des sources

L’import garde une table supplémentaire anfr_details, compatible avec le schéma Pylo 2, et une colonne commune facultative en fin de table stations. Les anciennes copies sans détails restent lisibles. Ne jamais réécrire l’adresse brute : la présentation passe par ANFRAddress. Les références de noms sont rafraîchies par `anfr-import --references` et une copie de repli est incluse dans les ressources de l’importeur.

Chaque préparation produit quality.json. Les azimuts 360° valent 0° pour l’affichage, mais l’export garde la chaîne originale. Les enregistrements source conservent aussi les dates et états propres à chaque support/système, au-delà de la synthèse station–bande.

L’import récupère également la dernière archive `-data.zip` des installations ANFR de plus de 5 watts et en extrait seulement `SUP_STATION.txt`. La table `station_dates`, facultative pour les anciennes bases, contient les trois dates administratives et la publication d’origine. `dates-source.json` accompagne chaque nouvelle release ; le manifeste surveille les versions des deux sources. L’absence d’une date ou d’une correspondance n’est pas remplacée par la date du fichier.
