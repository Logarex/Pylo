# Activer les notifications instantanées, pas à pas

Le code est prêt. Il reste à brancher trois comptes que toi seul peux ouvrir : Firebase (Google), Apple Developer et GitHub. Compte 20 à 30 minutes, une seule fois.

Tant que ce n’est pas fait, Pylo marche quand même : les alertes arrivent, mais quelques heures après la publication au lieu de quelques minutes.

## Ce que fait chaque morceau

- **Firebase** envoie les notifications aux iPhone. C’est gratuit.
- **Apple** autorise Firebase à parler aux iPhone, grâce à une clé.
- **GitHub** prévient Firebase quand l’ANFR publie, grâce à un mot de passe technique rangé dans un « secret ».

---

## Étape 1 · Créer le projet Firebase (5 min)

1. Va sur https://console.firebase.google.com et connecte-toi avec ton compte Google.
2. Clique sur **Créer un projet**. Nom : `Pylo`.
3. Quand on te propose **Google Analytics**, désactive-le. Pylo n’en a pas besoin.
4. Clique sur **Créer le projet**, puis **Continuer**.

## Étape 2 · Ajouter l’app iPhone et récupérer le fichier (5 min)

1. Sur la page du projet, clique sur l’icône **iOS** (« Ajouter une application »).
2. **ID du bundle Apple** : `org.epimac.pylo` (exactement).
3. Surnom : `Pylo`. Laisse l’App Store ID vide. Clique sur **Enregistrer l’application**.
4. Clique sur **Télécharger GoogleService-Info.plist**.
5. Mets ce fichier dans le dossier `App/` du projet :
   `/Users/louischabert/Documents/ChatGPT/Pylo/App/GoogleService-Info.plist`
6. Les étapes suivantes de Firebase (« Ajouter le SDK », « Code d’initialisation ») sont **déjà faites** : clique sur **Suivant** jusqu’à la fin.

Rien à faire dans Xcode : le fichier est pris automatiquement à la compilation.

## Étape 3 · Créer la clé Apple et la donner à Firebase (10 min)

1. Va sur https://developer.apple.com/account/resources/authkeys/list
2. Clique sur le **+** bleu.
3. Nom : `Pylo push`. Coche **Apple Push Notifications service (APNs)**, puis **Continue** et **Register**.
4. Clique sur **Download**. Tu obtiens un fichier `AuthKey_XXXXXXXXXX.p8`. **Garde-le bien** : Apple ne le redonne qu’une fois.
5. Note deux choses affichées sur la page :
   - le **Key ID** (10 caractères),
   - ton **Team ID** (en haut à droite, sous ton nom).
6. Retourne dans Firebase : roue dentée en haut à gauche → **Paramètres du projet** → onglet **Cloud Messaging**.
7. Section **Configuration de l’application Apple** → **Clé d’authentification APNs** → **Importer**.
8. Choisis le fichier `.p8`, colle le Key ID et le Team ID, puis **Importer**.

## Étape 4 · Donner à GitHub le droit d’envoyer (5 min)

1. Dans Firebase : **Paramètres du projet** → onglet **Comptes de service**.
2. Clique sur **Générer une nouvelle clé privée**, puis confirme. Un fichier `.json` se télécharge.
3. Dans le Terminal, lance cette commande en remplaçant le nom du fichier par le tien :

```bash
gh secret set FIREBASE_SERVICE_ACCOUNT --repo Logarex/Pylo < ~/Downloads/pylo-xxxxx-firebase-adminsdk-xxxxx.json
```

4. Ensuite, **supprime ce fichier .json** de ton dossier Téléchargements : c’est un mot de passe.

## Étape 5 · Vérifier dans Xcode (2 min)

1. Ouvre `Pylo.xcodeproj`, clique sur le projet **Pylo**, puis la cible **Pylo**, onglet **Signing & Capabilities**.
2. Tu dois voir **Push Notifications** et **Background Modes** (avec *Background fetch* et *Remote notifications* cochés).
3. S’il y a un message d’erreur rouge sur la signature, clique sur **Try Again** : Xcode met à jour ton identifiant d’app chez Apple tout seul.

