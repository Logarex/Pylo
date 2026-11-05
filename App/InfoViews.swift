import SwiftUI
import UniformTypeIdentifiers
struct LearnView: View {
    private let entries: [(String,String,String)] = [
        ("2G · GSM", "Les appels et les SMS", "La 2G, c’est le GSM. Le G et le E affichés sur l’iPhone correspondent à GPRS et EDGE, ses versions pour les données."),
        ("3G · UMTS", "Le premier internet mobile rapide", "La 3G repose sur l’UMTS. H et H+ correspondent à HSPA et HSPA+, ses versions plus rapides. Les opérateurs l’arrêtent petit à petit."),
        ("4G · LTE", "Le réseau le plus utilisé", "La 4G, c’est le LTE. Quand plusieurs bandes sont utilisées en même temps, on parle de 4G+. VoLTE permet de téléphoner en 4G."),
        ("5G · NR", "New Radio", "La 5G en 700 MHz porte loin. Celle en 3,5 GHz va plus vite, mais sur une zone plus petite. Le logo 5G seul ne dit pas laquelle tu utilises."),
        ("NSA / SA", "Les deux modes de la 5G", "En NSA, la 5G s’appuie sur la 4G. En SA, elle fonctionne seule, et les appels peuvent passer en VoNR."),
        ("Fréquences", "Basses et hautes fréquences", "Les bandes basses (700, 800, 900 MHz) passent mieux les murs. Les bandes hautes offrent plus de capacité, mais portent moins loin."),
        ("RSRP", "La puissance reçue", "Plus c’est proche de 0, plus c’est fort : −80 dBm est mieux que −110 dBm."),
        ("RSRQ / SINR", "La qualité du signal", "Ils disent si le signal est propre ou noyé dans le bruit. Plus le SINR est élevé, mieux c’est."),
        ("ANFR", "Ce que montre la carte", "L’ANFR recense les antennes déclarées par les opérateurs. La carte montre où elles sont, pas jusqu’où elles portent.")]
    var body: some View {
        NavigationStack {
            List {
                Section { Text("Les bases pour lire la carte et Field Test.").foregroundStyle(.secondary) }
                ForEach(entries, id: \.0) { entry in Section(entry.0) { Text(entry.1).font(.headline); Text(entry.2) } }
            }.navigationTitle("Comprendre")
        }
    }
}
struct DataView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var addressCopied = false
    @State private var importing = false
    var body: some View {
        @Bindable var store = store
        NavigationStack {
            List {
                Section {
                    Image("Brand").resizable().scaledToFit().frame(width: 100, height: 100).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous)).frame(maxWidth: .infinity).accessibilityLabel("Logo Pylo")
                    Text("Pylo").font(.largeTitle.bold())
                    Text("Gratuite et open source").font(.headline)
                    Text("Je suis étudiant et je voulais comprendre les antennes autour de moi. J’ai fait Pylo pour ça, sans pub et sans compte.")
                }
                Section("Une question, une idée ou un bug ?") {
                    Link(destination: URL(string: "https://github.com/Logarex/Pylo/issues/new/choose")!) { Label("Ouvrir une issue sur GitHub", systemImage: "bubble.left.and.bubble.right") }
                    Button {
                        openURL(URL(string: "mailto:pylo@nephoos.com")!) { accepted in
                            if !accepted { UIPasteboard.general.string = "pylo@nephoos.com"; addressCopied = true }
                        }
                    } label: { Label("Écrire à pylo@nephoos.com", systemImage: "envelope") }
                    Button("Copier l’adresse mail", systemImage: "doc.on.doc") { UIPasteboard.general.string = "pylo@nephoos.com"; addressCopied = true }
                    Text("Tous les retours sont bienvenus.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Ressources") {
                    NavigationLink { LearnView() } label: { Label("Comprendre les technologies", systemImage: "book.closed") }
                    Link("Découvrir RNC Mobile", destination: URL(string: "https://www.rncmobile.net/")!)
                    Text("Un site communautaire qui relie les identifiants radio aux antennes Free Mobile.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Données ANFR") {
                    Text("Pylo télécharge les nouvelles données de l’ANFR en Wi-Fi.")
                    Toggle("Mises à jour automatiques en Wi-Fi", isOn: $store.automaticUpdates)
                    if !store.dataSourceDate.isEmpty { LabeledContent("Données ANFR du", value: formattedDate(store.dataSourceDate)) }
                    if let date = store.lastDataCheck { LabeledContent("Dernière vérification", value: date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(Locale(identifier: "fr_FR")))) }
                    HStack(alignment: .top) {
                        if store.isUpdating { ProgressView() }
                        Text(store.updateStatus).font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("Vérifier maintenant", systemImage: "arrow.triangle.2.circlepath") { Task { await store.checkDataUpdates() } }.disabled(store.isUpdating)
                    DisclosureGroup("Import manuel · dépannage") {
                        Button("Importer un fichier ANFR préparé pour Pylo", systemImage: "square.and.arrow.down") { importing = true }.disabled(store.isUpdating)
                        Text("Pour tester une base locale.").font(.caption)
                    }
                    Link("Source officielle · ANFR / data.gouv.fr", destination: URL(string: "https://www.data.gouv.fr/datasets/donnees-sur-les-reseaux-mobiles")!)
                    Text("Données ANFR, Licence Ouverte 2.0. Consultables hors ligne.").font(.caption)
                }
                Section {
                    NavigationLink { AlertsView() } label: { Label("Notifications", systemImage: "bell.badge") }
                } footer: {
                    Text("Nouvelles données ANFR, nouvelles antennes ou changements autour des lieux que tu choisis, changements sur tes favoris.")
                }
                Section("Vie privée") {
                    Text("Tes favoris, ta position et tes zones d’alerte restent sur ton iPhone. Les recherches et itinéraires passent par Apple Plans.")
                    if PushService.isAvailable && (store.alertData || store.alertFavorites || store.alertZones.contains(where: \.isActive)) {
                        Text("Pour les notifications instantanées, ton iPhone s’abonne à deux canaux communs à tous les utilisateurs, via Firebase Cloud Messaging (Google). Firebase reçoit un identifiant technique de notification, rien d’autre : ni position, ni zone, ni favori.").font(.footnote)
                    }
                    Text("Pylo n’est liée ni à Apple, ni à l’ANFR, ni aux opérateurs.").font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("Le projet")
            .alert("Adresse copiée", isPresented: $addressCopied) { Button("OK", role: .cancel) {} } message: { Text("pylo@nephoos.com est dans le presse-papiers.") }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.database, .data]) { result in
                switch result { case .success(let url): Task { await store.importDatabase(url) }; case .failure(let error): store.message = error.localizedDescription }
            }
        }
    }
}
