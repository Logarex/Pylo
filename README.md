# Pylo

Le réseau mobile, autour de toi.

Je suis étudiant et j’ai créé Pylo pour comprendre les antennes que je croise et ce qui se cache derrière les logos 2G, 3G, 4G et 5G. L’idée : une app gratuite, sans pub, sans compte et avec du code simple à reprendre.

Le code est sous licence MIT. **Le dépôt reste privé pendant le développement** : sa publication en open source viendra quand je le rendrai public. Les données appartiennent à l’ANFR et sont réutilisées sous Licence Ouverte 2.0.

[Aperçu sur iPhone](docs/pylo-iphone.png)

## Dans l’application

- Carte Apple Plans, antennes regroupées pour garder la carte lisible, recherche d’adresse, localisation à la demande.
- Stations ANFR réelles, filtres 2G / 3G / 4G / 5G et opérateurs.
- Fiches par bande : état propre, date ANFR, directions, hauteur et numéro du support.
- Couleurs par opérateur, zoom +/−, axes d’orientation ANFR et boussole.
- Distance et cap à la demande, avec explications honnêtes sur la réception.
- Favoris locaux, partage et itinéraires.
- Guide Field Test pas à pas, dictionnaire consultable et calcul ECI LTE.
- Informations publiques iOS : type de connexion, radio déclarée par ligne et mode données réduites.
- Statistiques nationales : stations, supports, systèmes, opérateurs, générations, fréquences et dates déclarées.
- Petit guide pour comprendre les générations, fréquences et indicateurs radio.
- Base embarquée consultable hors ligne, import de mises à jour depuis Fichiers.
- SwiftUI natif, clair/sombre, Dynamic Type, Liquid Glass sur iOS 26+, matériaux système sur iOS 18.

## Ouvrir le projet

Ouvre `Pylo.xcodeproj` avec Xcode 26 ou plus récent. Sélectionne le schéma **Pylo**, puis un simulateur iPhone. Aucun paquet tiers à installer. iOS 18 minimum. Pour ton iPhone, choisis ton équipe dans Signing & Capabilities et adapte l’identifiant d’application si nécessaire.

Le fichier ANFR du 29 octobre 2026 est embarqué : ce ne sont pas des antennes de démonstration. Les métadonnées de cette copie se trouvent dans `docs/anfr-source.json`.

## Une mise à jour par mois, sans serveur

Le workflow **Mise à jour ANFR** tourne le 3 de chaque mois, à 07:23 UTC, et peut être lancé à la main dans Actions. Il interroge le catalogue officiel, découvre la dernière archive, la télécharge, valide les colonnes et les coordonnées, regroupe les systèmes par station et construit une base SQLite indexée.

La base est publiée dans une **Release privée** avec sa source et son empreinte SHA-256. Depuis l’iPhone connecté à ton compte GitHub, télécharge `antennas.sqlite`, puis importe ce fichier dans Pylo → Données. L’ancienne base n’est remplacée qu’après validation. Une erreur dans la source fait échouer le workflow ; consulte les notifications d’échec GitHub Actions.

Cette étape d’import est volontaire : une app ne peut pas télécharger anonymement les Releases d’un dépôt privé. Aucun jeton personnel n’est embarqué. Quand le dépôt sera public, on pourra ajouter un téléchargement automatique depuis un manifeste public versionné, avec contrôle d’intégrité. La version actuelle ne prétend pas déjà faire ce téléchargement automatique.

Pour reconstruire toi-même sur Mac :

```sh
mkdir -p output
swift run -c release anfr-import output/antennas.sqlite
swift test
```

Pour importer une archive déjà extraite :

```sh
swift run -c release anfr-import output/antennas.sqlite /chemin/observatoire.csv
```

## Architecture

`App/` contient les vues SwiftUI et l’état de l’application. `Sources/PyloCore/` contient les modèles, le lecteur CSV et SQLite, partagés avec l’importeur. `App/StatisticsView.swift` utilise Swift Charts sur l’intégralité de la base, hors du fil principal. `Sources/ANFRImport/` contient l’outil de maintenance en Swift. `Tests/` vérifie le parsing, les regroupements, les filtres et le calcul ECI. Les workflows construisent les données et vérifient le projet.

L’app compile directement les fichiers du cœur ; Swift Package Manager construit ces mêmes fichiers pour les tests et l’outil Mac. Pas de dépendance tierce, pas de serveur, pas de compte utilisateur. SQLite est fourni par le système. L’outil Mac utilise l’utilitaire système unzip pour décompresser les archives officielles.

## Limites honnêtes

