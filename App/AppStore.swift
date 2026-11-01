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
    var region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 48.8566, longitude: 2.3522), span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)) {
        didSet {
            let values = [region.center.latitude, region.center.longitude, region.span.latitudeDelta, region.span.longitudeDelta]
            if MapViewport(values: values) != nil { UserDefaults.standard.set(values, forKey: "lastMapViewport") }
        }
    }
    private var request = UUID()
    @ObservationIgnored private var centeredPositionRevision = 0
    @ObservationIgnored private var pendingMapCenter = false
    static var localDatabase: URL { URL.documentsDirectory.appendingPathComponent("antennas.sqlite") }
    init() {
        automaticUpdates = UserDefaults.standard.object(forKey: "automaticDataUpdates") as? Bool ?? true
        installedDigest = UserDefaults.standard.string(forKey: "installedDataDigest") ?? ""
        lastDataCheck = UserDefaults.standard.object(forKey: "lastDataCheck") as? Date
        favorites = Set(UserDefaults.standard.stringArray(forKey: "favorites") ?? [])
        if let values = UserDefaults.standard.array(forKey: "lastMapViewport") as? [Double], let saved = MapViewport(values: values) {
            region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: saved.values[0], longitude: saved.values[1]), span: MKCoordinateSpan(latitudeDelta: saved.values[2], longitudeDelta: saved.values[3]))
        }

    }
    var databaseURL: URL? {
        FileManager.default.fileExists(atPath: Self.localDatabase.path) ? Self.localDatabase : (FileManager.default.fileExists(atPath: Self.bundledDatabase.path) ? Self.bundledDatabase : nil)
    }
    static var bundledDatabase: URL { URL.cachesDirectory.appendingPathComponent("anfr-v2-2.sqlite") }
    func prepare() async {
        guard !ready else { return }
        do {
            if !FileManager.default.fileExists(atPath: Self.localDatabase.path), !FileManager.default.fileExists(atPath: Self.bundledDatabase.path), let source = Bundle.main.url(forResource: "antennas.sqlite", withExtension: "gz") {
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
    func locateOnMap() {
        pendingMapCenter = true
        location.locate()
    }
    func cancelAutomaticCentering() { pendingMapCenter = false }
    func newLocationRegion() -> MKCoordinateRegion? {
        guard pendingMapCenter, location.positionRevision > centeredPositionRevision,
              let coordinate = location.coordinate, let measuredAt = location.measuredAt,
              (-5...60).contains(Date().timeIntervalSince(measuredAt)) else { return nil }
        centeredPositionRevision = location.positionRevision
        pendingMapCenter = false
        return MKCoordinateRegion(center: coordinate, span: region.span)
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
        isUpdating = true
        defer { isUpdating = false }
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let destination = Self.localDatabase
            let date = try await Task.detached(priority: .userInitiated) {
                let fm = FileManager.default
                let staging = destination.deletingLastPathComponent().appendingPathComponent("import-\(UUID().uuidString).sqlite")
                defer { try? fm.removeItem(at: staging) }
                if url.pathExtension.lowercased() == "gz" { try AntennaDatabase.unpack(source: url, destination: staging) }
                else { try fm.copyItem(at: url, to: staging) }
                let db = try AntennaDatabase(url: staging); try db.validate(requireEnriched: true)
                let date = try db.sourceDate()
                if fm.fileExists(atPath: destination.path) { _ = try fm.replaceItemAt(destination, withItemAt: staging) }
                else { try fm.moveItem(at: staging, to: destination) }
                return date
            }.value
            installedDigest = ""; UserDefaults.standard.removeObject(forKey: "installedDataDigest")
            dataSourceDate = date
            databaseRevision += 1
            updateStatus = "Base importée et prête à être utilisée."
            await load()
        } catch { message = "Import impossible : \(error.localizedDescription)" }
    }

    @ObservationIgnored private var statisticsRevision = -1
    @ObservationIgnored private var statisticsCache: [String: NetworkStatistics] = [:]
    @ObservationIgnored private var statisticsTasks: [String: Task<NetworkStatistics, Error>] = [:]
    func networkStatistics(operatorName: String) async throws -> NetworkStatistics {
        guard let url = databaseURL else { throw DatabaseError.sqlite("Base ANFR indisponible.") }
        if statisticsRevision != databaseRevision {
            statisticsCache.removeAll()
            statisticsTasks.removeAll()
            statisticsRevision = databaseRevision
        }
        if let cached = statisticsCache[operatorName] { return cached }
        if let task = statisticsTasks[operatorName] { return try await task.value }
        let revision = databaseRevision
        let task = Task.detached(priority: .userInitiated) { try AntennaDatabase(url: url).statistics(operatorName: operatorName) }
        statisticsTasks[operatorName] = task
        do {
            let value = try await task.value
            if revision == databaseRevision {
                statisticsCache[operatorName] = value
                statisticsTasks.removeValue(forKey: operatorName)
            }
            return value
        } catch {
            if revision == databaseRevision { statisticsTasks.removeValue(forKey: operatorName) }
            throw error
        }
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
    private var requested = false
    var positionRevision = 0
    var coordinate: CLLocationCoordinate2D?
    var heading: Double?
    var headingAccuracy: Double?
    var headingReference = "nord vrai"
    var accuracy: Double?
    var altitude: Double?
    var verticalAccuracy: Double?
    var speed: Double?
    var course: Double?
    var measuredAt: Date?
    var precisePosition: Bool?
    var permission = "Non demandée"
    var status = ""
    override init() {
        super.init(); manager.delegate = self; manager.desiredAccuracy = kCLLocationAccuracyBest; manager.headingFilter = 5
        updatePermission()
    }
    private func updatePermission() {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse: permission = "Autorisée pendant l’utilisation"; precisePosition = manager.accuracyAuthorization == .fullAccuracy
        case .authorizedAlways: permission = "Toujours autorisée par iOS"; precisePosition = manager.accuracyAuthorization == .fullAccuracy
        case .denied: permission = "Refusée"; precisePosition = nil
        case .restricted: permission = "Limitée par iOS"; precisePosition = nil
        default: permission = "Non demandée"; precisePosition = nil
        }
    }
    func locate() {
        requested = true; updatePermission()
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { status = "Localisation refusée. Tu peux l’activer dans Réglages." }
        else { resumeIfNeeded() }
    }
    func resumeIfNeeded() {
        updatePermission()
        guard requested, manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways else { return }
        manager.requestLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }
    func suspend() { manager.stopUpdatingHeading() }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updatePermission()
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            coordinate = nil; heading = nil; accuracy = nil; altitude = nil; speed = nil; course = nil; measuredAt = nil
            suspend()
        }
        resumeIfNeeded()
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let fix = locations.last, fix.horizontalAccuracy >= 0 else { status = "Position non fiable. Réessaie dans un endroit plus dégagé."; return }
        coordinate = fix.coordinate; accuracy = fix.horizontalAccuracy; measuredAt = fix.timestamp
        altitude = fix.verticalAccuracy >= 0 ? fix.altitude : nil
        verticalAccuracy = fix.verticalAccuracy >= 0 ? fix.verticalAccuracy : nil
        speed = fix.speed >= 0 ? fix.speed * 3.6 : nil
        course = fix.course >= 0 && fix.speed >= 0.5 ? fix.course : nil
        let age = Date().timeIntervalSince(fix.timestamp)
        status = age > 60 ? "Cette position est ancienne ; actualise-la pour une distance plus fiable." : ""
        if age <= 60 && age >= -5 { positionRevision += 1 }
        updatePermission()
    }
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { heading = nil; headingAccuracy = nil; return }
        heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        headingReference = newHeading.trueHeading >= 0 ? "nord vrai" : "nord magnétique"
        headingAccuracy = newHeading.headingAccuracy
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { status = "Position indisponible pour le moment." }
}
