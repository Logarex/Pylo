# Fiche App Store Connect · Pylo

Textes prêts à copier, rubrique par rubrique, dans l'ordre d'App Store Connect.
Les limites de caractères sont indiquées entre crochets ; tous les textes les respectent.

---

## 1. Nouvelle app (création)

| Champ | Valeur |
|---|---|
| Plateformes | iOS |
| Nom | `Pylo` (si le nom est pris : `Pylo – Antennes 4G et 5G`) |
| Langue principale | Français (France) |
| Identifiant de lot (Bundle ID) | `org.epimac.pylo` |
| SKU | `PYLO-IOS-001` |
| Accès utilisateur | Accès complet |

---

## 2. Informations sur l'app

**Nom** [30] : `Pylo`

**Sous-titre** [30] :
```
Les antennes autour de toi
```

**Catégorie principale** : Utilitaires
**Catégorie secondaire** : Navigation (alternative : Éducation)

**Droits sur le contenu** : « Oui, elle contient ou accède à du contenu tiers et je dispose des droits nécessaires. »
→ Les données ANFR sont sous Licence Ouverte 2.0, qui autorise la réutilisation avec attribution (faite dans l'app, onglet « Le projet »).

**Classification par âge** (questionnaire) : répondre **Aucun / Non** partout.
- Pas de contenu violent, sexuel, de jeux d'argent, de drogue ni de langage grossier.
- Pas de contenu généré par les utilisateurs, pas de messagerie, pas de navigateur web intégré (les liens s'ouvrent dans Safari).
- Pas de contrôle parental ni de vérification d'âge.
→ Résultat attendu : **4+**.

**Contrat de licence** : Contrat de licence d'utilisateur final standard d'Apple. (Le code est sous GPL-3.0 sur GitHub, mais le CLUF standard suffit pour l'App Store.)

**Conformité au Digital Services Act (UE)** : déclarer **« Je ne suis pas un professionnel (non-trader) »**.
→ App gratuite, sans pub ni achat, projet étudiant non commercial. Si Epimac est enregistrée comme entreprise et veut se déclarer professionnelle, il faudra alors fournir adresse, téléphone et e-mail publics.

---

## 3. Tarifs et disponibilité

- **Prix** : Gratuit (0 €)
- **Disponibilité** : France uniquement (les données ANFR couvrent la France métropolitaine et l'outre-mer). Tu peux ouvrir tous les pays plus tard si tu le souhaites.
- **Disponible sur Mac (Apple Silicon)** : non (l'app est pensée pour iPhone et iPad).
- **Disponible sur Apple Vision Pro** : non.
- **Précommande** : non.

---

## 4. Confidentialité de l'app

**URL de la politique de confidentialité** (obligatoire) :
```
https://github.com/Logarex/Pylo#vie-privée-et-sources
```
(Mieux : une page dédiée, par exemple un fichier `PRIVACY.md` dans le dépôt. Texte proposé en annexe A.)

**Collecte de données** : **« Oui, nous collectons des données depuis cette app »**, puis une seule catégorie :
- **Identifiants → Identifiant de l’appareil** (jeton Firebase Cloud Messaging)
  - Utilisation : **Fonctionnalités de l’app** (notifications)
  - Lié à l’identité : **Non**
  - Utilisé pour le suivi : **Non**

Pourquoi :
- La position, le cap, les favoris, les zones d’alerte et la dernière zone de carte restent sur l’iPhone et ne sont envoyés à aucun serveur.
- Les notifications instantanées passent par Firebase Cloud Messaging : l’iPhone s’abonne à deux sujets communs à tous (`anfr-data`, `anfr-changes`). Firebase reçoit un jeton technique, pas la position ni les zones ni les favoris.
- Aucun compte, aucune analytique, aucune publicité.
- Les recherches et itinéraires passent par Apple Plans (service d’Apple, non compté comme collecte par le développeur).

→ Étiquette affichée : **« Données non liées à vous : Identifiants »**.

---

## 5. Accessibilité (étiquettes d'accessibilité)

Ne coche que ce que tu as testé toi-même. Ce qui est sûr aujourd'hui :
- ✅ **Interface sombre** : l'app suit le thème clair ou sombre de l'iPhone.
- ✅ **Texte plus grand** : polices système (Dynamic Type). À vérifier en taille maximale avant de cocher.
- ⚠️ **VoiceOver** : les boutons principaux ont des étiquettes. À tester sur tout le parcours avant de cocher.
- ❌ Sous-titres, audiodescription : sans objet (pas de vidéo ni d'audio).

Tu peux aussi laisser cette rubrique vide pour l'instant : elle est facultative.

---

## 6. Page de la version 1.0.0 (iOS)

### Aperçus et captures d'écran
- **iPhone 6,9″** (1320 × 2868) : dossier `appstore/screenshots/iphone-6.9/`
- **iPad 13″** (2064 × 2752) : dossier `appstore/screenshots/ipad-13/` (obligatoire, car l'app tourne aussi sur iPad)

App Store Connect réduit lui-même ces captures pour les autres tailles d'écran.

### Texte promotionnel [170]
```
Les données ANFR sont à jour : explore les antennes 2G, 3G, 4G et 5G autour de toi, filtre par opérateur et découvre ce que cache le logo réseau de ton iPhone.
```

### Description [4000]
```
Je suis étudiant et j'ai créé Pylo parce que je voulais comprendre les antennes autour de moi et ce que veulent vraiment dire les logos 4G, 5G ou 5G+ de mon iPhone. L'idée : tout réunir dans une app simple, gratuite, sans pub et sans compte.

EXPLORER
• Une carte Apple Plans avec les antennes 2G, 3G, 4G et 5G déclarées à l'ANFR.
• Une recherche avec suggestions pour aller n'importe où en France.
• Des filtres par opérateur et par génération.
• Des flèches qui montrent les directions déclarées des antennes.
• La carte se place autour de toi à l'ouverture, ou retrouve ta dernière zone consultée.

LES FICHES
Pour chaque station : technologies, bandes de fréquence, supports, hauteur, propriétaire déclaré, adresse, distance et orientation par rapport à toi. Les dates d'implantation, de mise en service et de dernière modification apparaissent quand elles sont renseignées.

FAVORIS
Garde tes stations préférées, partage-les ou ouvre un itinéraire dans Plans.

FIELD TEST
Un guide pour ouvrir le menu caché de l'iPhone et comprendre ce qu'il affiche : puissance du signal (RSRP), qualité (RSRQ, SINR), technologies et identifiants radio. Un décodeur ECI LTE t'aide à lire les identifiants.

STATISTIQUES
Le nombre de stations, de supports, de générations et de fréquences, et leur évolution entre deux publications. Tu peux aussi comparer deux opérateurs.

COMPRENDRE
De courtes fiches pour s'y retrouver : GSM, UMTS, LTE, NR, 4G+, 5G NSA et SA, fréquences basses et hautes… Les notions que j'aurais aimé avoir sous la main au début.

DONNÉES À JOUR
Les antennes viennent des publications officielles de l'ANFR. Pylo vérifie les nouveautés au maximum une fois par jour et télécharge la base en Wi-Fi. Elle reste consultable hors ligne.

VIE PRIVÉE
Pas de compte, pas de pub, pas de suivi. Tes favoris, ta position et tes zones d'alerte restent sur ton iPhone.

BON À SAVOIR
Les flèches montrent une direction déclarée, pas une couverture. La station la plus proche n'est pas forcément celle à laquelle ton iPhone est connecté : iOS ne laisse pas les apps lire cette information.

Pylo est open source (GPL-3.0) et indépendante. Elle n'est affiliée ni à Apple, ni à l'ANFR, ni aux opérateurs. Données ANFR sous Licence Ouverte 2.0.

Une idée ou un bug ? Écris-moi à pylo@nephoos.com : tes retours m'aident à améliorer l'app.
```

### Mots-clés [100]
```
antenne,ANFR,5G,4G,réseau mobile,pylône,opérateur,fréquence,signal,Field Test,relais,couverture,3G
```
(Pas de noms d'opérateurs : Apple peut refuser les marques déposées dans les mots-clés.)

### URL d'assistance (obligatoire)
```
https://github.com/Logarex/Pylo/issues
```

### URL marketing (facultatif)
```
https://github.com/Logarex/Pylo
```

### Version
`1.0.0`

### Copyright
```
2026 Louis Chabert
```

### Couverture de l'app de routage
Ne rien envoyer : Pylo ouvre les itinéraires dans Plans mais n'est pas une app de guidage.

### Build
Choisir le build envoyé depuis Xcode (Product › Archive › Distribute App › App Store Connect).

**Conformité à l'exportation (chiffrement)** : « Aucun des algorithmes mentionnés ci-dessus » / l'app n'utilise que le chiffrement standard d'iOS (HTTPS).
→ Astuce : ajouter `ITSAppUsesNonExemptEncryption = NO` dans l'Info.plist évite de répondre à chaque build.

### Nouveautés de cette version
Pas demandé pour la première version. Pour les suivantes, par exemple :
```
Les antennes s'affichent plus vite, le zoom est plus stable et tu peux maintenant m'écrire directement depuis l'onglet « Le projet ».
```

---

## 7. Informations pour la vérification de l'app (App Review)

**Connexion requise** : décocher (aucun compte dans l'app).

**Coordonnées** (à compléter) :
- Prénom : Louis
- Nom : Chabert
- Téléphone : `+33 …` (ton numéro, visible seulement par Apple)
- E-mail : `pylo@nephoos.com`

**Remarques** [4000] :
```
Bonjour,

Pylo ne demande aucun compte : toutes les fonctions sont accessibles dès l'ouverture.

L'app affiche les antennes de téléphonie mobile déclarées à l'ANFR (Agence nationale des fréquences), à partir de ses données publiques sous Licence Ouverte 2.0. Une base est incluse dans l'app et peut être mise à jour depuis GitHub en Wi-Fi.

La localisation est demandée uniquement pendant l'utilisation, pour centrer la carte et calculer la distance et la direction des antennes. Elle n'est envoyée à aucun serveur. Si elle est refusée, la carte s'ouvre sur Paris et reste entièrement utilisable. Les données couvrent la France : depuis l'étranger, il suffit de chercher « Paris » ou de déplacer la carte.

L'onglet Field Test explique comment ouvrir le menu de diagnostic intégré à iOS en composant *3001#12345#* dans l'app Téléphone. Pylo n'appelle aucune API privée : il affiche seulement le code (avec un bouton Copier) et aide à comprendre les valeurs.

Pylo est un projet étudiant gratuit, sans publicité, sans achat intégré et sans suivi.

Merci pour votre vérification !
Louis
```

**Pièce jointe** : facultatif (aucune nécessaire).

---

## 8. Publication de la version

Recommandé : **« Publier manuellement cette version »**, pour choisir toi-même le jour de sortie une fois la validation obtenue.

---

## Annexe A · Politique de confidentialité (à publier en `PRIVACY.md`)

```
# Politique de confidentialité de Pylo

Dernière mise à jour : 2 novembre 2026

Pylo ne collecte pas de donnée personnelle. La seule exception concerne les notifications, si tu les actives (voir plus bas).

• Pas de compte, pas de publicité, pas d'outil de mesure d'audience ni de suivi.
• Ta position sert seulement pendant l'utilisation, pour centrer la carte et calculer la distance et la direction des antennes. Elle n'est ni enregistrée en historique ni envoyée à un serveur.
• Tes favoris et la dernière zone de carte consultée restent sur ton appareil.
• Les recherches d'adresses et les itinéraires sont traités par Apple Plans, selon la politique de confidentialité d'Apple.
• La base d'antennes est téléchargée depuis GitHub, sans transmettre ta position ni tes favoris.
• Si tu actives les notifications, ton appareil s'abonne à deux canaux communs via Firebase Cloud Messaging (Google). Firebase reçoit un identifiant technique de notification, pas ta position, tes zones ou tes favoris : le tri est fait sur ton appareil.

Contact : pylo@nephoos.com
```
