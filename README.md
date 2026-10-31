# Pylo

Le réseau mobile, autour de toi.

Je suis étudiant et j’ai créé Pylo pour comprendre les antennes que je croise et ce qui se cache derrière les logos 3G, 4G et 5G. L’idée : une app gratuite, sans pub, sans compte et avec du code simple à reprendre.

Le code est sous licence MIT. **Le dépôt reste privé pendant le développement** : sa publication en open source viendra quand je le rendrai public. Les données appartiennent à l’ANFR et sont réutilisées sous Licence Ouverte 2.0.

[Aperçu sur iPhone](docs/pylo-iphone.png)

## Dans l’application

- Carte Apple Plans, antennes regroupées pour garder la carte lisible, recherche d’adresse, localisation à la demande.
- Stations ANFR réelles, filtres 3G / 4G / 5G et opérateurs.
- Bandes, état déclaré, coordonnées, adresse et date de mise à jour.
- Favoris locaux, partage et itinéraires.
- Guide Field Test, carnet manuel de relevés, export JSON et calcul ECI 4G.
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

`App/` contient les vues SwiftUI et l’état de l’application. `Sources/PyloCore/` contient les modèles, le lecteur CSV et SQLite, partagés avec l’importeur. `Sources/ANFRImport/` contient l’outil de maintenance en Swift. `Tests/` vérifie le parsing, les regroupements, les filtres et le calcul ECI. Les workflows construisent les données et vérifient le projet.

L’app compile directement les fichiers du cœur ; Swift Package Manager construit ces mêmes fichiers pour les tests et l’outil Mac. Pas de dépendance tierce, pas de serveur, pas de compte utilisateur. SQLite est fourni par le système. L’outil Mac utilise l’utilitaire système unzip pour décompresser les archives officielles.

## Limites honnêtes

iOS n’expose pas d’API publique pour lire les mesures radio brutes, la cellule courante ou le menu Field Test. Pylo propose un guide et une saisie manuelle ; aucune valeur n’est inventée. L’ECI/eNodeB n’est pas un identifiant ANFR. Pas de rapprochement automatique supposé entre les deux.

La carte affiche au maximum 600 stations par zone : zoome pour affiner. Il ne s’agit pas d’une carte de couverture ni d’un test de débit. Les états ANFR restent ceux de la source ; « autorisé » ne veut pas dire « en service ». Les fonds Plans, recherches et itinéraires nécessitent parfois internet. Les fonctions doivent encore être essayées sur un vrai iPhone avant une distribution TestFlight/App Store.

## Sources

- [Catalogue officiel ANFR](https://www.data.gouv.fr/datasets/donnees-sur-les-reseaux-mobiles)
- [API du catalogue utilisée par l’importeur](https://www.data.gouv.fr/api/1/datasets/6ab291cf426d615c84196260/)
- [Observatoire ANFR](https://www.anfr.fr/gestion-des-frequences-sites/lobservatoire)
- [Limitation des API de mesure radio, Apple](https://developer.apple.com/forums/thread/721067)
- [Liquid Glass, Apple](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)

Pylo n’est affiliée ni à Apple, ni à l’ANFR, ni aux opérateurs. Les logos de référence ont été fournis par l’auteur du projet.
