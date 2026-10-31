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
        .init(name: "RAT / Radio Access Technology", meaning: "La famille radio utilisée : GSM (2G), WCDMA/UMTS (3G), LTE (4G) ou NR (5G).", read: "C’est le premier repère à regarder. En 5G NSA, l’iPhone peut aussi afficher des informations LTE pour la connexion d’appui."),
        .init(name: "Serving Cell / cellule servante", meaning: "La cellule avec laquelle le téléphone échange à cet instant.", read: "Cherche Serving Cell Info, LTE, NR ou RAT selon ta version d’iOS. Ne la confonds pas avec Neighbor Cells : ce sont les cellules voisines, pas forcément utilisées."),
        .init(name: "RSRP / SS-RSRP / CSI-RSRP", meaning: "La puissance d’un signal de référence reçu. SS et CSI désignent des références différentes en 5G.", read: "En dBm, moins négatif = plus fort. −80 est plus fort que −105. Compare le même type de mesure ; RSRP fort ne veut pas dire débit élevé."),
        .init(name: "RSRQ / SS-RSRQ", meaning: "Un indicateur de qualité du signal de référence par rapport à la puissance reçue sur le canal.", read: "En dB, une valeur moins négative est généralement meilleure. Il aide à repérer une réception dégradée même quand la puissance semble bonne."),
        .init(name: "SINR / SNR / SS-SINR", meaning: "Le rapport du signal utile au bruit et, pour SINR, aux interférences.", read: "Plus élevé = signal plus facile à distinguer. Un SINR faible peut expliquer une mauvaise connexion malgré un RSRP fort. SNR et SINR ne sont pas strictement la même mesure."),
        .init(name: "RSSI", meaning: "La puissance totale reçue dans la bande mesurée : signal utile, autres signaux et bruit.", read: "En 2G, c’est un repère de puissance fréquent. En LTE, ne le lis pas seul : un RSSI élevé peut aussi venir d’interférences."),
        .init(name: "Noise / bruit / interférences", meaning: "Le bruit vient notamment des équipements et du milieu ; les interférences viennent d’autres émissions.", read: "Field Test ne donne pas toujours une valeur de bruit séparée. Le SINR décrit leur effet relatif sur le signal utile. On ne peut pas déduire leur puissance exacte avec la seule distance."),
        .init(name: "RSCP / Ec/No / Ec/Io", meaning: "Des indicateurs courants de la 3G : puissance d’un code reçu pour RSCP, et rapport de qualité pour Ec/No ou Ec/Io.", read: "RSCP est en dBm ; Ec/No ou Ec/Io en dB. Ne les compare pas directement aux valeurs RSRP/RSRQ de la 4G : la définition change."),
        .init(name: "Band / freq_band_ind", meaning: "Le numéro normalisé de la bande, par exemple B3 en LTE ou n78 en 5G.", read: "B3 correspond à la bande 1 800 MHz ; B20 à 800 MHz ; B28 à 700 MHz ; n78 à 3,5 GHz environ. Le numéro de bande n’est pas la fréquence en MHz."),
        .init(name: "EARFCN / NR-ARFCN / ARFCN / UARFCN", meaning: "Le numéro du canal radio : respectivement LTE, NR, GSM et UMTS.", read: "Il sert à retrouver la fréquence avec les tables de la technologie concernée. Ce n’est ni un numéro de station ni un identifiant unique d’antenne."),
        .init(name: "PCI / Physical Cell ID", meaning: "Un identifiant physique local en LTE et NR. En 3G, on peut voir un PSC ; en GSM, un BSIC.", read: "Le PCI est réutilisé à beaucoup d’endroits. Un PCI seul ne permet donc pas d’identifier une antenne. Il faut au moins le réseau, le canal et le contexte géographique."),
        .init(name: "Cell ID / ECI / NCI", meaning: "L’identifiant de cellule. ECI désigne l’identité LTE (28 bits), NCI celle de la 5G NR (36 bits).", read: "Regarde si la valeur est décimale ou hexadécimale. En LTE, on peut séparer eNodeB et identifiant local sur 8 bits. En NR, la taille de l’identifiant gNodeB varie : pas de division universelle par 256."),
        .init(name: "eNB / eNodeB / gNB / RNC", meaning: "eNodeB : station logique LTE. gNodeB : station logique NR. RNC : contrôleur réseau en 3G.", read: "Ces identifiants réseau ne sont pas les identifiants ANFR. Une base communautaire de correspondance peut aider, si elle couvre le réseau et la zone."),
        .init(name: "MCC / MNC / PLMN", meaning: "Les codes du réseau : MCC pour le pays, MNC pour le réseau mobile. Ensemble, ils forment le PLMN.", read: "Ils aident à distinguer le réseau réellement utilisé, notamment en itinérance. Le nom commercial affiché ne remplace pas ces codes."),
        .init(name: "TAC / LAC", meaning: "Une zone de suivi (4G/5G) ou une zone de localisation (2G/3G).", read: "Ce sont des regroupements de cellules. Ils ne donnent ni ton adresse ni la position exacte d’une antenne."),
        .init(name: "Bandwidth / largeur de canal", meaning: "La largeur de spectre utilisée par une porteuse, en MHz.", read: "Une largeur plus grande peut offrir davantage de capacité, mais les utilisateurs connectés et la qualité radio comptent aussi. Ce n’est pas le débit réel."),
        .init(name: "CA / PCC / SCC / agrégation", meaning: "CA regroupe plusieurs porteuses. PCC est la principale, SCC une secondaire.", read: "Voir plusieurs bandes peut correspondre à la 4G+. Les porteuses actives changent selon le trafic et le réseau : une liste au repos ne raconte pas tout."),
        .init(name: "NSA / SA / EN-DC", meaning: "NSA : NR avec appui LTE. SA : NR avec cœur 5G. EN-DC désigne une double connectivité LTE/NR.", read: "Le logo 5G ne prouve pas à lui seul une connexion SA. Lis les indications de mode lorsqu’elles sont disponibles dans Field Test."),
        .init(name: "CQI / MCS / modulation / rank", meaning: "Des indications sur la qualité de canal, le codage, la modulation et les couches radio utilisées.", read: "Elles évoluent rapidement et sont adaptées par le réseau. Une modulation plus élevée demande généralement une meilleure qualité radio ; ce n’est pas un test de débit."),
        .init(name: "Timing Advance / TA", meaning: "Un ajustement temporel pour que les émissions du téléphone arrivent au bon moment.", read: "Il peut donner un indice de distance selon la technologie et l’unité. Sans ces détails, le convertir directement en mètres serait trompeur."),
        .init(name: "rx / tx / dl / ul / timestamp", meaning: "rx = réception, tx = émission, dl = descendant, ul = montant. Timestamp indique l’heure d’une mesure.", read: "Vérifie que la valeur est récente et son unité. Certains champs peuvent rester figés, manquer ou changer de nom selon le modem et iOS.")
    ]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    InfoCard("Ton réseau, en clair.", subtitle: "Un guide à garder à côté de Field Test.") {
                        Text("Pas besoin de noter toutes les valeurs. Commence par la technologie, puis la puissance et la qualité. Les identifiants servent ensuite à chercher la station.")
                    }
                    InfoCard("Ce que peut lire Pylo", subtitle: "L’accès internet et la radio cellulaire sont deux informations différentes.") {
                        networkInfo("Connexion internet", value: store.device.connection, icon: store.device.connectionIcon)
                        Divider()
                        networkInfo("Technologie cellulaire · 2G à 5G", value: store.device.radioStatus, icon: "simcard")
                        Text(store.device.radioExplanation).font(.footnote).foregroundStyle(.secondary)
                        ForEach(store.device.radioLines) { line in
                            LabeledContent(line.dataLine ? "\(line.name) · données mobiles" : line.name, value: line.technology)
                        }
                        DisclosureGroup("Détails de la connexion") {
                            LabeledContent("Accès cellulaire de Pylo", value: store.device.cellularAccess)
                            Text("Cet état décrit une restriction d’accès pour l’app, pas une garantie de couverture mobile.").font(.caption).foregroundStyle(.secondary)
                            if let ipv4 = store.device.supportsIPv4 { LabeledContent("IPv4 disponible", value: ipv4 ? "Oui" : "Non") }
                            if let ipv6 = store.device.supportsIPv6 { LabeledContent("IPv6 disponible", value: ipv6 ? "Oui" : "Non") }
                            if let dns = store.device.supportsDNS { LabeledContent("DNS disponible", value: dns ? "Oui" : "Non") }
                            LabeledContent("Connexion marquée coûteuse", value: store.device.expensive ? "Oui, par iOS" : "Non signalée comme telle")
                            Text("IPv4, IPv6 et DNS décrivent le chemin réseau fourni par iOS, sans test de serveur ni mesure du débit. « Coûteuse » est une indication du système, pas le tarif de ton forfait.").font(.caption).foregroundStyle(.secondary)
                        }
                        Divider()
                        networkInfo("Mode données réduites", value: store.device.reducedDataStatus, icon: "arrow.down.circle")
                        Text("Cet état concerne la connexion internet actuelle, Wi-Fi ou mobile. Il ne mesure pas la qualité du signal.").font(.footnote).foregroundStyle(.secondary)
                        Button("Actualiser les informations", systemImage: "arrow.clockwise") { store.device.refresh() }
                        if let date = store.device.lastUpdated { Text("Dernière lecture : \(date.formatted(date: .omitted, time: .standard))").font(.caption).foregroundStyle(.secondary) }
                        Text("iOS ne donne pas à Pylo le numéro de téléphone, l’IMEI, la cellule utilisée, les bandes actives ni les mesures RSRP/RSRQ/SINR. Le guide ci-dessous explique comment lire ces mesures dans Field Test.").font(.caption).foregroundStyle(.secondary)
                    }
                    InfoCard("Ta position et ton cap", subtitle: "Uniquement à ta demande, sans historique de déplacement.") {
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
                        if let date = store.location.measuredAt { LabeledContent("Position relevée à", value: date.formatted(date: .omitted, time: .standard)) }
                        if !store.location.status.isEmpty { Text(store.location.status).font(.footnote).foregroundStyle(.secondary) }
                        Text("L’altitude de l’iPhone n’est pas la hauteur d’un support ANFR. Le cap du téléphone et la direction du déplacement sont aussi deux choses différentes. Les valeurs incertaines ou indisponibles ne sont pas inventées.").font(.caption).foregroundStyle(.secondary)
                    }
                    InfoCard("1 · Ouvrir Field Test") {
                        Text("Dans Téléphone → Clavier, saisis ce code puis appuie sur Appeler.")
                        HStack { Text(verbatim: "*3001#12345#*").font(.title3.monospaced()); Spacer(); Button("Copier") { UIPasteboard.general.string = "*3001#12345#*" } }
                        Text("Les menus varient selon l’iPhone, le modem, iOS et l’opérateur. Certaines rubriques peuvent manquer ; Pylo ne peut pas ouvrir directement ce menu à ta place.").font(.caption).foregroundStyle(.secondary)
                    }
                    InfoCard("2 · Lire la puissance et la qualité") {
                        Label("Puissance → RSRP", systemImage: "antenna.radiowaves.left.and.right").font(.headline)
                        Text("Pense au volume d’une voix : plus le signal est fort, plus il est facile à entendre.")
                        Label("Qualité → RSRQ et SINR", systemImage: "waveform").font(.headline)
                        Text("Pense à une conversation dans une salle bruyante : une voix forte peut rester difficile à comprendre si les autres parlent en même temps.")
                        signalScale("RSRP · dBm", values: ["≥ −80 : fort", "−90 à −80 : bon", "−100 à −90 : moyen", "< −100 : faible"])
                        signalScale("SINR · dB", values: ["≥ 20 : favorable", "13 à 20 : bon", "0 à 13 : perturbé", "< 0 : difficile"])
                        Text("Repères indicatifs LTE/NR, inspirés des recommandations Teltonika pour leurs modems ; pas des seuils Apple ni une garantie de débit. Lis toujours aussi le RSRQ, le contexte et le type exact de mesure.").font(.caption).foregroundStyle(.secondary)
                        Link("Lire les repères de mesure", destination: URL(string: "https://wiki.teltonika-networks.com/view/Mobile_Signal_Strength_Recommendations")!).font(.caption)
                    }
                    InfoCard("3 · Retrouver l’antenne utilisée") {
                        step("1", "Repère la cellule servante", "Dans Serving Cell Info, relève le réseau (MCC/MNC), la technologie, la bande ou le canal, et l’identifiant complet de cellule. Le PCI seul ne suffit pas.")
                        step("2", "Pour la 4G, retrouve l’eNodeB", "Si Field Test donne un ECI LTE, le calcul ci-dessous sépare l’eNodeB de l’identifiant local de cellule. Ce n’est pas l’identifiant ANFR.")
                        step("3", "Cherche une correspondance documentée", "Pour Free Mobile, RNC Mobile peut aider avec ses identifications communautaires. Vérifie la technologie, les identifiants et la zone, puis compare la position et les bandes dans Pylo.")
                        step("4", "Garde un doute si les données manquent", "La station la plus proche n’est pas forcément la bonne. Sans correspondance vérifiée, Pylo ne peut pas confirmer la station connectée. Les rôles des cellules LTE et NR peuvent aussi différer en NSA.")
                        TextField("ECI LTE en décimal ou 0x…", text: $eci).textFieldStyle(.roundedBorder).autocorrectionDisabled().textInputAutocapitalization(.never)
                        if let value = decodedECI {
                            LabeledContent("eNodeB", value: String(Radio.enodeB(value)))
                            LabeledContent("Cellule locale (8 bits)", value: String(Radio.sector(value)))
                            Text("La valeur locale ne désigne pas universellement un panneau ou une direction.").font(.caption).foregroundStyle(.secondary)
                        } else if !eci.isEmpty { Text("Il faut un ECI LTE valide entre 0 et 268 435 455. Ne colle pas un NCI 5G ici.").font(.caption).foregroundStyle(.orange) }
                        Link("Consulter RNC Mobile", destination: URL(string: "https://www.rncmobile.net/")!)
                        Text("Lien vers un projet indépendant. Aucun partenariat ni accès à leur base n’est annoncé à ce stade.").font(.caption).foregroundStyle(.secondary)
                    }
                    InfoCard("Le dictionnaire Field Test", subtitle: "Les champs courants, traduits simplement. Les noms exacts peuvent varier.") {
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
