# Audit des données ANFR et iPhone

Audit du 31 octobre 2026 sur la copie ANFR du 29 octobre 2026 : **821 309 lignes et 23 colonnes**. Périmètre : l’observatoire des réseaux mobiles utilisé par Pylo, pas l’ensemble des jeux de données publiés par l’ANFR.

## Ce qui a été trouvé et corrigé

- Les adresses contiennent des abréviations de voie présentes dans la source : `r`, `bd`, `av`, `rte`, `chem`, etc. Pylo les développe uniquement au début d’une composante d’adresse, éventuellement après un numéro. Il ne remplace pas les lettres dans les noms propres, ne réinvente pas les accents et ne transforme pas arbitrairement des compléments tels que « Résidence R ».
- **72 lignes** contiennent un azimut `360`. Il est désormais normalisé à `0°` pour l’affichage ; la valeur originale est conservée.
- **2 495 lignes** portent exactement `ND` pour leurs azimuts et 235 autres contiennent des listes de `ND` répétés, soit **2 730 lignes sans direction exploitable**. Cela signifie que la direction n’est pas renseignée, pas qu’elle vaut zéro.
- **69 253 lignes** n’ont pas de date système. Pylo laisse cette date absente.
- Les hauteurs utilisent souvent la virgule décimale : **244 131 lignes** dans cette copie. Ce format est conservé ; une hauteur de support n’est pas assimilée à l’altitude ou à la hauteur exacte d’un panneau.
- Les colonnes `code_insee` et `com_cd_insee` sont identiques dans cette copie. Elles restent conservées séparément, sans supposer que toutes les publications futures seront identiques.
- Les codes de nature et de propriétaire n’étaient pas exploités. Les nomenclatures officielles sont maintenant utilisées : 37 types de supports et 83 catégories/propriétaires dans le référentiel consulté. Le code de nature 56 (32 lignes) et le propriétaire 87 (115 lignes) n’y figurent pas : ils restent explicitement non référencés, sans libellé deviné.
- Les noms des communes proviennent de l’API géographique de l’État, avec une requête distincte pour les 45 arrondissements municipaux de Paris, Lyon et Marseille. Les territoires ou codes absents du référentiel ne reçoivent pas de nom inventé : le code source reste visible.

Les nombres ci-dessus comptent des **lignes de source**, qui peuvent se rapporter à la même station ou au même support. Ce ne sont pas des nombres d’antennes distinctes.

## Les 23 colonnes

| Colonne source | Traitement dans Pylo |
| --- | --- |
| `id` | Identifiant de ligne conservé dans les enregistrements d’origine ; contrôlé vide/doublon à l’import. Il n’est pas utilisé comme identifiant radio. |
| `adm_lb_nom` | Opérateur affiché et filtre/couleur ; valeur d’origine conservée. |
| `sup_id` | Support physique, regroupement et fiche, distinct de la station opérateur. |
| `emr_lb_systeme` | Technologie et bande affichées ; conservées dans chaque enregistrement source. |
| `emr_dt` | Date déclarée, conservée par support et système ; absence explicite. La synthèse station–bande retient la première date renseignée. |
| `sta_nm_dpt` | Code de département ANFR consultable. Il reste une chaîne pour conserver son format. |
| `code_insee` | Code source conservé, même s’il double actuellement `com_cd_insee`. |
| `generation` | Génération source conservée par enregistrement. Une technologie inconnue n’est plus classée artificiellement en 2G. |
| `date_maj` | Date de publication/mise à jour source. |
| `sta_nm_anfr` | Identifiant stable utilisé pour la station et les favoris. Il n’est pas un ECI/eNodeB. |
| `nat_id` | Code et libellé officiel du type de support. |
| `sup_nm_haut` | Hauteur de support déclarée, sans la confondre avec l’altitude. |
| `tpo_id` | Code et libellé officiel du propriétaire du support, qui peut être différent de l’opérateur. |
| `adr_lb_lieu` | Lieu/complément conservé et intégré à l’adresse lisible. |
| `adr_lb_add1` | Adresse conservée ; abréviation de voie développée pour l’affichage si reconnue. |
| `adr_lb_add2` | Complément conservé et affiché lorsqu’il existe. |
| `adr_lb_add3` | Complément conservé et affiché lorsqu’il existe. |
| `adr_nm_cp` | Code postal conservé en texte, avec ses zéros éventuels. |
| `com_cd_insee` | Code de commune, associé à un nom officiel lorsque disponible. |
| `coordonnees` | Coordonnées décimales validées et utilisées par la carte ; chaîne d’origine également conservée. |
| `coord` | Coordonnées en degrés/minutes/secondes conservées dans les champs bruts. |
| `statut` | État exact conservé pour chaque système/support, sans convertir un projet en installation en service. |
| `list_azimut` | Directions par support/système, valeurs d’origine conservées ; 360° équivaut à 0° dans l’affichage et ND reste inconnu. |

Les détails sont dans la fiche de station, rubrique **Ce que déclare l’ANFR**. Chaque support possède ses propres systèmes, dates et états. L’export JSON reconstitue les colonnes originales, sans appliquer les reformulations d’adresse.

