# Maintenance de Pylo

## Développement local

Il faut **Xcode 26 ou plus récent** et **iOS 18 minimum**.

1. Clone le dépôt et ouvre `Pylo.xcodeproj`.
2. Sélectionne le schéma **Pylo**, puis un simulateur iPhone.
3. Pour ton iPhone, choisis ton équipe dans **Signing & Capabilities**.

Une seule dépendance, FirebaseMessaging (Swift Package Manager, résolue automatiquement par Xcode), pour les notifications instantanées. Le reste est écrit en Swift, avec SwiftUI, MapKit, Swift Charts et SQLite.

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


## Publication des données

Le workflow `.github/workflows/anfr.yml` vérifie le catalogue officiel chaque jour à 07:23 UTC. `workflow_dispatch` permet un lancement manuel, avec `force` si une reconstruction est souhaitée malgré une source identique. L’ANFR déclare une fréquence hebdomadaire ; ne pas supposer une publication le premier ou le troisième jour du mois.

Le workflow choisit une ressource précise et garde sa sélection pendant l’import, même si le catalogue change entre-temps. Il télécharge la base précédente, compare les identifiants, prépare et valide la nouvelle base, puis crée une Release avec une URL immuable. Seulement après l’envoi des fichiers, il remplace `data/manifest.json` via l’API GitHub. Un échec antérieur laisse le manifeste et les applications sur la publication précédente. Aucun secret supplémentaire n’est nécessaire : le GITHUB_TOKEN du workflow est limité à ce dépôt.

Dans GitHub Actions, activer les notifications d’échec pour surveiller les changements de format ou les interruptions de source. Après un changement de colonnes, adapter le mapping et lancer les tests ainsi qu’un import complet avant publication.

## Mise à jour dans l’app

Le contrôle automatique a lieu à l’ouverture/retour dans l’app ou au rétablissement du Wi-Fi, au maximum une fois par 24 h après une vérification réussie. La base elle-même n’est jamais téléchargée en arrière-plan : seules les notifications le sont (voir plus bas). Les téléchargements de bases sont limités au Wi-Fi hors mode données réduites. Le bouton Vérifier maintenant permet une lecture du manifeste à la demande.

DataUpdates contrôle le schéma, l’hôte et le chemin du dépôt, la taille compressée, le SHA-256, la taille décompressée, l’intégrité SQLite et la date source. La base est préparée à côté de la destination puis remplacée atomiquement. Une erreur garde la copie précédente. Les favoris sont dans un stockage distinct.

Test complet de la publication publique sur Mac :

```sh
swift run anfr-import --verify-update /tmp/pylo-update-check.sqlite
```

## Notifications

Deux chemins, gratuits tous les deux. La position, les zones et les favoris ne quittent jamais l’iPhone.

**Publication.** Quand `PYLO_PREVIOUS_DATABASE` est fourni, l’import compare la nouvelle base à la précédente (`AntennaDatabase.changeReport`) et écrit `changes.json` : pour chaque station ajoutée, retirée ou modifiée, l’opérateur, la position, l’adresse, les systèmes ajoutés ou retirés, les changements de statut et les codes `orientation`, `height`, `location`, `supports`. Statuts, hauteurs (`30` = `30,0`) et azimuts sont normalisés pour éviter les faux changements dus à l’ordre des lignes CSV. Le fichier va dans la même Release que la base, et le manifeste le référence dans `changes` (URL, SHA-256, taille). Le champ est facultatif : les anciennes versions de l’app l’ignorent. Ordre de grandeur au 5 novembre 2026 : 7 500 stations, 2 Mo, 4 s de calcul.

**Push instantané (Firebase Cloud Messaging, offre gratuite).** Après la mise en ligne du manifeste, l’étape « Prévenir les iPhone » du workflow envoie deux messages à des sujets FCM, sans liste d’appareils à stocker :
- `anfr-data` : alerte visible, même texte pour tout le monde, généré par `anfr-import --push-message`.
- `anfr-changes` : signal silencieux (`content-available`, priorité 5). iOS réveille Pylo, qui télécharge `changes.json` et construit lui-même les alertes de zones et de favoris.

L’étape s’authentifie avec le compte de service du secret `FIREBASE_SERVICE_ACCOUNT` (JWT signé avec `openssl`, aucun outil à installer). Sans ce secret, elle s’arrête proprement et les iPhone voient la publication par l’actualisation en arrière-plan. Une erreur d’envoi n’annule pas la publication.

