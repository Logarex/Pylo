import SwiftUI
struct FieldTestTerm: Identifiable {
    var id: String { name }
    let name: String
    let meaning: String
    let read: String
}
struct FieldTestView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var search = ""
    @State private var eci = ""
    private let terms: [FieldTestTerm] = [
        .init(name: "RAT / Radio Access Technology", meaning: "La technologie utilisée : GSM (2G), UMTS (3G), LTE (4G) ou NR (5G).", read: "C’est la première chose à regarder. En 5G NSA, des infos LTE s’affichent aussi."),
        .init(name: "Serving Cell / cellule servante", meaning: "La cellule à laquelle ton iPhone est connecté.", read: "À ne pas confondre avec Neighbor Cells, les cellules voisines."),
        .init(name: "RSRP / SS-RSRP / CSI-RSRP", meaning: "La puissance du signal reçu.", read: "En dBm. Plus c’est proche de 0, plus c’est fort : −80 est mieux que −105."),
        .init(name: "RSRQ / SS-RSRQ", meaning: "La qualité du signal reçu.", read: "En dB. Moins c’est négatif, mieux c’est. Utile quand le signal est fort mais que ça rame."),
        .init(name: "SINR / SNR / SS-SINR", meaning: "Le rapport entre le signal utile, le bruit et les interférences.", read: "Plus c’est haut, mieux c’est. Un SINR faible explique souvent une connexion lente malgré un bon RSRP."),
        .init(name: "RSSI", meaning: "Toute la puissance reçue, bruit compris.", read: "Utile en 2G. En 4G, regarde plutôt le RSRP et le SINR."),
        .init(name: "Noise / bruit / interférences", meaning: "Le bruit ambiant et les signaux des autres émetteurs.", read: "Rarement affiché à part. Le SINR montre leur effet."),
        .init(name: "RSCP / Ec/No / Ec/Io", meaning: "Les mesures de la 3G : puissance (RSCP) et qualité (Ec/No, Ec/Io).", read: "Elles ne se calculent pas comme en 4G, donc ne les compare pas au RSRP."),
        .init(name: "Band / freq_band_ind", meaning: "Le numéro de bande, par exemple B3 en 4G ou n78 en 5G.", read: "B28 = 700 MHz, B20 = 800 MHz, B3 = 1 800 MHz, n78 = 3,5 GHz."),
        .init(name: "EARFCN / NR-ARFCN / ARFCN / UARFCN", meaning: "Le numéro du canal radio.", read: "Il donne la fréquence exacte utilisée."),
        .init(name: "PCI / Physical Cell ID", meaning: "Un identifiant de cellule local, réutilisé un peu partout.", read: "Seul, il ne suffit pas pour retrouver une antenne."),
        .init(name: "Cell ID / ECI / NCI", meaning: "L’identifiant complet de la cellule : ECI en 4G, NCI en 5G.", read: "Regarde s’il est en décimal ou en hexadécimal. Le décodeur plus haut lit l’ECI."),
        .init(name: "eNB / eNodeB / gNB / RNC", meaning: "Le numéro de la station chez l’opérateur : eNodeB en 4G, gNodeB en 5G.", read: "Ce n’est pas le numéro ANFR. RNC Mobile peut aider à faire le lien."),
        .init(name: "MCC / MNC / PLMN", meaning: "Le pays (MCC) et l’opérateur (MNC). Les deux ensemble forment le PLMN.", read: "Pratique pour savoir sur quel réseau tu es vraiment, en itinérance par exemple."),
        .init(name: "TAC / LAC", meaning: "Une zone qui regroupe plusieurs cellules.", read: "Elle ne donne pas la position d’une antenne."),
        .init(name: "Bandwidth / largeur de canal", meaning: "La largeur du canal, en MHz.", read: "Plus il est large, plus il y a de capacité, à partager entre tous ceux qui sont connectés."),
        .init(name: "CA / PCC / SCC / agrégation", meaning: "Plusieurs bandes utilisées en même temps : c’est la 4G+.", read: "PCC est la bande principale, SCC les secondaires."),
        .init(name: "NSA / SA / EN-DC", meaning: "NSA : la 5G s’appuie sur la 4G. SA : la 5G fonctionne seule.", read: "EN-DC veut dire que tu es connecté en 4G et en 5G à la fois."),
        .init(name: "CQI / MCS / modulation / rank", meaning: "La qualité du canal et la modulation choisies par le réseau.", read: "Ça change tout le temps. Une modulation haute veut dire une bonne radio."),
        .init(name: "Timing Advance / TA", meaning: "Un décalage de temps lié à ta distance à l’antenne.", read: "Donne une idée de la distance, mais la conversion en mètres dépend de la technologie."),
        .init(name: "rx / tx / dl / ul / timestamp", meaning: "rx = réception, tx = émission, dl = descendant, ul = montant.", read: "Regarde le timestamp : certaines valeurs restent figées.")
    ]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    InfoCard("Par où commencer") {
                        Text("Regarde d’abord la technologie, puis la puissance et la qualité. Les identifiants servent à retrouver l’antenne.")
                    }
                    InfoCard("Ta connexion") {
                        networkInfo("Connexion internet", value: store.device.connection, icon: store.device.connectionIcon)
                        Divider()
                        networkInfo("Technologie cellulaire · 2G à 5G", value: store.device.radioStatus, icon: "simcard")
                        Text(store.device.radioExplanation).font(.footnote).foregroundStyle(.secondary)
                        ForEach(store.device.radioLines) { line in
                            LabeledContent(line.dataLine ? "\(line.name) · données mobiles" : line.name, value: line.technology)
                        }
                        DisclosureGroup("Détails de la connexion") {
                            LabeledContent("Accès cellulaire de Pylo", value: store.device.cellularAccess)
                            if let ipv4 = store.device.supportsIPv4 { LabeledContent("IPv4 disponible", value: ipv4 ? "Oui" : "Non") }
                            if let ipv6 = store.device.supportsIPv6 { LabeledContent("IPv6 disponible", value: ipv6 ? "Oui" : "Non") }
                            if let dns = store.device.supportsDNS { LabeledContent("DNS disponible", value: dns ? "Oui" : "Non") }
                            LabeledContent("Connexion marquée coûteuse", value: store.device.expensive ? "Oui, par iOS" : "Non signalée comme telle")
                        }
                        Divider()
                        networkInfo("Mode données réduites", value: store.device.reducedDataStatus, icon: "arrow.down.circle")
                        Button("Actualiser les informations", systemImage: "arrow.clockwise") { store.device.refresh() }
                        if let date = store.device.lastUpdated { Text("Dernière lecture : \(date.formatted(Date.FormatStyle(date: .omitted, time: .standard).locale(Locale(identifier: "fr_FR"))))").font(.caption).foregroundStyle(.secondary) }
                        Text("iOS ne laisse pas les apps lire la cellule utilisée ni la qualité du signal. Field Test, si.").font(.caption).foregroundStyle(.secondary)
                    }
                    InfoCard("Ta position et ton cap") {
                        LabeledContent("Localisation", value: store.location.permission)
                        if let precise = store.location.precisePosition { LabeledContent("Position précise", value: precise ? "Autorisée" : "Approximative") }
                        Button("Lire ma position et mon cap", systemImage: "location.north.circle") { store.location.locate() }
                        if let accuracy = store.location.accuracy { LabeledContent("Précision horizontale", value: "± \(Int(accuracy)) m") }
                        if let altitude = store.location.altitude { LabeledContent("Altitude estimée", value: "\(Int(altitude)) m") }
                        if let vertical = store.location.verticalAccuracy { LabeledContent("Précision verticale", value: "± \(Int(vertical)) m") }
                        if let speed = store.location.speed { LabeledContent("Vitesse au dernier relevé", value: speed.formatted(.number.precision(.fractionLength(1))) + " km/h") }
                        if let course = store.location.course { LabeledContent("Direction du déplacement", value: "\(Int(course))°") }
                        if let heading = store.location.heading { LabeledContent("Cap de l’iPhone", value: "\(Int(heading))° · \(store.location.headingReference)") }
                        if let accuracy = store.location.headingAccuracy { LabeledContent("Précision du cap", value: "± \(Int(accuracy))°") }
                        if let date = store.location.measuredAt { LabeledContent("Position relevée à", value: date.formatted(Date.FormatStyle(date: .omitted, time: .standard).locale(Locale(identifier: "fr_FR")))) }
                        if !store.location.status.isEmpty { Text(store.location.status).font(.footnote).foregroundStyle(.secondary) }
                    }
                    InfoCard("1 · Ouvrir Field Test") {
                        Text("Dans Téléphone → Clavier, saisis ce code puis appuie sur Appeler.")
                        HStack { Text(verbatim: "*3001#12345#*").font(.title3.monospaced()); Spacer(); Button("Copier") { UIPasteboard.general.string = "*3001#12345#*" } }
                        Text("Les menus changent selon l’iPhone et la version d’iOS.").font(.caption).foregroundStyle(.secondary)
                    }
                    InfoCard("2 · Lire la puissance et la qualité") {
                        Label("Puissance → RSRP", systemImage: "antenna.radiowaves.left.and.right").font(.headline)
                        Text("La puissance reçue, en dBm. Plus elle est proche de 0, plus le signal est fort.")
                        Label("Qualité → RSRQ et SINR", systemImage: "waveform").font(.headline)
                        Text("La qualité du signal. Un signal fort peut quand même être brouillé par les interférences.")
                        signalScale("RSRP · dBm", values: ["≥ −80 : fort", "−90 à −80 : bon", "−100 à −90 : moyen", "< −100 : faible"])
                        signalScale("SINR · dB", values: ["≥ 20 : favorable", "13 à 20 : bon", "0 à 13 : perturbé", "< 0 : difficile"])
                        Text("Repères indicatifs pour la 4G et la 5G, d’après Teltonika.").font(.caption).foregroundStyle(.secondary)
                        Link("Voir les repères de Teltonika", destination: URL(string: "https://wiki.teltonika-networks.com/view/Mobile_Signal_Strength_Recommendations")!).font(.caption)
                    }
                    InfoCard("3 · Retrouver l’antenne utilisée") {
                        step("1", "Repère ta cellule", "Dans Serving Cell Info, note le MCC/MNC, la bande et l’identifiant de cellule.")
                        step("2", "En 4G, trouve l’eNodeB", "Colle l’ECI ci-dessous pour obtenir le numéro d’eNodeB.")
                        step("3", "Cherche le site", "Pour Free Mobile, RNC Mobile recense beaucoup de sites. Compare ensuite avec la carte de Pylo.")
                        step("4", "Méfie-toi de la plus proche", "Ce n’est pas forcément celle à laquelle tu es connecté.")
                        TextField("ECI LTE en décimal ou 0x…", text: $eci).textFieldStyle(.roundedBorder).autocorrectionDisabled().textInputAutocapitalization(.never)
                        if let value = decodedECI {
                            LabeledContent("eNodeB", value: String(Radio.enodeB(value)))
                            LabeledContent("Cellule locale (8 bits)", value: String(Radio.sector(value)))
                        } else if !eci.isEmpty { Text("ECI invalide : il doit être entre 0 et 268 435 455 (pas un NCI 5G).").font(.caption).foregroundStyle(.orange) }
                        Link("Consulter RNC Mobile", destination: URL(string: "https://www.rncmobile.net/")!)
                    }
                    InfoCard("Le dictionnaire Field Test", subtitle: "Les champs les plus courants.") {
                        TextField("Chercher : PCI, bruit, LTE…", text: $search).textFieldStyle(.roundedBorder)
                        ForEach(terms.filter { search.isEmpty || ($0.name + $0.meaning + $0.read).localizedCaseInsensitiveContains(search) }) { term in
                            DisclosureGroup { VStack(alignment: .leading, spacing: 10) { Text(term.meaning).font(.subheadline); Text(term.read).font(.subheadline).foregroundStyle(.secondary) }.padding(.vertical,8) } label: { Text(term.name).font(.subheadline.bold()).foregroundStyle(.primary) }
                            Divider()
                        }
                    }
                    NavigationLink { LearnView() } label: { Label("Comprendre GSM, GPRS, EDGE, UMTS, LTE et NR", systemImage: "book") }.padding()
                }.padding(16)
            }.background(Color(.systemGroupedBackground)).navigationTitle("Field Test").navigationBarTitleDisplayMode(.inline)
                .task { store.device.refresh() }
                .onChange(of: scenePhase) { if scenePhase == .active { store.device.refresh() } }
        }
    }
    private func networkInfo(_ title: String, value: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(Palette.accent).frame(width: 24).padding(.top, 3)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.headline).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
    private var decodedECI: UInt32? {
        let clean = eci.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = clean.lowercased().hasPrefix("0x") ? UInt32(clean.dropFirst(2), radix: 16) : UInt32(clean)
        return value.flatMap { $0 <= 268435455 ? $0 : nil }
    }
    private func step(_ number: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 12) { Text(number).font(.headline).foregroundStyle(Palette.accent).frame(width: 28,height: 28).background(Palette.accent.opacity(0.1), in: Circle()); VStack(alignment: .leading, spacing: 5) { Text(title).font(.headline); Text(body).font(.subheadline).foregroundStyle(.secondary) } }
    }
    private func signalScale(_ name: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(name).font(.subheadline.bold()); ForEach(Array(values.enumerated()), id: \.offset) { index, value in HStack { Capsule().fill([Color.teal,.green,.orange,.red][index]).frame(width: 22,height: 6); Text(value).font(.caption) } } }.padding(14).frame(maxWidth: .infinity,alignment: .leading).background(Palette.accent.opacity(0.05), in: .rect(cornerRadius: 16))
    }
}
