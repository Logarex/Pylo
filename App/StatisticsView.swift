import SwiftUI
import Charts
struct StatisticsView: View {
    @Environment(AppStore.self) private var store
    @State private var stats: NetworkStatistics?
    @State private var selectedOperator = ""
    @State private var operators: [String] = []
    @State private var error: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Le réseau en chiffres.").font(.largeTitle.bold())
                        Text("Toute la base ANFR, France et outre-mer. Ces chiffres ne dépendent pas du zoom de la carte.").foregroundStyle(.secondary)
                        Picker("Opérateur", selection: $selectedOperator) { Text("Tous les opérateurs").tag(""); ForEach(operators, id: \.self) { Text(operatorDisplayName($0)).tag($0) } }.pickerStyle(.menu)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical,8)
                    if let stats {
                        LazyVGrid(columns: [GridItem(.flexible()),GridItem(.flexible())], spacing: 12) {
                            metric(stats.stationCount, "Stations opérateur", "antenna.radiowaves.left.and.right")
                            metric(stats.supportCount, "Supports distincts", "building.2")
                            metric(stats.systemCount, "Systèmes / bandes", "waveform")
                            metric(stats.operators.count, "Opérateurs", "person.2")
                        }
                        InfoCard("Qui est présent ?", subtitle: "Répartition des stations par opérateur") {
                            Chart(operatorSlices(stats.operators)) { item in SectorMark(angle: .value("Stations",item.count), innerRadius: .ratio(0.62), angularInset: 2).foregroundStyle(by: .value("Opérateur", operatorDisplayName(item.label))) }
                                .chartForegroundStyleScale(domain: operatorSlices(stats.operators).map { operatorDisplayName($0.label) }, range: operatorSlices(stats.operators).map { Palette.operatorColor($0.label) }).frame(height: 240)
                                .accessibilityLabel("Répartition des stations par opérateur")
                            ForEach(stats.operators) { item in HStack { Circle().fill(Palette.operatorColor(item.label)).frame(width:8,height:8); Text(operatorDisplayName(item.label)).font(.caption); Spacer(); Text(item.count.formatted()).font(.caption.monospacedDigit()) } }
                        }
                        InfoCard("De la 2G à la 5G", subtitle: "Nombre de stations avec au moins un système de cette génération") {
                            Chart(stats.generations) { item in BarMark(x: .value("Génération",item.label), y: .value("Stations",item.count)).foregroundStyle(Palette.generation(item.label)).cornerRadius(5).annotation(position: .top) { Text(item.count.formatted()).font(.caption2) } }.frame(height: 230)
                            Text("Une station peut apparaître dans plusieurs générations. Les colonnes ne s’additionnent donc pas au total des stations.").font(.caption).foregroundStyle(.secondary)
                        }
                        InfoCard("Les bandes de fréquence", subtitle: "Nombre de couples station–système, par bande en MHz") {
                            Chart(stats.frequencies) { item in BarMark(x: .value("Systèmes",item.count), y: .value("MHz",item.label)).foregroundStyle(Palette.accent.gradient).cornerRadius(4) }.frame(height: max(220,Double(stats.frequencies.count)*32))
                            Text("Une même station peut compter plusieurs bandes et plusieurs générations dans une même bande.").font(.caption).foregroundStyle(.secondary)
                        }
                        InfoCard("Les dates déclarées", subtitle: "Systèmes dont la date ANFR se situe dans les 12 derniers mois de la source") {
                            if stats.deployments.isEmpty { Text("Aucune date renseignée dans cette période.") }
                            else { Chart(stats.deployments) { item in BarMark(x: .value("Mois",item.label), y: .value("Systèmes",item.count)).foregroundStyle(.teal.gradient).cornerRadius(3) }.chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }.frame(height: 220) }
                            Text("Ces dates décrivent les systèmes dans la copie actuelle. Elles ne mesurent pas les ajouts au catalogue ni les mises en service certaines : le sens dépend de l’état déclaré.").font(.caption).foregroundStyle(.secondary)
                        }
                        InfoCard("Ce qui a changé") {
                            if let added = stats.additions, let removed = stats.removals, let previous = stats.previousDate {
                                Label("\(added.formatted()) stations apparues", systemImage: "plus.circle.fill").foregroundStyle(.teal)
                                Label("\(removed.formatted()) stations absentes", systemImage: "minus.circle").foregroundStyle(.orange)
                                Text("Comparaison de la copie du \(formattedDate(previous)) avec celle du \(formattedDate(stats.sourceDate)). Une apparition n’est pas forcément une nouvelle antenne physique.").font(.caption)
                            } else {
                                Text(selectedOperator.isEmpty ? "La première copie enrichie sert de point de départ. Le prochain import comparera les identifiants avec cette copie pour compter les apparitions et les retraits." : "La comparaison entre publications est disponible dans la vue Tous les opérateurs.")
                                Text("Pas de chiffre inventé pour les « ajouts du dernier mois ». Une date de publication seule ne suffit pas à les compter.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        InfoCard("Comment lire ces chiffres ?") {
                            Text("Support : le pylône, le toit ou la structure. Station : les équipements d’un opérateur, parfois rattachés à plusieurs supports. Système : une technologie et une bande sur une station. Le nombre de panneaux physiques n’est pas disponible dans cet observatoire.")
                            Text("Source ANFR · \(formattedDate(stats.sourceDate)) · Licence Ouverte 2.0").font(.caption).foregroundStyle(.secondary)
                        }
                    } else if let error { ContentUnavailableView("Statistiques indisponibles", systemImage: "chart.bar", description: Text(error)) }
                    else { ProgressView("Lecture de la base complète…").padding(40) }
                }.padding(16)
            }.background(Color(.systemGroupedBackground)).navigationTitle("Statistiques").navigationBarTitleDisplayMode(.inline)
                .task(id: selectedOperator) { await load() }
                .refreshable { await load() }
        }
    }
    private func metric(_ value: Int, _ title: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) { Image(systemName: icon).foregroundStyle(Palette.accent); Text(value.formatted()).font(.title2.bold()).minimumScaleFactor(0.7).lineLimit(1); Text(title).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
    }
    private func operatorSlices(_ values: [StatItem]) -> [StatItem] {
        let main = Array(values.prefix(4)); let others = values.dropFirst(4).reduce(0) { $0 + $1.count }
        return others > 0 ? main + [StatItem(label: "Autres", count: others)] : main
    }
    private func load() async {
        guard let url = store.databaseURL else { error = "Importe une base ANFR."; return }
        let op = selectedOperator
        do {
            let value = try await Task.detached { try AntennaDatabase(url: url).statistics(operatorName: op) }.value
            guard selectedOperator == op else { return }
            stats = value; error = nil
            if op.isEmpty { operators = value.operators.map(\.label) }
        } catch { self.error = error.localizedDescription; stats = nil }
    }
}
