import SwiftUI
import UniformTypeIdentifiers
struct LearnView: View {
    private let entries: [(String,String,String)] = [
        ("2G · GSM", "Les appels et les premiers SMS", "GSM est la technologie radio de la 2G. GPRS ajoute les données par paquets (souvent le symbole G) ; EDGE améliore leur transmission (symbole E). Une station déclarée GSM ne permet pas de confirmer séparément l’activation de GPRS ou EDGE."),
        ("3G · UMTS / WCDMA", "Puis HSPA et HSPA+", "UMTS s’appuie notamment sur WCDMA. HSDPA améliore le téléchargement, HSUPA l’envoi ; HSPA et HSPA+ regroupent ces évolutions, souvent affichées H ou H+. Le fichier ANFR ne détaille pas chaque fonction activée."),
        ("4G · LTE / LTE-Advanced", "Des données et des appels sur IP", "LTE est la radio 4G. LTE-Advanced ajoute notamment l’agrégation de porteuses, souvent appelée 4G+. VoLTE permet de passer les appels sur le réseau 4G, selon la compatibilité de la ligne et du téléphone."),
        ("5G · NR / VoNR", "Une nouvelle radio", "NR signifie New Radio. En 5G SA, les appels peuvent utiliser VoNR lorsque le réseau et l’appareil le permettent. Sinon, ils peuvent s’appuyer sur une autre génération. Une déclaration ANFR ne prouve pas l’activation de toutes ces fonctions."),
        ("3G", "La génération qui a lancé l’internet mobile", "Elle sert aux appels et aux données selon les réseaux encore disponibles. Son arrêt est progressif et dépend de l’opérateur : une station présente dans la base peut avoir changé depuis la publication."),
        ("4G", "Le réseau du quotidien", "La 4G utilise LTE. Plusieurs bandes peuvent être regroupées pour augmenter la capacité : c’est l’agrégation de porteuses, souvent appelée 4G+."),
        ("5G", "Plus de capacité, selon les bandes", "La 5G en 700 MHz porte loin. Le 3,5 GHz apporte davantage de capacité, avec une portée plus courte. Le logo 5G ne suffit donc pas à deviner le débit."),
        ("NSA / SA", "Deux façons de faire de la 5G", "En NSA, la 5G s’appuie sur une connexion 4G. En SA, elle utilise un cœur de réseau 5G. La base ANFR ne permet pas de confirmer le mode de ta connexion."),
        ("Fréquences", "Portée et capacité", "Les bandes basses, comme 700, 800 ou 900 MHz, traversent généralement mieux les obstacles. Les bandes plus hautes offrent de la capacité. Le relief, les murs et la charge du réseau comptent aussi."),
        ("RSRP", "La puissance reçue", "Une valeur moins négative correspond à un signal plus fort : −80 dBm est plus fort que −110 dBm. C’est un indicateur radio, pas une mesure de débit. En 3G, on rencontre plutôt le RSCP."),
        ("RSRQ / SINR", "La qualité du signal", "Le RSRQ décrit la qualité du signal de référence ; le SINR compare le signal utile au bruit et aux interférences. Un SINR plus élevé est généralement préférable. Compare surtout tes relevés dans les mêmes conditions."),
        ("ANFR", "Une station n’est pas une carte de couverture", "L’ANFR recense des installations déclarées. Une station peut porter plusieurs systèmes et bandes. Les états autorisé, en service et techniquement opérationnel doivent être lus tels qu’ils sont publiés.")]
    var body: some View {
        NavigationStack {
            List {
                Section { Text("Le réseau mobile, sans se prendre la tête.").font(.title2.bold()); Text("J’ai créé Pylo pour comprendre les antennes autour de moi. Voilà les notions que j’aurais aimé avoir sous la main au début.").foregroundStyle(.secondary) }
                ForEach(entries, id: \.0) { entry in Section(entry.0) { Text(entry.1).font(.headline); Text(entry.2) } }
            }.navigationTitle("Comprendre")
        }
    }
}
struct DataView: View {
    @Environment(AppStore.self) private var store
    @State private var importing = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Image("Brand").resizable().scaledToFit().frame(height: 100).frame(maxWidth: .infinity).accessibilityLabel("Logo Pylo")
                    Text("Pylo").font(.largeTitle.bold())
                    Text("Gratuite. Code sous licence libre. Développée par un étudiant.").font(.headline)
                    Text("J’aime comprendre comment le réseau fonctionne. Alors j’ai créé Pylo : une app simple pour explorer les antennes et apprendre au passage. Pas de pub, pas de compte, pas de suivi.")
                    Text("Le dépôt est privé pendant le développement. Son ouverture publique viendra ensuite.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Pour aller plus loin") {
                    NavigationLink { LearnView() } label: { Label("Comprendre les technologies", systemImage: "book.closed") }
                    Link("Découvrir RNC Mobile", destination: URL(string: "https://www.rncmobile.net/")!)
                    Text("Leurs identifications communautaires peuvent aider à relier des identifiants radio aux sites Free Mobile. Pylo propose un lien ; il n’existe pas de partenariat confirmé ni d’import de leur base dans cette version.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Les antennes, à jour") {
                    Text("La carte utilise une copie locale des données ANFR. Elle fonctionne hors ligne ; le fond de carte et la recherche de lieux peuvent nécessiter internet.")
                    Button("Importer une mise à jour ANFR", systemImage: "square.and.arrow.down") { importing = true }
                    Text("Chaque mois, GitHub prépare le fichier antennas.sqlite. Télécharge-le depuis les publications privées du projet, puis ouvre-le ici avec Fichiers. Aucun identifiant GitHub n’est intégré dans l’app.").font(.footnote).foregroundStyle(.secondary)
                    if let url = store.databaseURL, let attrs = try? FileManager.default.attributesOfItem(atPath: url.path), let size = attrs[.size] as? Int {
                        LabeledContent("Base locale", value: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                    }
                    if let message = store.message { Text(message).foregroundStyle(.orange) }
                    Link("Source officielle · ANFR / data.gouv.fr", destination: URL(string: "https://www.data.gouv.fr/datasets/donnees-sur-les-reseaux-mobiles")!)
                    Text("Données ANFR, Licence Ouverte 2.0. Dates et états affichés tels que publiés par la source.").font(.caption)
                }
                Section("Tes données restent avec toi") {
                    Text("Les favoris restent sur cet appareil. La localisation et le cap servent à centrer la carte et à calculer les directions et distances ; Pylo ne les conserve pas et ne les envoie pas à un serveur Pylo. Apple Plans traite les recherches et itinéraires selon ses propres conditions.")
                    Text("Pylo n’est pas affiliée à Apple, à l’ANFR ou aux opérateurs.").font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("Le projet")
            .fileImporter(isPresented: $importing, allowedContentTypes: [.database, .data]) { result in
                switch result { case .success(let url): Task { await store.importDatabase(url) }; case .failure(let error): store.message = error.localizedDescription }
            }
        }
    }
}
