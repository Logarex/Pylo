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
                LazyVStack(spacing: 16) {
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
                            Chart(stats.generations) { item in BarMark(x: .value("Génération",item.label), y: .value("Stations",item.count)).foregroundStyle(Palette.generation(item.label)).cornerRadius(5).annotation(position: .top) { Text(item.count.formatted()).font(.caption2) } }
                                .chartYScale(domain: 0...max(1, Double(stats.generations.map(\.count).max() ?? 1) * 1.2))
                                .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) }
                                .frame(height: 250)
                            Text("Une station peut apparaître dans plusieurs générations. Les colonnes ne s’additionnent donc pas au total des stations.").font(.caption).foregroundStyle(.secondary)
                        }
                        InfoCard("Les bandes de fréquence", subtitle: "Nombre de couples station–système, par bande en MHz") {
                            FrequencyBars(items: stats.frequencies, color: Palette.accent)
                            Text("Une même station peut compter plusieurs bandes et plusieurs générations dans une même bande.").font(.caption).foregroundStyle(.secondary)
                        }
                        InfoCard("Les dates des équipements", subtitle: "À quelles périodes correspondent les équipements présents dans la base ?") {
                            Text("Chaque barre compte les systèmes dont la date ANFR tombe dans ce mois. Un système, c’est une technologie sur une fréquence : LTE 700 et LTE 1800 comptent pour deux.").font(.subheadline)
                            if stats.deployments.isEmpty { Text("Aucune date renseignée dans cette période.") }
                            else { DeploymentChart(items: stats.deployments) }
                            Text("Ce graphique donne un aperçu des dates des équipements recensés aujourd’hui. Pour connaître les stations apparues depuis la dernière publication, regarde « Ce qui a changé ». Pour la mise en service d’une station, ouvre sa fiche.").font(.caption).foregroundStyle(.secondary)
                        }
                        comparisonCard
                        InfoCard("Ce qui a changé") {
                            if let added = stats.additions, let removed = stats.removals, let previous = stats.previousDate {
                                Label("\(added.formatted()) stations apparues", systemImage: "plus.circle.fill").foregroundStyle(.teal)
                                Label("\(removed.formatted()) stations absentes", systemImage: "minus.circle").foregroundStyle(.orange)
                                Text("Comparaison de la copie du \(formattedDate(previous)) avec celle du \(formattedDate(stats.sourceDate)). Une apparition n’est pas forcément une nouvelle antenne physique.").font(.caption)
                            } else {
                                Text(selectedOperator.isEmpty ? "La première copie enrichie sert de point de départ. Le prochain import comparera les identifiants avec cette copie pour compter les apparitions et les retraits." : "La comparaison entre publications est disponible dans la vue Tous les opérateurs.")

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
        }
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
        .task(id: "\(firstOperator)|\(secondOperator)|\(store.databaseRevision)") { await loadComparison() }
        .onChange(of: firstOperator) {
            if firstOperator == secondOperator { secondOperator = operators.first { $0 != firstOperator } ?? "" }
        }
    }
    private func loadComparison() async {
        comparison = []; comparisonError = nil
        let a = firstOperator, b = secondOperator
        guard !a.isEmpty, !b.isEmpty, a != b, store.databaseURL != nil else { return }
        do {
            let revision = store.databaseRevision
            let result = try await [store.networkStatistics(operatorName: a), store.networkStatistics(operatorName: b)]
            guard revision == store.databaseRevision else { return }
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
        guard store.databaseURL != nil else { error = "Importe une base ANFR."; return }
        let op = selectedOperator
        let revision = store.databaseRevision
        stats = nil; error = nil
        do {
            let value = try await store.networkStatistics(operatorName: op)
            guard selectedOperator == op, revision == store.databaseRevision, !Task.isCancelled else { return }
            stats = value; error = nil
            if op.isEmpty {
                operators = value.operators.map(\.label)
                if firstOperator.isEmpty { firstOperator = operators.first ?? "" }
                if secondOperator.isEmpty { secondOperator = operators.dropFirst().first ?? "" }
            }
        } catch { if !Task.isCancelled, selectedOperator == op, revision == store.databaseRevision { self.error = error.localizedDescription; stats = nil } }
    }
}