iOS n’expose pas d’API publique pour lire les mesures radio brutes, la cellule courante ou le menu Field Test. Pylo propose un guide détaillé et un décodeur ECI ; aucune valeur n’est inventée. L’ECI/eNodeB n’est pas un identifiant ANFR. Pas de rapprochement automatique supposé entre les deux.

La carte affiche au maximum 600 stations par zone : zoome pour affiner. Il ne s’agit pas d’une carte de couverture ni d’un test de débit. Les états ANFR restent ceux de la source ; « autorisé » ne veut pas dire « en service ». Les fonds Plans, recherches et itinéraires nécessitent parfois internet. Les fonctions doivent encore être essayées sur un vrai iPhone avant une distribution TestFlight/App Store.

## Sources

- [Catalogue officiel ANFR](https://www.data.gouv.fr/datasets/donnees-sur-les-reseaux-mobiles)
- [API du catalogue utilisée par l’importeur](https://www.data.gouv.fr/api/1/datasets/6ab291cf426d615c84196260/)
- [Observatoire ANFR](https://www.anfr.fr/gestion-des-frequences-sites/lobservatoire)
- [Limitation des API de mesure radio, Apple](https://developer.apple.com/forums/thread/721067)
- [Liquid Glass, Apple](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)

Pylo n’est affiliée ni à Apple, ni à l’ANFR, ni aux opérateurs. Les logos de référence ont été fournis par l’auteur du projet.

## Version 0.2 — lire les données correctement

Le fichier embarqué `App/Resources/antennas.sqlite.gz` est compressé (environ 36 Mo). Au premier lancement, le cœur Swift le décompresse dans le cache de l’app (environ 146 Mo). Une mise à jour choisie par l’utilisateur reste dans Documents. Le fichier SQLite brut local est ignoré par Git ; il sert à la maintenance.

Le schéma 2 conserve chaque couple station–système : technologie, bande, état, date, azimuts. Il ajoute les identifiants de supports et leur hauteur. Les directions affichées sont des axes, sans largeur de faisceau inventée. Les orientations de la carte concernent au plus 12 stations individuelles visibles ; la fiche contient toutes les directions renseignées pour la station.

Le pipeline mensuel récupère la publication précédente et compare les identifiants. Une station peut avoir plusieurs supports : ils sont conservés séparément et comptés distinctement. Les directions de la carte concernent le support du repère ; les fiches regroupent les azimuts de la station et listent ses supports.

La première publication de schéma 2 initialise l’historique : une base de schéma 1 n’est pas comparable, car elle excluait la 2G. Les apparitions/retraits sont toujours associés aux deux dates des copies ; ce ne sont pas des antennes forcément construites/démontées pendant le mois. Les graphiques de dates utilisent `emr_dt` et sont explicitement séparés de cette comparaison.

Le carnet manuel a été remplacé par le guide demandé. Les anciens relevés restent conservés dans le stockage de l’app mais ne sont plus présentés dans l’interface.

RNC Mobile : lien et proposition de contact dans `docs/RNC-MOBILE.md`. Aucune récupération de leur base, API inventée ou annonce de partenariat. Logos et méthode de préparation : `docs/ASSETS.md`.

Sources complémentaires : [CoreTelephony](https://developer.apple.com/documentation/coretelephony/cttelephonynetworkinfo/servicecurrentradioaccesstechnology), [repères de mesure Teltonika](https://wiki.teltonika-networks.com/view/Mobile_Signal_Strength_Recommendations), [définition des mesures LTE ETSI](https://www.etsi.org/deliver/etsi_ts/136200_136299/136214/08.03.00_60/ts_136214v080300p.pdf).

La carte utilise MKMapView et ses regroupements natifs pour conserver les gestes de zoom fluides. Les requêtes sont décalées de 300 ms après la fin du mouvement ; les flèches sont limitées à 12 stations individuelles et 48 directions dans une seule couche de dessin. Leur taille est constante à l’écran et ne représente pas une portée radio.

### Orientations et fluidité

Les orientations de la carte sont désormais dessinées dans une seule couche légère, avec des flèches de 30 points et un trait de 1,6 point, indépendants du niveau de zoom. Elles s’effacent pendant le mouvement et reviennent après 360 ms de repos. Seuls les marqueurs individuels visibles sont concernés, avec au plus 12 stations et 48 flèches au total (six directions maximum par station sur la carte). Les directions complètes restent consultables dans la fiche.

Les mises à jour de marqueurs sont différées pendant un geste. Les images de regroupement sont réutilisées dans un cache borné à 200 entrées. Le plan d’orientations est testé pour sa limite, son ordre de proximité et l’élimination des doublons/angles invalides.
