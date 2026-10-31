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
    var databaseRevision = 0
    var isUpdating = false
    var updateStatus = "Les mises à jour se font automatiquement en Wi-Fi."
    var dataSourceDate = ""
    var lastDataCheck: Date?
    var automaticUpdates: Bool { didSet { UserDefaults.standard.set(automaticUpdates, forKey: "automaticDataUpdates") } }
    @ObservationIgnored private var installedDigest: String
    @ObservationIgnored private var lastUpdateAttempt: Date?
    var generation = ""
    var operatorName = ""
    var favorites: Set<String> { didSet { UserDefaults.standard.set(Array(favorites), forKey: "favorites") } }
    let location = LocationService()
    let device = DeviceNetworkInfo()
    var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522), span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06))
    private var request = UUID()
    static var localDatabase: URL { URL.documentsDirectory.appendingPathComponent("antennas.sqlite") }
    init() {
        automaticUpdates = UserDefaults.standard.object(forKey: "automaticDataUpdates") as? Bool ?? true
        installedDigest = UserDefaults.standard.string(forKey: "installedDataDigest") ?? ""
        lastDataCheck = UserDefaults.standard.object(forKey: "lastDataCheck") as? Date
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
            if let url = databaseURL {
                dataSourceDate = (try? await Task.detached { try AntennaDatabase(url: url).sourceDate() }.value) ?? ""
            }
            if installedDigest.isEmpty, !FileManager.default.fileExists(atPath: Self.localDatabase.path), let bundled = Bundle.main.url(forResource: "antennas.sqlite", withExtension: "gz") {
                installedDigest = (try? await Task.detached { try DataUpdates.digest(of: bundled) }.value) ?? ""
                UserDefaults.standard.set(installedDigest, forKey: "installedDataDigest")
            }
            ready = true
        } catch { message = error.localizedDescription; ready = true }
    }
    func checkDataUpdates(automatic: Bool = false) async {
        guard ready, !isUpdating else { return }
        if automatic {
            guard automaticUpdates, device.connection == "Wi-Fi", device.constrained != true else { return }
            if let lastDataCheck, Date().timeIntervalSince(lastDataCheck) < 86400 { return }
            if let lastUpdateAttempt, Date().timeIntervalSince(lastUpdateAttempt) < 900 { return }
        }
        lastUpdateAttempt = Date(); isUpdating = true
        defer { isUpdating = false }
        updateStatus = "Vérification des dernières données ANFR…"
        do {
            let manifest = try await DataUpdates.fetchManifest()
            if manifest.sourceDate < dataSourceDate || manifest.sha256 == installedDigest {
                updateStatus = "Ta base est à jour."
                lastDataCheck = Date(); UserDefaults.standard.set(lastDataCheck, forKey: "lastDataCheck")
                return
            }
            guard device.connection == "Wi-Fi", device.constrained != true else {
                updateStatus = "Une mise à jour est disponible. Elle sera téléchargée en Wi-Fi, hors mode données réduites."
                return
            }
            updateStatus = "Téléchargement de la base · environ \(manifest.compressedBytes / 1_000_000) Mo…"
            try await DataUpdates.install(manifest, at: Self.localDatabase)
            installedDigest = manifest.sha256; dataSourceDate = manifest.sourceDate
            UserDefaults.standard.set(installedDigest, forKey: "installedDataDigest")
            lastDataCheck = Date(); UserDefaults.standard.set(lastDataCheck, forKey: "lastDataCheck")
            databaseRevision += 1
            updateStatus = "Mise à jour installée. Les antennes sont prêtes."
            await load()
        } catch {
            updateStatus = "La mise à jour n’a pas pu aboutir. Ta base actuelle reste disponible. Réessaie plus tard."
        }
    }
    func load() async {
        guard let url = databaseURL else { message = "Ajoute une base ANFR dans l’onglet Données."; return }
        let token = UUID(); request = token; loading = true
        let r = region, g = generation, op = operatorName
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                let db = try AntennaDatabase(url: url)
                let stations = try db.stations(south: r.center.latitude-r.span.latitudeDelta/2, north: r.center.latitude+r.span.latitudeDelta/2, west: r.center.longitude-r.span.longitudeDelta/2, east: r.center.longitude+r.span.longitudeDelta/2, generation: g, operatorName: op)
                let directions = (try? db.primaryDirections(for: stations.map(\.id))) ?? [:]
                return (stations, directions)
            }.value
            guard request == token else { return }
            stations = result.0; directions = result.1; message = nil; loading = false
        } catch { if request == token { message = error.localizedDescription; loading = false } }
    }
    func importDatabase(_ url: URL) async {
        guard !isUpdating else { return }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let staging = URL.documentsDirectory.appendingPathComponent("import-\(UUID().uuidString).sqlite")
            defer { try? FileManager.default.removeItem(at: staging) }
            try data.write(to: staging)
            let db = try AntennaDatabase(url: staging); try db.validate(requireEnriched: true)
            try data.write(to: Self.localDatabase, options: .atomic)
            installedDigest = ""; UserDefaults.standard.removeObject(forKey: "installedDataDigest")
            dataSourceDate = (try? db.sourceDate()) ?? ""
            databaseRevision += 1
            await load()
        } catch { message = "Import impossible : \(error.localizedDescription)" }
    }
    func toggle(_ station: Station) { if !favorites.insert(station.id).inserted { favorites.remove(station.id) } }
    func savedStations(ids: Set<String>) async throws -> [Station] {
        guard !ids.isEmpty else { return [] }
        guard let url = databaseURL else { throw DatabaseError.sqlite("Base ANFR indisponible.") }
        return try await Task.detached(priority: .userInitiated) {
            try AntennaDatabase(url: url).stations(ids: ids)
        }.value
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
