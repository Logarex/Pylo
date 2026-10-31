<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/logo-dark.svg">
    <img src="docs/images/logo-light.svg" alt="Logo de Pylo" width="100" height="100">
  </picture>
</p>

<h1 align="center">Pylo</h1>
<p align="center"><strong>Le réseau mobile, autour de toi.</strong><br>2G · 3G · 4G · 5G</p>

Je suis étudiant et j’ai créé Pylo pour comprendre les antennes autour de moi et ce qui se cache derrière les logos de réseau de mon iPhone. L’idée : tout retrouver dans une app simple, gratuite, sans pub et sans compte.

Pylo est écrite en Swift, avec une interface native, des données ANFR consultables hors ligne et un guide pour apprendre à lire Field Test sans se perdre dans les acronymes.

**Gratuite et open source · développée par un étudiant · licence GPL-3.0.**

## Un aperçu de l’app

<p align="center">
  <img src="docs/pylo-iphone.png" alt="Pylo en thème sombre : antennes ANFR, couleurs par opérateur et flèches d’orientation autour de Notre-Dame de Paris" width="310">
</p>

*Capture de la version actuelle dans le simulateur iPhone. Les stations affichées proviennent de la base ANFR ; ce ne sont pas des données de démonstration.*

## Dans l’app

- **Explorer** : carte Apple Plans, recherche avec suggestions, localisation et filtres par opérateur ou génération. Les flèches indiquent l’orientation déclarée des antennes et sont activées par défaut.
- **Les fiches** : technologies, bandes de fréquence, supports, hauteur, propriétaire déclaré, adresse, distance et orientation. Les dates d’implantation, de mise en service et de dernière modification sont affichées lorsqu’elles sont renseignées.
- **Favoris** : retrouver ses stations, les partager ou ouvrir un itinéraire dans Plans.
- **Field Test** : un guide pour ouvrir le menu avec `*3001#12345#*` et comprendre le signal, le bruit, les technologies et les identifiants radio. Un décodeur ECI LTE aide à lire les identifiants.
- **Statistiques** : stations, supports, générations, fréquences et évolutions entre publications. On peut comparer deux opérateurs sur la même base.

Pylo suit le thème de l’iPhone et utilise Liquid Glass sur iOS 26, avec une présentation native sur les versions antérieures. Les commandes ont une couleur neutre ; les couleurs des opérateurs servent aux antennes.

Les données sont consultables hors ligne. Le fond de carte, la recherche et les itinéraires peuvent nécessiter internet.

## Des antennes à jour

Pas de fichier à chercher : le projet surveille chaque jour les deux sources officielles ANFR et publie une nouvelle base dès qu’elles changent.

Sur l’iPhone, Pylo vérifie les nouveautés à l’ouverture ou au retour dans l’app, au maximum une fois par jour. La base est téléchargée **en Wi-Fi, hors mode données réduites**. Si le téléchargement échoue, la copie précédente reste disponible et les favoris sont conservés.

Dans **Le projet**, on retrouve la date des données, le réglage des mises à jour automatiques et le bouton **Vérifier maintenant**. Une app fermée n’est pas forcément réveillée par iOS : la vérification attend alors sa prochaine ouverture. Les mises à jour de l’application elle-même se distribuent séparément.

Pour lancer une publication manuellement : [Actions → Mise à jour ANFR](https://github.com/Logarex/Pylo/actions/workflows/anfr.yml), puis **Run workflow**. L’option **force** reconstruit la base même si la source n’a pas changé. Code et données sont dans ce seul dépôt ; aucun serveur Pylo à entretenir.

## Bien lire les données

Une station correspond aux équipements d’un opérateur et peut être rattachée à plusieurs supports physiques. Elle peut utiliser plusieurs technologies et fréquences : les catégories des graphiques ne s’additionnent donc pas toutes.

Les flèches montrent une direction, pas une couverture. La station la plus proche n’est pas forcément celle utilisée par l’iPhone. iOS ne permet pas aux apps de lire publiquement la cellule connectée, les bandes actives ou les mesures RSRP, RSRQ et SINR : le guide Field Test aide à les retrouver et à les comprendre.

Les dates de station viennent des installations ANFR de plus de 5 watts. Les dates de systèmes viennent de l’observatoire mobile. Les deux fichiers peuvent être publiés à des moments différents ; une date absente reste indiquée comme non renseignée.

## Ouvrir le projet

Il faut **Xcode 26 ou plus récent** et **iOS 18 minimum**.

1. Clone le dépôt et ouvre `Pylo.xcodeproj`.
2. Sélectionne le schéma **Pylo**, puis un simulateur iPhone.
3. Pour ton iPhone, choisis ton équipe dans **Signing & Capabilities**.

Aucun paquet tiers à installer. Tout est écrit en Swift, avec SwiftUI, MapKit, Swift Charts et SQLite.

| Dossier | Contenu |
| --- | --- |
| `App/` | Interface et services iPhone |
| `Sources/PyloCore/` | Modèles, base de données et traitements partagés |
| `Sources/ANFRImport/` | Récupération et préparation des données ANFR |
| `Tests/` | Tests du cœur Swift |
| `.github/workflows/` | Vérifications et publication automatique des données |

```sh
swift test
mkdir -p output
swift run -c release anfr-import output/antennas.sqlite
```

Les instructions pour entretenir les données et préparer une version sont dans [la documentation de maintenance](docs/MAINTENANCE.md).

## Vie privée et sources

Pas de compte, pas de publicité, pas d’outil de suivi. Les favoris restent sur l’iPhone. À l’ouverture, Pylo cherche la position avec l’autorisation iOS. La dernière zone de carte consultée et son zoom sont conservés sur l’iPhone pour retrouver la carte si la position est indisponible. Le cap sert aux directions ; aucun historique de déplacement n’est conservé. Apple Plans traite les recherches et les itinéraires selon ses conditions. Les bases publiques sont téléchargées depuis GitHub.

- [ANFR : réseaux mobiles](https://www.data.gouv.fr/datasets/donnees-sur-les-reseaux-mobiles).
- [ANFR : installations radioélectriques de plus de 5 watts](https://www.data.gouv.fr/datasets/donnees-sur-les-installations-radioelectriques-de-plus-de-5-watts-1).
- [API géographique de l’État](https://geo.api.gouv.fr/) pour les noms des communes.
- [RNC Mobile](https://www.rncmobile.net/) pour découvrir leur travail communautaire. Pylo propose un lien ; il n’y a pas de partenariat confirmé ni d’import de leur base.

Le code est sous [licence GPL-3.0](LICENSE) (`GPL-3.0-only`). Les données ANFR gardent leur Licence Ouverte 2.0. Les autres attributions sont dans [NOTICE.md](NOTICE.md). Pylo est un projet indépendant, sans affiliation avec Apple, l’ANFR ou les opérateurs.