Les tables de détails supplémentaires restent compatibles avec le format de base Pylo 2. Une ancienne copie de base continue de fonctionner mais ne présente pas les nouvelles rubriques tant qu’une base enrichie n’a pas été installée.

## Contrôles lors des prochains imports

Le pipeline vérifie les colonnes attendues, les identifiants de lignes, le format des lignes et les coordonnées. Il prépare `quality.json`, joint à la publication, avec les dates manquantes, les orientations inconnues, les azimuts 360°, les codes sans libellé et les hauteurs déclarées à zéro. Ces situations sont signalées, pas corrigées arbitrairement. Les nomenclatures sont rafraîchies lors d’une nouvelle préparation ; une copie documentée incluse dans le projet sert de repli si les services auxiliaires sont indisponibles.

## Informations iPhone utiles

| Information publique | Utilisation et limites |
| --- | --- |
| Technologie radio par service | Affichage par ligne anonyme et identification de la ligne de données lorsque fournie par iOS ; aucune déduction forcée si la valeur manque. |
| Accès cellulaire de Pylo | Restriction d’usage de l’app, pas preuve de couverture ni état général du forfait. |
| Chemin internet | Wi-Fi/mobile/hors ligne, mode données réduites et connexion marquée coûteuse par iOS. Ce dernier indicateur n’est pas le prix facturé. |
| IPv4, IPv6, DNS | Capacités déclarées du chemin courant, sans prétendre avoir testé un serveur distant. |
| Autorisation de localisation | Précise/approximative/refusée, visible dans le guide. |
| Position et précision | Distance et cap vers les stations ; horodatage et précision indiqués. Lecture à la demande, sans historique enregistré. |
| Altitude | Estimation et précision verticale lorsqu’elles sont valides. Ni hauteur d’antenne ni différence de hauteur fiable avec un support ANFR. |
| Vitesse et direction de déplacement | Valeurs du dernier relevé de position quand elles sont disponibles ; la direction n’est pas présentée à l’arrêt. Aucun suivi GPS continu n’est ajouté. |
| Boussole | Cap, précision, distinction nord vrai/nord magnétique ; valeurs invalides masquées et arrêt en arrière-plan. |

Le SDK public ne permet pas à Pylo de lire la cellule servante, les voisins radio, les bandes actives ou les RSRP/RSRQ/SINR. Le nom opérateur historique de CTCarrier est déprécié et ne sert pas à inventer une identification fiable. Les numéros de téléphone, IMEI et identifiants SIM ne sont pas collectés. Les données sans rapport utile avec le réseau — contacts, photos, santé, microphone, etc. — ne sont pas demandées pour gonfler une liste de fonctions.

D’autres données ANFR existent dans d’autres jeux, notamment sur des installations de plus de 5 W. Les puissances détaillées, inclinaisons, diagrammes de rayonnement et une couverture mesurée ne figurent pas dans le CSV mobile utilisé ici : Pylo ne les fabrique pas. Une intégration de ces jeux nécessiterait des correspondances et une validation séparées.

## Sources

- [ANFR : observatoire mobile et nomenclatures NAT_ID/TPO_ID](https://data-backoffice.anfr.fr/en/dataset/observatoire_2g_3g_4g)
- [ANFR sur data.gouv.fr](https://www.data.gouv.fr/datasets/donnees-sur-les-reseaux-mobiles)
- [API géographique de l’État](https://geo.api.gouv.fr/)
- [La Poste : abréviations d’adresses](https://www.laposte.fr/envoyer/abreviation-adresses-postales)
- [Apple : CLLocation](https://developer.apple.com/documentation/corelocation/cllocation)
- [Apple : CTCellularData](https://developer.apple.com/documentation/coretelephony/ctcellulardata)
- [Apple : technologie radio déclarée par service](https://developer.apple.com/documentation/coretelephony/cttelephonynetworkinfo/servicecurrentradioaccesstechnology)

## Complément : dates administratives des stations

Pylo relie désormais `STA_NM_ANFR` à `SUP_STATION.txt` du [jeu officiel des installations de plus de 5 watts](https://www.data.gouv.fr/datasets/donnees-sur-les-installations-radioelectriques-de-plus-de-5-watts-1). Les champs `DTE_IMPLANTATION`, `DTE_EN_SERVICE` et `DTE_MODIF` sont conservés dans une petite table distincte, avec le titre de leur publication source. Les identifiants restent des chaînes pour conserver les zéros initiaux. Les dates vides restent non renseignées. Une station mobile récente peut être absente de cette publication mensuelle, même si elle apparaît déjà dans l’observatoire mobile hebdomadaire.

La surveillance compare les versions des deux ressources : une nouvelle publication des installations déclenche aussi une nouvelle base. Une erreur de téléchargement, de schéma ou de rapprochement interrompt la publication et conserve la base publique précédente. Ces dates de station sont distinctes des dates système de l’observatoire et de la date de publication de chaque fichier.