**Côté app.** `PushService` (dans `App/Alerts.swift`) ne démarre Firebase que si `App/GoogleService-Info.plist` est présent. L’app s’abonne à `anfr-data` si l’alerte de données est activée, à `anfr-changes` si les favoris ou une zone sont suivis, et se désabonne sinon. Le swizzling Firebase est coupé (`FirebaseAppDelegateProxyEnabled` = NO) : `AppDelegate` transmet lui-même le jeton APNs.

`AlertChecker.run()` est le seul point d’entrée : signal silencieux, `BGAppRefreshTask` (`org.epimac.pylo.alerts`, toutes les 4 h au plus tôt, en secours), lancement et retour au premier plan (une fois par heure au plus). Il s’arrête si `sourceDate` n’est pas plus récente que `alertLastSourceDate`, télécharge `changes.json` si besoin (taille + SHA-256 + date vérifiées), puis `AlertDigest` construit au plus quatre notifications : données ANFR (seulement si l’appareil n’est pas abonné à `anfr-data`), favoris, nouvelles antennes, changements. Une station favorite n’est pas répétée dans les alertes de zone. Pour chaque zone, `newAntennasKM` et `changesKM` sont facultatifs ; une station est rattachée à la zone la plus proche qui la couvre. En cas d’erreur réseau, la date n’avance pas et le prochain réveil réessaie.

Limites : iOS peut retarder un signal silencieux (batterie faible, mode économie d’énergie) et ne réveille pas une app fermée de force ; l’alerte visible `anfr-data`, elle, arrive toujours. `changes.json` décrit seulement l’écart avec la publication précédente.

**Mise en place de Firebase (une fois).** Version détaillée, clic par clic : [NOTIFICATIONS-PAS-A-PAS.md](NOTIFICATIONS-PAS-A-PAS.md).
1. Sur console.firebase.google.com, créer un projet (offre Spark, gratuite, sans Analytics), puis ajouter une app iOS avec le bundle `org.epimac.pylo`.
2. Télécharger `GoogleService-Info.plist` et le placer dans `App/`. La phase de build « Firebase config » le copie dans l’app s’il existe (sinon, simple avertissement). Il peut être versionné : ce n’est pas un secret.
3. Sur developer.apple.com, créer une clé APNs (Keys → +, Apple Push Notifications service), puis l’importer dans Firebase (Paramètres du projet → Cloud Messaging → Configuration de l’app Apple) avec le Key ID et le Team ID.
4. Dans Xcode, onglet Signing & Capabilities, vérifier que Push Notifications et Background Modes (Background fetch, Remote notifications) apparaissent bien. `App/Pylo.entitlements` les déclare déjà.
5. Firebase → Paramètres du projet → Comptes de service → Générer une nouvelle clé privée. Coller le JSON complet dans un secret GitHub `FIREBASE_SERVICE_ACCOUNT` (Settings → Secrets and variables → Actions).
6. Dans App Store Connect, mettre à jour la confidentialité de l’app : Identifiants → Identifiant de l’appareil, utilisé pour les fonctionnalités de l’app, non lié à l’identité, sans suivi.

**Tester.** Pour rejouer une alerte, remettre `alertLastSourceDate` à une date antérieure. Une alerte visible se simule avec `xcrun simctl push <appareil> org.epimac.pylo fichier.apns`. Le simulateur refuse les pushs purement silencieux : tester le signal `anfr-changes` sur un iPhone, ou simuler le réveil en arrière-plan depuis la console LLDB :

```
e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"org.epimac.pylo.alerts"]
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

## Statistiques et chargement

Les résultats statistiques sont conservés en mémoire par opérateur et invalidés à chaque changement de base. Les requêtes simultanées identiques partagent le même calcul. Les fiches lisent les systèmes, supports et détails hors du fil principal. Une base locale déjà installée évite une décompression inutile de la copie embarquée au lancement.

Les fréquences séparent les libellés, les nombres et les barres. Le graphique mensuel affiche douze mois, y compris les mois à zéro, avec quatre repères espacés et un détail dépliable. Le début de période est calculé depuis le premier jour du mois pour éviter les décalages des 29, 30 et 31.

Au lancement, la carte restaure `lastMapViewport` (centre et zoom, valeurs validées), puis demande une position ponctuelle avec l’autorisation iOS. Un échec conserve cette zone ; au tout premier lancement sans position, le centre initial est Paris. Seuls le lancement et le bouton de localisation demandent un recentrage : un rafraîchissement GPS au retour au premier plan ne déplace pas la caméra. Le zoom courant est conservé et un geste de carte, un bouton de zoom ou une recherche annule le recentrage encore en attente. La dernière zone est remplacée localement à chaque changement de région ; aucun historique n’est conservé.
