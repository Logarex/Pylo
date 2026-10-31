import SwiftUI
import MapKit

struct ContentView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Group {
        if store.ready {
        TabView {
            Tab("Explorer", systemImage: "map") { ExplorerView() }
            Tab("Favoris", systemImage: "star") { FavoritesView() }
            Tab("Field Test", systemImage: "waveform.path.ecg") { FieldTestView() }
            Tab("Statistiques", systemImage: "chart.bar.xaxis") { StatisticsView() }
            Tab("Le projet", systemImage: "info.circle") { DataView() }
        }
        } else { ProgressView("Préparation des données ANFR…").padding() }
        }.task { await store.prepare() }
    }
}
extension View {
    @ViewBuilder func pyloGlass() -> some View {
        if #available(iOS 26, *) { self.glassEffect(.regular, in: .rect(cornerRadius: 24)) }
        else { self.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24)) }
    }
}
struct StationRow: View {
    let station: Station
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "antenna.radiowaves.left.and.right").font(.title2).foregroundStyle(Palette.operatorColor(station.operatorName)).frame(width: 44, height: 44).background(Palette.operatorColor(station.operatorName).opacity(0.12), in: .rect(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 7) {
                Text(operatorDisplayName(station.operatorName)).font(.headline)
                Text(station.address).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 5) { ForEach(["2G","3G","4G","5G"].filter { g in station.systems.components(separatedBy: " · ").contains { Radio.generation($0) == g } }, id: \.self) { g in Text(g).font(.caption2.bold()).padding(.horizontal, 7).padding(.vertical, 3).background(Palette.generation(g).opacity(0.13), in: Capsule()).foregroundStyle(Palette.generation(g)) } }
            }
        }.padding(.vertical, 6)
    }
}
struct StationCluster: Identifiable {
    let id: String
    let stations: [Station]
    var latitude: Double { stations.reduce(0) { $0 + $1.latitude } / Double(stations.count) }
    var longitude: Double { stations.reduce(0) { $0 + $1.longitude } / Double(stations.count) }
}
struct ExplorerView: View {
    @Environment(AppStore.self) private var store
    @State private var command: MapCommand?
    @State private var reloadTask: Task<Void, Never>?
    @State private var selected: StationCluster?
    @State private var search = ""
    @State private var searchMessage = ""
    @State private var suggestions = AddressSuggestions()
    @FocusState private var searchFocused: Bool
    @State private var placeSearch: MKLocalSearch?
    @State private var searchRequestID = UUID()
    @State private var showDirections = false
    var body: some View {
        @Bindable var store = store
        NavigationStack {
            NativeAntennaMap(initialRegion: store.region, stations: store.stations, directions: store.directions, showDirections: showDirections, command: command, onRegion: { region in
                store.region = region
                reloadTask?.cancel()
                reloadTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    await store.load()
                }
            }, onSelection: { stations in
                guard !stations.isEmpty else { return }
                selected = StationCluster(id: UUID().uuidString, stations: stations)
            })
            .ignoresSafeArea(.container, edges: .all)
            .safeAreaInset(edge: .top) {
                VStack(spacing: 10) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Une ville, une adresse…", text: $search)
                            .focused($searchFocused).autocorrectionDisabled().submitLabel(.search)
                            .onSubmit { searchFocused = false; suggestions.clear(); Task { await find() } }
                        if !search.isEmpty {
                            Button { search = ""; suggestions.clear(); searchMessage = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.accessibilityLabel("Effacer la recherche")
                        }
                        Button { store.location.locate() } label: { Image(systemName: "location.fill") }.accessibilityLabel("Autour de moi")
                    }.padding(15).pyloGlass()
                    if searchFocused && (!suggestions.results.isEmpty || suggestions.loading || !suggestions.message.isEmpty) {
                        ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if suggestions.loading { HStack { ProgressView(); Text("Recherche de propositions…").font(.caption).foregroundStyle(.secondary) }.padding(14) }
                            ForEach(Array(suggestions.results.enumerated()), id: \.offset) { index, completion in
                                if index > 0 { Divider().padding(.leading, 42) }
                                Button {
                                    searchFocused = false
                                    search = [completion.title, completion.subtitle].filter { !$0.isEmpty }.joined(separator: ", ")
                                    suggestions.clear()
                                    Task { await find(completion: completion) }
                                } label: {
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: "mappin.and.ellipse").foregroundStyle(Palette.accent).frame(width: 20)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(completion.title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                            if !completion.subtitle.isEmpty { Text(completion.subtitle).font(.caption).foregroundStyle(.secondary) }
                                        }
                                        Spacer(minLength: 0)
                                    }.padding(12).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                            if !suggestions.message.isEmpty { Text(suggestions.message).font(.caption).foregroundStyle(.secondary).padding(14) }
                        }
                        }.frame(maxHeight: suggestions.results.isEmpty ? 75 : 250)
                            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
                    }
                    HStack {
                        Picker("Réseau", selection: $store.generation) { Text("Tous").tag(""); ForEach(["2G","3G","4G","5G"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
                        Menu {
                            Picker("Opérateur", selection: $store.operatorName) {
                                Text("Tous les opérateurs").tag("")
                                ForEach(["ORANGE","SFR","BOUYGUES TELECOM","FREE MOBILE","DAUPHIN TELECOM","DIGICEL","FREE CARAIBES","GLOBALTEL","Gouv Nelle Calédonie (OPT)","MAORE MOBILE","ONATI","OUTREMER TELECOM","PMT-VODAFONE","SPM TELECOM","SPT","SRR","TELCO OI","UTS Caraibes","VITI SAS","ZEOP"], id: \.self) { Text(operatorDisplayName($0)).tag($0) }
                            }
                        } label: { Image(systemName: "line.3.horizontal.decrease").padding(12).pyloGlass() }.accessibilityLabel("Filtrer les opérateurs")
                    }
                }.padding(.horizontal).padding(.top, 6)
            }
            .overlay(alignment: .trailing) {
                VStack(spacing: 0) {
                    Button { zoom(0.5) } label: { Image(systemName: "plus").frame(width: 48, height: 48) }.accessibilityLabel("Zoomer")
                    Divider().frame(width: 25)
                    Button { zoom(2) } label: { Image(systemName: "minus").frame(width: 48, height: 48) }.accessibilityLabel("Dézoomer")
                    Divider().frame(width: 25)
                    Button { showDirections.toggle() } label: { Image(systemName: showDirections ? "location.north.line.fill" : "location.north.line").frame(width: 48, height: 48) }.accessibilityLabel("Afficher les orientations ANFR").accessibilityValue(showDirections ? "Activées" : "Désactivées")
                }.pyloGlass().padding(.trailing, 12)
            }
            .safeAreaInset(edge: .bottom) {
                if !searchFocused {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Le réseau, autour de toi.").font(.headline)
                        Text(store.message ?? (store.stations.count >= 600 ? "600 stations affichées · zoome pour affiner" : "\(store.stations.count) stations dans cette zone")).font(.caption).foregroundStyle(.secondary)
                        if !store.location.status.isEmpty { Text(store.location.status).font(.caption) }
                        if !searchMessage.isEmpty { Text(searchMessage).font(.caption) }
                        if showDirections { Text("Orientations des stations isolées · après le zoom · pas une couverture").font(.caption2) }
                        Text("Groupes multicolores : plusieurs opérateurs.").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if store.loading { ProgressView() } else { Image(systemName: "antenna.radiowaves.left.and.right").foregroundStyle(Palette.accent).font(.title2) }
                }.padding(18).pyloGlass().padding()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $selected) { cluster in
                if cluster.stations.count == 1, let station = cluster.stations.first {
                    StationDetail(station: station).presentationDetents([.medium,.large])
                } else {
                    NavigationStack {
                        List(cluster.stations) { station in NavigationLink { StationDetail(station: station) } label: { StationRow(station: station) } }
                            .navigationTitle("\(cluster.stations.count) stations proches").navigationBarTitleDisplayMode(.inline)
                    }.presentationDetents([.medium,.large])
                }
            }
            .task { await store.load() }
            .onDisappear { reloadTask?.cancel(); suggestions.clear(); searchRequestID = UUID(); placeSearch?.cancel() }
            .onChange(of: search) {
                searchMessage = ""
                if searchFocused { searchRequestID = UUID(); placeSearch?.cancel(); suggestions.update(search, region: store.region) }
            }
            .onChange(of: searchFocused) {
                if searchFocused { suggestions.update(search, region: store.region) }
                else { suggestions.clear() }
            }
            .onChange(of: store.generation) { Task { await store.load() } }
            .onChange(of: store.operatorName) { Task { await store.load() } }
            .onChange(of: store.location.coordinate?.latitude) {
                if let c = store.location.coordinate { command = MapCommand(region: MKCoordinateRegion(center: c, span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04))) }
            }
        }
    }
    private func zoom(_ factor: Double) {
        let r = store.region
        let span = MKCoordinateSpan(latitudeDelta: min(140, max(0.001, r.span.latitudeDelta * factor)), longitudeDelta: min(300, max(0.001, r.span.longitudeDelta * factor)))
        let target = MKCoordinateRegion(center: r.center, span: span)
        store.region = target
        command = MapCommand(region: target)
    }
    private func find(completion: MKLocalSearchCompletion? = nil) async {
        guard completion != nil || !search.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        placeSearch?.cancel()
        let token = UUID(); searchRequestID = token
        let request: MKLocalSearch.Request
        if let completion { request = MKLocalSearch.Request(completion: completion) }
        else { request = MKLocalSearch.Request(); request.naturalLanguageQuery = search }
        request.region = store.region
        let lookup = MKLocalSearch(request: request); placeSearch = lookup
        do {
            let response = try await lookup.start()
            guard searchRequestID == token, !Task.isCancelled else { return }
            guard let item = response.mapItems.first else { searchMessage = "Aucun lieu trouvé."; return }
            command = MapCommand(region: MKCoordinateRegion(center: item.placemark.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04))); searchMessage = ""
        } catch {
            if searchRequestID == token && !Task.isCancelled { searchMessage = "Recherche indisponible. Vérifie ta connexion puis réessaie." }
        }
    }
}
@MainActor @Observable final class AddressSuggestions: NSObject, @preconcurrency MKLocalSearchCompleterDelegate {
    var results: [MKLocalSearchCompletion] = []
    var loading = false
    var message = ""
    @ObservationIgnored private var completer: MKLocalSearchCompleter?
    @ObservationIgnored private var pending: Task<Void, Never>?
    func clear() {
        pending?.cancel(); pending = nil
        completer?.delegate = nil; completer?.cancel(); completer = nil
        results = []; loading = false; message = ""
    }
    func update(_ text: String, region: MKCoordinateRegion) {
        clear()
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else { return }
        loading = true
        pending = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            let engine = MKLocalSearchCompleter()
            self.completer = engine
            engine.delegate = self; engine.region = region; engine.resultTypes = [.address]
            engine.queryFragment = query
        }
    }
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        guard completer === self.completer else { return }
        results = Array(completer.results.prefix(5)); loading = false
        message = results.isEmpty ? "Aucune proposition. Tu peux préciser l’adresse ou appuyer sur Rechercher." : ""
    }
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        guard completer === self.completer else { return }
        results = []; loading = false
        message = "Propositions indisponibles. Vérifie ta connexion ou appuie sur Rechercher pour réessayer."
    }
}
private struct FavoritesRequest: Hashable {
    let ids: Set<String>
    let databaseRevision: Int
}
struct FavoritesView: View {
    @Environment(AppStore.self) private var store
    @State private var saved: [Station] = []
    @State private var loading = false
    @State private var error: String?
    var body: some View {
        let request = FavoritesRequest(ids: store.favorites, databaseRevision: store.databaseRevision)
        NavigationStack {
            List(saved) { station in NavigationLink { StationDetail(station: station) } label: { StationRow(station: station) } }
                .overlay {
                    if saved.isEmpty {
                        if loading { ProgressView("Lecture de tes favoris…") }
                        else if let error { ContentUnavailableView("Favoris indisponibles", systemImage: "exclamationmark.circle", description: Text(error)) }
                        else { ContentUnavailableView("Tes antennes, de côté", systemImage: "star", description: Text(store.favorites.isEmpty ? "Ajoute une station depuis la carte pour la retrouver ici." : "Ces stations ne figurent plus dans la base actuelle. Tes identifiants favoris sont conservés.")) }
                    }
                }
                .navigationTitle("Favoris")
                .task(id: request) {
                    guard !request.ids.isEmpty else { saved = []; error = nil; loading = false; return }
                    loading = saved.isEmpty
                    do {
                        let result = try await store.savedStations(ids: request.ids)
                        guard !Task.isCancelled else { return }
                        saved = result; error = nil; loading = false
                    } catch {
                        guard !Task.isCancelled else { return }
                        self.error = error.localizedDescription; loading = false
                    }
                }
        }
    }
}
