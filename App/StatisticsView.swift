import SwiftUI
import Charts
private struct StatisticsRequest: Hashable { let operatorName: String; let databaseRevision: Int }
struct StatisticsView: View {
    @Environment(AppStore.self) private var store
    @State private var stats: NetworkStatistics?
    @State private var selectedOperator = ""
    @State private var operators: [String] = []
    @State private var error: String?
    @State private var firstOperator = ""
    @State private var secondOperator = ""
    @State private var comparison: [NetworkStatistics] = []
    @State private var comparisonError: String?
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
                            Chart(stats.frequencies) { item in
                                BarMark(x: .value("Systèmes",item.count), y: .value("MHz",item.label)).foregroundStyle(Palette.accent.gradient).cornerRadius(4)
                                    .annotation(position: .trailing) { Text(item.count.formatted()).font(.caption2.monospacedDigit()).foregroundStyle(.primary) }
                            }.chartXScale(domain: 0...max(1, Double(stats.frequencies.map(\.count).max() ?? 1) * 1.3))
                                .chartXAxis { AxisMarks { _ in AxisValueLabel() } }
                                .chartYAxis { AxisMarks { _ in AxisValueLabel() } }
                                .frame(height: max(220,Double(stats.frequencies.count)*36))
                            Text("Une même station peut compter plusieurs bandes et plusieurs générations dans une même bande.").font(.caption).foregroundStyle(.secondary)
                        }
                        InfoCard("Les dates déclarées", subtitle: "Systèmes dont la date ANFR se situe dans les 12 derniers mois de la source") {
                            if stats.deployments.isEmpty { Text("Aucune date renseignée dans cette période.") }
                            else { Chart(stats.deployments) { item in BarMark(x: .value("Mois",item.label), y: .value("Systèmes",item.count)).foregroundStyle(.teal.gradient).cornerRadius(3) }.chartXAxis {
                                AxisMarks(values: stats.deployments.enumerated().filter { $0.offset % 3 == 0 || $0.offset == stats.deployments.count - 1 }.map { $0.element.label }) { value in
                                    AxisValueLabel { if let month = value.as(String.self) { Text(monthLabel(month)).font(.caption2) } }
                                }
                            }.frame(height: 240) }
                            Text("Ces dates décrivent les systèmes dans la copie actuelle. Elles ne mesurent pas les ajouts au catalogue ni les mises en service certaines : le sens dépend de l’état déclaré.").font(.caption).foregroundStyle(.secondary)
                        }
                        comparisonCard
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
                .task(id: StatisticsRequest(operatorName: selectedOperator, databaseRevision: store.databaseRevision)) { await load() }
                .refreshable { await load() }
                .task(id: "\(firstOperator)|\(secondOperator)|\(store.databaseRevision)") { await loadComparison() }
        }
    }
    private func monthLabel(_ value: String) -> String {
        let parts = value.split(separator: "-")
        guard parts.count == 2 else { return value }
        return "\(parts[1])/\(parts[0].suffix(2))"
    }
    private var comparisonCard: some View {
        InfoCard("Comparer deux opérateurs", subtitle: "Même source ANFR, mêmes critères de comptage") {
            Picker("Premier opérateur", selection: $firstOperator) {
                Text("Choisir").tag("")
                ForEach(operators, id: \.self) { Text(operatorDisplayName($0)).tag($0) }
            }
            Picker("Second opérateur", selection: $secondOperator) {
                Text("Choisir").tag("")
                ForEach(operators.filter { $0 != firstOperator }, id: \.self) { Text(operatorDisplayName($0)).tag($0) }
            }
            if firstOperator == secondOperator && !firstOperator.isEmpty { Text("Choisis deux opérateurs différents.").font(.caption) }
            else if comparison.count == 2 {
                ForEach(Array(comparison.enumerated()), id: \.offset) { index, value in
                    let name = index == 0 ? firstOperator : secondOperator
                    VStack(alignment: .leading, spacing: 6) {
                        Label(operatorDisplayName(name), systemImage: "circle.fill").foregroundStyle(Palette.operatorColor(name)).font(.headline)
                        LabeledContent("Stations", value: value.stationCount.formatted())
                        LabeledContent("Supports", value: value.supportCount.formatted())
                        LabeledContent("Systèmes / bandes", value: value.systemCount.formatted())
                    }.padding(.vertical, 5)
                }
                Chart {
                    ForEach(Array(comparison.enumerated()), id: \.offset) { index, value in
                        let name = index == 0 ? firstOperator : secondOperator
                        ForEach(value.generations) { item in
                            BarMark(x: .value("Génération", item.label), y: .value("Stations", item.count))
                                .position(by: .value("Opérateur", operatorDisplayName(name)))
                                .foregroundStyle(by: .value("Opérateur", operatorDisplayName(name)))
                        }
                    }
                }.chartForegroundStyleScale(domain: [operatorDisplayName(firstOperator), operatorDisplayName(secondOperator)], range: [Palette.operatorColor(firstOperator), Palette.operatorColor(secondOperator)]).frame(height: 240)
                Text("Stations par génération. Ces volumes ne mesurent ni la couverture ni la qualité du réseau.").font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Comparer les bandes · systèmes déclarés") {
                    ForEach(Array(Set(comparison.flatMap { $0.frequencies.map(\.label) })).sorted { (Double($0) ?? 0) < (Double($1) ?? 0) }, id: \.self) { band in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(band + " MHz").font(.subheadline.bold())
                            ForEach(0..<2) { index in
                                LabeledContent(operatorDisplayName(index == 0 ? firstOperator : secondOperator), value: (comparison[index].frequencies.first { $0.label == band }?.count ?? 0).formatted()).font(.caption)
                            }
                        }.padding(.vertical, 4)
                    }
                }
            } else if let comparisonError { Text(comparisonError).font(.caption) }
            else if !firstOperator.isEmpty && !secondOperator.isEmpty { ProgressView("Comparaison…") }
        }
    }
    private func loadComparison() async {
        comparison = []; comparisonError = nil
        let a = firstOperator, b = secondOperator
        guard !a.isEmpty, !b.isEmpty, a != b, let url = store.databaseURL else { return }
        do {
            let result = try await Task.detached {
                let db = try AntennaDatabase(url: url)
                return try [db.statistics(operatorName: a), db.statistics(operatorName: b)]
            }.value
            guard !Task.isCancelled, a == firstOperator, b == secondOperator else { return }
            comparison = result
        } catch { if !Task.isCancelled { comparisonError = "La comparaison n’a pas pu être chargée." } }
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
            guard selectedOperator == op, !Task.isCancelled else { return }
            stats = value; error = nil
            if op.isEmpty {
                operators = value.operators.map(\.label)
                if firstOperator.isEmpty { firstOperator = operators.first ?? "" }
                if secondOperator.isEmpty { secondOperator = operators.dropFirst().first ?? "" }
            }
        } catch { if !Task.isCancelled { self.error = error.localizedDescription; stats = nil } }
    }
}
