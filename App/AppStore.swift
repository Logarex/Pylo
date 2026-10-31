import Foundation
import SwiftUI
import CoreLocation
import MapKit

struct Measurement: Codable, Identifiable {
    var id = UUID(); var date = Date()
    var generation = "4G"; var rsrp = ""; var rsrq = ""; var sinr = ""; var cellID = ""; var note = ""
}
@MainActor @Observable final class AppStore {
    var stations: [Station] = []
    var message: String?
    var loading = false
    var generation = ""
    var operatorName = ""
    var favorites: Set<String> { didSet { UserDefaults.standard.set(Array(favorites), forKey: "favorites") } }
    var measurements: [Measurement] { didSet { if let data = try? JSONEncoder().encode(measurements) { UserDefaults.standard.set(data, forKey: "measurements") } } }
    var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522), span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06))
    private var request = UUID()
    static var localDatabase: URL { URL.documentsDirectory.appendingPathComponent("antennas.sqlite") }
    init() {
        favorites = Set(UserDefaults.standard.stringArray(forKey: "favorites") ?? [])
        measurements = (UserDefaults.standard.data(forKey: "measurements").flatMap { try? JSONDecoder().decode([Measurement].self, from: $0) }) ?? []
    }
    var databaseURL: URL? {
        FileManager.default.fileExists(atPath: Self.localDatabase.path) ? Self.localDatabase : Bundle.main.url(forResource: "antennas", withExtension: "sqlite")
    }
    func load() async {
        guard let url = databaseURL else { message = "Ajoute une base ANFR dans l’onglet Données."; return }
        let token = UUID(); request = token; loading = true
        let r = region, g = generation, op = operatorName
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                let db = try AntennaDatabase(url: url)
                return try db.stations(south: r.center.latitude-r.span.latitudeDelta/2, north: r.center.latitude+r.span.latitudeDelta/2, west: r.center.longitude-r.span.longitudeDelta/2, east: r.center.longitude+r.span.longitudeDelta/2, generation: g, operatorName: op)
            }.value
            guard request == token else { return }
            stations = result; message = nil; loading = false
        } catch { if request == token { message = error.localizedDescription; loading = false } }
    }
    func importDatabase(_ url: URL) async {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let staging = URL.documentsDirectory.appendingPathComponent("import-\(UUID().uuidString).sqlite")
            defer { try? FileManager.default.removeItem(at: staging) }
            try data.write(to: staging)
            let db = try AntennaDatabase(url: staging); try db.validate()
            try data.write(to: Self.localDatabase, options: .atomic)
            await load()
        } catch { message = "Import impossible : \(error.localizedDescription)" }
    }
    func toggle(_ station: Station) { if !favorites.insert(station.id).inserted { favorites.remove(station.id) } }
    func savedStations() -> [Station] {
        guard let url = databaseURL, let db = try? AntennaDatabase(url: url), let all = try? db.stations(limit: 200000) else { return [] }
        return all.filter { favorites.contains($0.id) }
    }
}
@MainActor @Observable final class LocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var coordinate: CLLocationCoordinate2D?
    var status = ""
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyHundredMeters }
    func locate() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { status = "Localisation refusée. Tu peux l’activer dans Réglages." }
        else { manager.requestLocation() }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { manager.requestLocation() }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { coordinate = locations.last?.coordinate; status = "" }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { status = "Position indisponible pour le moment." }
}
