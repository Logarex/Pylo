import SwiftUI
import MapKit

struct StationDetail: View {
    @Environment(AppStore.self) private var store
    let station: Station
    @State private var systems: [RadioSystem] = []
    @State private var supports: [AntennaSupport] = []
    @State private var error: String?
    private var color: Color { Palette.operatorColor(station.operatorName) }
    private var distance: Double? {
        guard let user = store.location.coordinate else { return nil }
        return CLLocation(latitude: user.latitude, longitude: user.longitude).distance(from: CLLocation(latitude: station.latitude, longitude: station.longitude))
    }
    private var bearing: Double? {
        guard let user = store.location.coordinate else { return nil }
        return Geometry.bearing(lat1: user.latitude, lon1: user.longitude, lat2: station.latitude, lon2: station.longitude)
    }
    private var azimuths: [Double] { Array(Set(systems.flatMap(\.azimuths))).sorted() }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    hero
                    InfoCard("Les réseaux de cette station", subtitle: "Chaque bande a son propre état déclaré à l’ANFR.") {
                        if let error { Text(error).foregroundStyle(.secondary) }
                        ForEach(["2G","3G","4G","5G"], id: \.self) { g in
                            let group = systems.filter { $0.generation == g }
                            if !group.isEmpty {
                                HStack { Text(g).font(.title3.bold()).foregroundStyle(Palette.generation(g)); Text(technology(g)).font(.subheadline).foregroundStyle(.secondary) }
                                ForEach(group) { system in
                                    VStack(alignment: .leading, spacing: 7) {
                                        HStack(alignment: .top) {
                                            Text(system.name).font(.headline)
                                            Spacer()
                                            Text(system.status).font(.caption.weight(.medium)).foregroundStyle(system.status.contains("Projet") ? Color.orange : Color.teal).multilineTextAlignment(.trailing)
                                        }
                                        if !system.date.isEmpty { Text("Date système ANFR : \(formattedDate(system.date))").font(.caption).foregroundStyle(.secondary) }
                                        if !system.azimuths.isEmpty { Text("Directions : \(system.azimuths.map { "\(Int($0))°" }.joined(separator: " · "))").font(.caption).foregroundStyle(.secondary) }
                                    }.padding(12).background(Palette.generation(g).opacity(0.06), in: .rect(cornerRadius: 14))
                                }
                            }
                        }
                        Text("GSM, UMTS, LTE et NR sont les technologies radio. Les nombres indiquent les bandes de fréquence en MHz. La date système ANFR n’est pas la date d’ajout à Pylo.").font(.footnote).foregroundStyle(.secondary)
                    }
                    InfoCard("Dans quelle direction ?", subtitle: "Les axes viennent des azimuts déclarés par l’ANFR.") {
                        HStack(spacing: 22) {
                            CompassDiagram(azimuths: azimuths, bearing: bearing, heading: store.location.heading, color: color).frame(width: 130, height: 150)
                            VStack(alignment: .leading, spacing: 9) {
                                Text(azimuths.isEmpty ? "Orientation non renseignée" : azimuths.map { "\(Int($0))°" }.joined(separator: " · ")).font(.headline)
                                if let bearing { Text("Depuis toi : cap \(Int(bearing))° vers la station.").font(.subheadline) }
                                if let heading = store.location.heading { Text("Ton iPhone pointe à \(Int(heading))° du nord vrai.").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                        Text("0° = nord, 90° = est. Les traits montrent des directions, pas des zones de couverture. L’ANFR ne fournit ici ni l’ouverture du faisceau ni son inclinaison. Plusieurs bandes peuvent avoir des directions différentes.").font(.footnote).foregroundStyle(.secondary)
                        Button("Utiliser ma position et la boussole", systemImage: "location.north.circle") { store.location.locate() }
                        if !store.location.status.isEmpty { Text(store.location.status).font(.caption).foregroundStyle(.orange) }
                    }
                    InfoCard("Et la réception chez moi ?", subtitle: "Des indices pour comprendre, pas une mesure de ton signal.") {
                        if let distance {
                            Label(distance.formatted(.number.precision(.fractionLength(0))) + " m à vol d’oiseau", systemImage: "point.topleft.down.to.point.bottomright.curvepath").font(.headline)
                            if let accuracy = store.location.accuracy { Text("Précision de ta position : environ \(Int(max(0,accuracy))) m.").font(.caption).foregroundStyle(.secondary) }
                            Text(distance < 1000 ? "Cette station est proche. Les murs, le relief, la direction des panneaux et la charge du réseau peuvent quand même dégrader la réception." : "La distance atténue le signal. Une bande basse peut aider à porter plus loin ; les obstacles et les autres signaux restent déterminants.")
                            if let user = store.location.coordinate, !azimuths.isEmpty {
                                let towardUser = Geometry.bearing(lat1: station.latitude, lon1: station.longitude, lat2: user.latitude, lon2: user.longitude)
                                let delta = azimuths.map { Geometry.angularDifference($0, towardUser) }.min() ?? 0
                                Text("Tu te situes à \(Int(delta))° de l’axe déclaré le plus proche. Cet angle ne suffit pas à dire si tu es dans son faisceau.").font(.footnote)
                            }
                        } else { Text("Autorise la localisation pour connaître la distance et la direction de cette station depuis toi.") }
                        Text("On ne peut pas calculer un RSRP, un SINR ou un débit fiable avec la distance seule : il manque la puissance émise, les gains, les obstacles et le bruit. Pour savoir ce que reçoit vraiment ton iPhone, regarde Field Test.").font(.footnote).foregroundStyle(.secondary)
                        NavigationLink { FieldTestView() } label: { Label("Comprendre mon signal", systemImage: "waveform.path.ecg") }
                    }
                    InfoCard("Le site en détail") {
                        LabeledContent("Station ANFR", value: station.id)
                        ForEach(supports) { support in
                            VStack(alignment: .leading, spacing: 7) {
                                LabeledContent("Support physique", value: support.id)
                                if !support.height.isEmpty { LabeledContent("Hauteur du support", value: support.height + " m") }
                                Text(String(format: "%.5f, %.5f", support.latitude, support.longitude)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        LabeledContent("Publication source", value: formattedDate(station.updated))
                        LabeledContent("Coordonnées", value: String(format: "%.5f, %.5f", station.latitude, station.longitude))
                        Text("Une station regroupe des équipements d’un opérateur et peut être rattachée à plusieurs supports dans la source. Plusieurs stations peuvent partager un support. La hauteur du support n’est pas forcément celle des panneaux. Si plusieurs supports sont présents, le repère de carte et la distance utilisent le premier enregistré ; les directions ci-dessus regroupent les azimuts déclarés.").font(.footnote).foregroundStyle(.secondary)
                    }
                    InfoCard("À garder sous la main") {
                        Button { store.toggle(station) } label: { Label(store.favorites.contains(station.id) ? "Retirer des favoris" : "Garder en favori", systemImage: store.favorites.contains(station.id) ? "star.fill" : "star") }
                        Button("Itinéraire dans Plans", systemImage: "arrow.triangle.turn.up.right.diamond") {
                            let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: station.latitude, longitude: station.longitude)))
                            item.name = station.operatorName; item.openInMaps()
                        }
                        ShareLink(item: "Station ANFR \(station.id) · \(station.operatorName)\n\(station.address)\n\(station.systems)\nhttps://maps.apple.com/?ll=\(station.latitude),\(station.longitude)") { Label("Partager cette station", systemImage: "square.and.arrow.up") }
                    }
                }.padding(16)
            }.background(Color(.systemGroupedBackground)).navigationTitle("La station").navigationBarTitleDisplayMode(.inline)
                .task { loadSystems() }
        }
    }
    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "antenna.radiowaves.left.and.right").font(.largeTitle).foregroundStyle(color)
                Spacer()
                Text("DONNÉES ANFR").font(.caption2.bold()).tracking(1.5).foregroundStyle(.secondary)
            }
            Text(operatorDisplayName(station.operatorName)).font(.largeTitle.bold())
            Text(station.address).font(.subheadline).foregroundStyle(.secondary)
            HStack { ForEach(["2G","3G","4G","5G"].filter { g in systems.contains { $0.generation == g } }, id: \.self) { g in Text(g).font(.subheadline.bold()).padding(.horizontal,12).padding(.vertical,7).background(Palette.generation(g).opacity(0.12), in: Capsule()).foregroundStyle(Palette.generation(g)) } }
            Label("Station déclarée · connexion non confirmée", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(24).background(color.opacity(0.07), in: .rect(cornerRadius: 28))
    }
    private func loadSystems() {
        do { if let url = store.databaseURL { let db = try AntennaDatabase(url: url); systems = try db.systems(for: station.id); supports = try db.supports(for: station.id) } }
        catch { self.error = error.localizedDescription }
    }
    private func technology(_ generation: String) -> String { switch generation { case "2G": "GSM"; case "3G": "UMTS"; case "4G": "LTE"; default: "5G NR" } }
}
func formattedDate(_ string: String) -> String {
    let iso = String(string.prefix(10)); let parts = iso.split(separator: "-")
    return parts.count == 3 ? "\(parts[2])/\(parts[1])/\(parts[0])" : string
}
struct CompassDiagram: View {
    let azimuths: [Double]
    let bearing: Double?
    let heading: Double?
    let color: Color
    var body: some View {
        ZStack {
            Circle().stroke(.secondary.opacity(0.2), lineWidth: 1).padding(14)
            Text("N").font(.caption.bold()).offset(y: -64)
            Text("S").font(.caption2).foregroundStyle(.secondary).offset(y: 64)
            Text("E").font(.caption2).foregroundStyle(.secondary).offset(x: 61)
            Text("O").font(.caption2).foregroundStyle(.secondary).offset(x: -61)
            ForEach(azimuths, id: \.self) { angle in
                Rectangle().fill(color).frame(width: 6, height: 43).offset(y: -21).rotationEffect(.degrees(angle))
                Image(systemName: "arrowtriangle.up.fill").font(.system(size: 19, weight: .black)).foregroundStyle(color).offset(y: -45).rotationEffect(.degrees(angle))
            }
            Circle().fill(color).frame(width: 12,height: 12)
            if let heading { Image(systemName: "location.north.fill").foregroundStyle(.secondary).offset(y: -29).rotationEffect(.degrees(heading)) }
        }.accessibilityElement(children: .ignore).accessibilityLabel("Orientations ANFR : \(azimuths.map { String(Int($0)) }.joined(separator: ", ")) degrés depuis le nord")
    }
}
