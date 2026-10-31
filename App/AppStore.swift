import Foundation
import SwiftUI
import CoreLocation
import MapKit

@MainActor @Observable final class AppStore {
    var stations: [Station] = []
    var directions: [String: [Double]] = [:]
    var message: String?
    var loading = false
    var ready = false
    var generation = ""
    var operatorName = ""
    var favorites: Set<String> { didSet { UserDefaults.standard.set(Array(favorites), forKey: "favorites") } }
    let location = LocationService()
    let device = DeviceNetworkInfo()
    var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522), span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06))
    private var request = UUID()
    static var localDatabase: URL { URL.documentsDirectory.appendingPathComponent("antennas.sqlite") }
    init() {
        favorites = Set(UserDefaults.standard.stringArray(forKey: "favorites") ?? [])

    }
    var databaseURL: URL? {
        FileManager.default.fileExists(atPath: Self.localDatabase.path) ? Self.localDatabase : (FileManager.default.fileExists(atPath: Self.bundledDatabase.path) ? Self.bundledDatabase : nil)
    }
    static var bundledDatabase: URL { URL.cachesDirectory.appendingPathComponent("anfr-v2-2.sqlite") }
    func prepare() async {
        guard !ready else { return }
        do {
            if !FileManager.default.fileExists(atPath: Self.bundledDatabase.path), let source = Bundle.main.url(forResource: "antennas.sqlite", withExtension: "gz") {
                let destination = Self.bundledDatabase
                try await Task.detached { try AntennaDatabase.unpack(source: source, destination: destination) }.value
            }
            ready = true
        } catch { message = error.localizedDescription; ready = true }
    }
    func load() async {
        guard let url = databaseURL else { message = "Ajoute une base ANFR dans l’onglet Données."; return }
        let token = UUID(); request = token; loading = true
        let r = region, g = generation, op = operatorName
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                let db = try AntennaDatabase(url: url)
                let stations = try db.stations(south: r.center.latitude-r.span.latitudeDelta/2, north: r.center.latitude+r.span.latitudeDelta/2, west: r.center.longitude-r.span.longitudeDelta/2, east: r.center.longitude+r.span.longitudeDelta/2, generation: g, operatorName: op)
                let directions = Dictionary(uniqueKeysWithValues: stations.sorted { a,b in
                    pow(a.latitude-r.center.latitude,2) + pow(a.longitude-r.center.longitude,2) < pow(b.latitude-r.center.latitude,2) + pow(b.longitude-r.center.longitude,2)
                }.prefix(36).map { station in
                    (station.id, ((try? db.supports(for: station.id)) ?? []).first(where: { $0.id == station.supportID })?.azimuths ?? [])
                })
                return (stations, directions)
            }.value
            guard request == token else { return }
            stations = result.0; directions = result.1; message = nil; loading = false
        } catch { if request == token { message = error.localizedDescription; loading = false } }
    }
    func importDatabase(_ url: URL) async {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let staging = URL.documentsDirectory.appendingPathComponent("import-\(UUID().uuidString).sqlite")
            defer { try? FileManager.default.removeItem(at: staging) }
            try data.write(to: staging)
            let db = try AntennaDatabase(url: staging); try db.validate(requireEnriched: true)
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
    var heading: Double?
    var accuracy: Double?
    var status = ""
    override init() { super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyBest }
    func locate() {
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { status = "Localisation refusée. Tu peux l’activer dans Réglages." }
        else { manager.requestLocation(); if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() } }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { manager.requestLocation(); if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() } }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { coordinate = locations.last?.coordinate; accuracy = locations.last?.horizontalAccuracy; status = "" }
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) { heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : nil }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { status = "Position indisponible pour le moment." }
}
