<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/logo-dark.svg">
    <img src="docs/images/logo-light.svg" alt="Logo de Pylo" width="100" height="100">
  </picture>
</p>

<h1 align="center">Pylo</h1>
<p align="center"><strong>Le réseau mobile, autour de toi.</strong><br>2G · 3G · 4G · 5G</p>

Je suis étudiant et j’ai créé Pylo pour comprendre les antennes autour de moi et ce qui se cache derrière les logos de réseau de mon iPhone. L’idée : tout retrouver dans une app simple, gratuite, sans pub et sans compte.

Avec Pylo, tu peux explorer les réseaux autour de toi et apprendre à lire les informations de ton iPhone, même si tu débutes.

**Gratuite et open source · développée par un étudiant · licence GPL-3.0.**

## Disponibilité

Pylo est en préparation pour une publication sur l’App Store. Le lien de téléchargement sera ajouté ici à sa sortie.

## Un aperçu de l’app

<p align="center">
  <img src="docs/pylo-iphone.png" alt="Pylo en thème sombre : antennes ANFR, couleurs par opérateur et flèches d’orientation autour de Notre-Dame de Paris" width="310">
</p>

*Pylo en thème sombre, autour de Notre-Dame de Paris.*

## Dans l’app

- **Explorer** : carte Apple Plans, recherche avec suggestions, localisation et filtres par opérateur ou génération. La carte se place autour de toi à l’ouverture ou retrouve ta dernière zone consultée si ta position est indisponible. Les flèches montrent les directions déclarées des antennes.
- **Les fiches** : technologies, bandes de fréquence, supports, hauteur, propriétaire déclaré, adresse, distance et orientation. Les dates d’implantation, de mise en service et de dernière modification sont affichées lorsqu’elles sont renseignées.
- **Favoris** : retrouver ses stations, les partager ou ouvrir un itinéraire dans Plans.
- **Field Test** : un guide pour ouvrir le menu avec `*3001#12345#*` et comprendre le signal, le bruit, les technologies et les identifiants radio. Un décodeur ECI LTE aide à lire les identifiants.
- **Statistiques** : stations, supports, générations, fréquences et évolutions entre publications. On peut comparer deux opérateurs sur la même base.

Pylo suit le thème clair ou sombre de ton iPhone, avec une interface native et Liquid Glass sur iOS 26. Disponible pour iPhone et iPad à partir d’iOS 18.

Les données sont consultables hors ligne. Le fond de carte, la recherche et les itinéraires peuvent nécessiter internet.

## Des antennes à jour

Les antennes sont actualisées à partir des publications officielles de l’ANFR. Tu n’as aucun fichier à chercher ni à importer.

Sur l’iPhone, Pylo vérifie les nouveautés à l’ouverture ou au retour dans l’app, au maximum une fois par jour. La base est téléchargée **en Wi-Fi, hors mode données réduites**. Si le téléchargement échoue, la copie précédente reste disponible et les favoris sont conservés.

Tu peux consulter la date des données, régler les mises à jour automatiques ou toucher **Vérifier maintenant** dans **Le projet**. Si tu n’as pas de Wi-Fi, tu peux continuer à utiliser la dernière base téléchargée.

## Ce que les données permettent de savoir

Une station correspond aux équipements d’un opérateur et peut être rattachée à plusieurs supports physiques. Elle peut utiliser plusieurs technologies et fréquences : les catégories des graphiques ne s’additionnent donc pas toutes.

Les flèches montrent une direction, pas une couverture. La station la plus proche n’est pas forcément celle utilisée par l’iPhone. iOS ne permet pas aux apps de lire publiquement la cellule connectée, les bandes actives ou les mesures RSRP, RSRQ et SINR : le guide Field Test aide à les retrouver et à les comprendre.

Les dates affichées sont celles déclarées à l’ANFR. Elles peuvent manquer ou être décalées par rapport à la situation sur le terrain.

## Une question ou un bug ?

Tu peux [ouvrir une issue sur GitHub](https://github.com/Logarex/Pylo/issues) ou m’écrire à [pylo@nephoos.com](mailto:pylo@nephoos.com). Tes retours m’aident à améliorer Pylo.

## Vie privée et sources

Pas de compte, pas de publicité, pas d’outil de suivi. Les favoris restent sur l’iPhone. À l’ouverture, Pylo cherche la position avec l’autorisation iOS. La dernière zone de carte consultée et son zoom sont conservés sur l’iPhone pour retrouver la carte si la position est indisponible. Le cap sert aux directions ; aucun historique de déplacement n’est conservé. Apple Plans traite les recherches et les itinéraires selon ses conditions. Les bases publiques sont téléchargées depuis GitHub.

- [ANFR : réseaux mobiles](https://www.data.gouv.fr/datasets/donnees-sur-les-reseaux-mobiles).
- [ANFR : installations radioélectriques de plus de 5 watts](https://www.data.gouv.fr/datasets/donnees-sur-les-installations-radioelectriques-de-plus-de-5-watts-1).
- [API géographique de l’État](https://geo.api.gouv.fr/) pour les noms des communes.
- [RNC Mobile](https://www.rncmobile.net/) pour découvrir leur travail communautaire. Pylo propose un lien ; il n’y a pas de partenariat confirmé ni d’import de leur base.

Le code est sous [licence GPL-3.0](LICENSE) (`GPL-3.0-only`). Les données ANFR gardent leur Licence Ouverte 2.0. Les autres attributions sont dans [NOTICE.md](NOTICE.md). Pylo est un projet indépendant, sans affiliation avec Apple, l’ANFR ou les opérateurs.

Pour contribuer au code ou entretenir le projet, les instructions sont dans [la documentation technique](docs/MAINTENANCE.md).