// Values live outside the bars so labels remain legible at every screen width.
struct FrequencyBars: View {
    let items: [StatItem]
    let color: Color
    private var maximum: Double { Double(max(1, items.map(\.count).max() ?? 1)) }
    var body: some View {
        VStack(spacing: 18) {
            ForEach(items) { item in
                VStack(spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(item.label.isEmpty ? "Bande non renseignée" : item.label + " MHz").font(.subheadline.weight(.medium))
                        Spacer(minLength: 4)
                        Text(item.count.formatted()).font(.subheadline.monospacedDigit()).fixedSize(horizontal: true, vertical: false)
                    }
                    GeometryReader { proxy in
                        Capsule().fill(color.opacity(0.12))
                        Capsule().fill(color.gradient).frame(width: max(0, proxy.size.width * Double(item.count) / maximum))
                    }.frame(height: 8).accessibilityHidden(true)
                }.accessibilityElement(children: .combine)
            }
        }
    }
}
struct DeploymentChart: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @ScaledMetric(relativeTo: .caption) private var labelHalfWidth: CGFloat = 18
    let items: [StatItem]
    @ScaledMetric(relativeTo: .caption) private var height: CGFloat = 210
    @ScaledMetric(relativeTo: .caption) private var axisWidth: CGFloat = 46
    @ScaledMetric(relativeTo: .caption) private var labelsHeight: CGFloat = 40
    private var upperBound: Double {
        let maximum = Double(max(1, items.map(\.count).max() ?? 1))
        let step = max(1, pow(10, floor(log10(maximum / 4))))
        return ceil(maximum / (4 * step)) * step * 4
    }
    private var ticks: [Int] {
        guard items.count > 1 else { return Array(items.indices) }
        if textSize >= .accessibility3 { return [0, items.count - 1] }
        if textSize.isAccessibilitySize { return Array(Set([0, (items.count - 1) / 2, items.count - 1])).sorted() }
        return Array(Set([0, (items.count - 1) / 3, (items.count - 1) * 2 / 3, items.count - 1])).sorted()
    }
    private func labelX(_ index: Int, width: CGFloat) -> CGFloat {
        let fraction = (CGFloat(index) + 0.5) / CGFloat(max(1, items.count))
        return axisWidth + 8 + min(width - labelHalfWidth, max(labelHalfWidth, width * fraction))
    }
    private func label(_ value: String) -> String {
        let parts = value.split(separator: "-")
        return parts.count == 2 ? "\(parts[1])\n\(parts[0])" : value
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 10) {
                GeometryReader { proxy in
                    ForEach(0..<5) { tick in
                        let value = upperBound * Double(tick) / 4
                        HStack(spacing: 8) {
                            Text(value.formatted(.number.precision(.fractionLength(0))))
                                .font(.caption.monospacedDigit()).foregroundStyle(.primary).lineLimit(1).minimumScaleFactor(0.75)
                                .frame(width: axisWidth, alignment: .trailing)
                            Rectangle().fill(.secondary.opacity(0.2)).frame(height: 0.5)
                        }.position(x: proxy.size.width / 2, y: proxy.size.height * (1 - Double(tick) / 4))
                    }
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(items) { item in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(.teal.gradient)
                                .frame(width: max(1, (proxy.size.width - axisWidth - 8) / CGFloat(max(1, items.count)) * 0.65), height: max(0, proxy.size.height * CGFloat(item.count) / CGFloat(upperBound)))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        }
                    }.padding(.leading, axisWidth + 8)
                }.frame(height: height).padding(.top, 10)
                GeometryReader { proxy in
                    let width = max(1, proxy.size.width - axisWidth - 8)
                    ForEach(ticks, id: \.self) { index in
                        Text(label(items[index].label)).font(.caption).foregroundStyle(.primary)
                            .multilineTextAlignment(.center).fixedSize()
                            .position(x: labelX(index, width: width), y: labelsHeight / 2)
                    }
                }.frame(height: labelsHeight)
            }.accessibilityElement(children: .ignore).accessibilityLabel("Nombre de systèmes par mois de date ANFR. Le détail des valeurs est disponible ci-dessous.")
            DisclosureGroup("Nombre de systèmes par mois") {
                ForEach(items) { item in
                    LabeledContent(item.label, value: item.count.formatted()).font(.subheadline).padding(.vertical, 3)
                }
            }.font(.subheadline)
        }
    }
}
