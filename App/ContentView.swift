import SwiftUI
import MapKit

struct ContentView: View {
    var body: some View {
        TabView {
            Tab("Explorer", systemImage: "map") { ExplorerView() }
            Tab("Favoris", systemImage: "star") { FavoritesView() }
            Tab("Field Test", systemImage: "waveform.path.ecg") { FieldTestView() }
            Tab("Comprendre", systemImage: "book.closed") { LearnView() }
            Tab("Données", systemImage: "arrow.triangle.2.circlepath") { DataView() }
        }
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
            Image(systemName: "antenna.radiowaves.left.and.right").font(.title2).foregroundStyle(.blue).frame(width: 40)
            VStack(alignment: .leading, spacing: 5) {
                Text(station.operatorName.capitalized).font(.headline)
                Text(station.address).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text(station.systems).font(.caption2).foregroundStyle(.blue).lineLimit(2)
            }
        }.padding(.vertical, 5)
    }
}
struct ExplorerView: View {
    @Environment(AppStore.self) private var store
    @State private var position: MapCameraPosition = .region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522), span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)))
    @State private var selected: Station?
    @State private var search = ""
    @State private var searchMessage = ""
    @State private var location = LocationService()
    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Map(position: $position) {
                UserAnnotation()
                ForEach(store.stations) { station in
                    Annotation(station.operatorName.capitalized, coordinate: CLLocationCoordinate2D(latitude: station.latitude, longitude: station.longitude)) {
                        Button { selected = station } label: {
                            Image(systemName: "antenna.radiowaves.left.and.right").font(.caption.bold()).padding(10).foregroundStyle(.white).background(.blue.gradient, in: Circle())
                        }.accessibilityLabel("Antenne \(station.operatorName), \(station.address)")
                    }
                }
            }
            .mapControls { MapCompass(); MapScaleView() }
            .onMapCameraChange(frequency: .onEnd) { context in store.region = context.region; Task { await store.load() } }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 10) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Une ville, une adresse…", text: $search).submitLabel(.search).onSubmit { Task { await find() } }
                        Button { location.locate() } label: { Image(systemName: "location.fill") }.accessibilityLabel("Autour de moi")
                    }.padding(15).pyloGlass()
                    HStack {
                        Picker("Réseau", selection: $store.generation) { Text("Tous").tag(""); ForEach(["3G","4G","5G"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
                        Menu {
                            Picker("Opérateur", selection: $store.operatorName) {
                                Text("Tous les opérateurs").tag("")
                                ForEach(["ORANGE","SFR","BOUYGUES TELECOM","FREE MOBILE","DAUPHIN TELECOM","DIGICEL","FREE CARAIBES","GLOBALTEL","Gouv Nelle Calédonie (OPT)","MAORE MOBILE","ONATI","OUTREMER TELECOM","PMT-VODAFONE","SPM TELECOM","SPT","SRR","TELCO OI","UTS Caraibes","VITI SAS","ZEOP"], id: \.self) { Text($0.capitalized).tag($0) }
                            }
                        } label: { Image(systemName: "line.3.horizontal.decrease").padding(12).pyloGlass() }.accessibilityLabel("Filtrer les opérateurs")
                    }
                }.padding(.horizontal).padding(.top, 6)
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Le réseau, autour de toi.").font(.headline)
                        Text(store.message ?? (store.stations.count >= 600 ? "600 stations affichées · zoome pour affiner" : "\(store.stations.count) stations dans cette zone")).font(.caption).foregroundStyle(.secondary)
                        if !location.status.isEmpty { Text(location.status).font(.caption) }
                        if !searchMessage.isEmpty { Text(searchMessage).font(.caption) }
                    }
                    Spacer()
                    if store.loading { ProgressView() } else { Image(systemName: "antenna.radiowaves.left.and.right").foregroundStyle(.blue).font(.title2) }
                }.padding(18).pyloGlass().padding()
            }
            .navigationTitle("pylo").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selected) { StationDetail(station: $0).presentationDetents([.medium,.large]) }
            .task { await store.load() }
            .onChange(of: store.generation) { Task { await store.load() } }
            .onChange(of: store.operatorName) { Task { await store.load() } }
            .onChange(of: location.coordinate?.latitude) {
                if let c = location.coordinate { position = .region(MKCoordinateRegion(center: c, span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04))) }
            }
        }
    }
    private func find() async {
        guard !search.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let request = MKLocalSearch.Request(); request.naturalLanguageQuery = search; request.region = store.region
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard let item = response.mapItems.first else { searchMessage = "Aucun lieu trouvé."; return }
            position = .region(MKCoordinateRegion(center: item.placemark.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04))); searchMessage = ""
        } catch { searchMessage = "La recherche nécessite une connexion." }
    }
}
struct StationDetail: View {
    @Environment(AppStore.self) private var store
    let station: Station
    var body: some View {
        NavigationStack {
            List {
                Section { StationRow(station: station) }
                Section("La station") {
                    LabeledContent("Identifiant ANFR", value: station.id)
                    LabeledContent("État déclaré", value: station.status)
                    LabeledContent("Mise à jour source", value: String(station.updated.prefix(10)))
                    LabeledContent("Latitude", value: String(format: "%.5f", station.latitude))
                    LabeledContent("Longitude", value: String(format: "%.5f", station.longitude))
                }
                Section {
                    Button { store.toggle(station) } label: { Label(store.favorites.contains(station.id) ? "Retirer des favoris" : "Garder en favori", systemImage: store.favorites.contains(station.id) ? "star.fill" : "star") }
                    Button("Itinéraire dans Plans", systemImage: "arrow.triangle.turn.up.right.diamond") {
                        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: station.latitude, longitude: station.longitude)))
                        item.name = station.operatorName; item.openInMaps()
                    }
                    ShareLink(item: "Station ANFR \(station.id) · \(station.operatorName)\n\(station.address)\n\(station.systems)\nhttps://maps.apple.com/?ll=\(station.latitude),\(station.longitude)")
                }
                Section { Text("Une antenne proche n’est pas forcément celle utilisée par ton iPhone. La présence d’une station ne garantit ni la couverture ni le débit à cet endroit.").font(.footnote).foregroundStyle(.secondary) }
            }.navigationTitle("L’antenne en détail").navigationBarTitleDisplayMode(.inline)
        }
    }
}
struct FavoritesView: View {
    @Environment(AppStore.self) private var store
    @State private var saved: [Station] = []
    var body: some View {
        NavigationStack {
            List(saved) { station in NavigationLink { StationDetail(station: station) } label: { StationRow(station: station) } }
                .overlay { if saved.isEmpty { ContentUnavailableView("Tes antennes, de côté", systemImage: "star", description: Text("Ajoute une station depuis la carte pour la retrouver ici.")) } }
                .navigationTitle("Favoris").task { saved = store.savedStations() }.onChange(of: store.favorites) { saved = store.savedStations() }
        }
    }
}