## Étape 6 · Tester sur ton iPhone (5 min)

1. Lance Pylo sur ton iPhone depuis Xcode (pas le simulateur).
2. Onglet **Le projet** → **Notifications** → active **Nouvelles données ANFR** et accepte les notifications.
3. Dans Firebase : menu de gauche **Messaging** (ou « Exécuter » → « Messaging ») → **Nouvelle campagne** → **Notifications Firebase**.
4. Titre : `Test Pylo`, texte : `Ça marche`. **Suivant**.
5. Cible : **Sujet** → `anfr-data`. **Suivant** → **Planification : Maintenant** → **Examiner** → **Publier**.
6. La notification doit arriver sur ton iPhone dans la minute. Si elle n’arrive pas, attends 5 minutes (le premier abonnement peut être lent), ferme et rouvre Pylo, puis renvoie.

## Étape 7 · App Store Connect (2 min, avant la prochaine version)

Dans App Store Connect → ton app → **Confidentialité de l’app** → **Modifier** :
- Coche **Identifiants** → **Identifiant de l’appareil**.
- Utilisation : **Fonctionnalités de l’app**.
- Lié à l’identité : **Non**. Utilisé pour le suivi : **Non**.

---

## Ensuite, plus rien à faire

À chaque publication de l’ANFR, le robot lance GitHub, qui envoie les notifications tout seul. Dans l’onglet **Actions** du dépôt, l’étape « Prévenir les iPhone » indique si l’envoi a marché.

---

## Étape 8 · Le robot qui surveille l’ANFR chaque minute (15 min)

Sans lui, GitHub vérifie l’ANFR une fois par jour, souvent avec plusieurs heures de retard. Avec lui, la publication est repérée en une minute environ, et la notification part 3 à 5 minutes après la publication de l’ANFR, le temps de préparer la base.

Le robot tourne chez Cloudflare, gratuitement. Son code est dans le dossier `watcher/`.

**8.1 · Créer un compte Cloudflare**
Va sur https://dash.cloudflare.com/sign-up et crée un compte gratuit. Aucune carte bancaire n’est demandée pour les Workers.

**8.2 · Créer une clé GitHub qui ne sert qu’à lancer le workflow**
1. Va sur https://github.com/settings/personal-access-tokens/new
2. Nom : `Pylo robot ANFR`. Expiration : 1 an.
3. **Repository access** → **Only select repositories** → `Logarex/Pylo`.
4. **Permissions** → **Repository permissions** → **Actions** → **Read and write**. Ne touche à rien d’autre.
5. **Generate token**, puis copie la clé (elle commence par `github_pat_`). Garde l’onglet ouvert, elle ne s’affiche qu’une fois.

**8.3 · Mettre le robot en ligne** (dans le Terminal, une commande à la fois)

```bash
cd /Users/louischabert/Documents/ChatGPT/Pylo/watcher
```

```bash
npx wrangler login
```
Une page Cloudflare s’ouvre : clique sur **Allow**.

```bash
npx wrangler deploy
```
À la fin, une adresse s’affiche, du type `https://pylo-anfr-watcher.xxxx.workers.dev`.

```bash
npx wrangler secret put GITHUB_TOKEN
```
Colle la clé GitHub de l’étape 8.2, puis Entrée. Tu peux ensuite fermer l’onglet GitHub.

**8.4 · Vérifier**
Ouvre l’adresse `…workers.dev` dans ton navigateur. Tu dois voir `"a_jour": true` : Pylo a les mêmes données que data.gouv. Quand l’ANFR publiera, le robot lancera GitHub tout seul dans la minute.

Dans Cloudflare → **Workers & Pages** → `pylo-anfr-watcher` → **Logs**, chaque minute affiche `rien`, `attente` ou `lancé`.
