import XCTest
@testable import PyloCore
final class PyloCoreTests: XCTestCase {
    func testCSVQuotesAndNewlines() {
        var rows: [[String]] = []
        CSV.rows("id;name\r\n1;\"rue; de l’\"\"église\"\"\nParis\"\r\n") { rows.append($0) }
        XCTAssertEqual(rows, [["id","name"],["1","rue; de l’\"église\"\nParis"]])
    }
    func testDatabaseGroupingFiltersAndValidation() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let db = try AntennaDatabase(url: url, writable: true)
        try db.prepareImport()
        for system in ["LTE 700", "LTE 700", "5G NR 3500"] {
            try db.insert(id: "001", operatorName: "L’OPÉRATEUR", lat: 48, lon: 2, address: "Rue de l’église", system: system, status: "En service", updated: "2026-10-29")
        }
        try db.finishImport(); try db.validate()
        let stations = try db.stations(generation: "5G", operatorName: "L’OPÉRATEUR")
        XCTAssertEqual(stations.count, 1)
        XCTAssertEqual(stations.first?.systems, "LTE 700 · 5G NR 3500")
        XCTAssertTrue(try db.stations(south: 49, north: 50).isEmpty)
        XCTAssertTrue(try db.stations(generation: "3G").isEmpty)
    }
    func testEnrichedStatisticsAndSnapshotComparison() throws {
        let previous = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let current = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: previous); try? FileManager.default.removeItem(at: current) }
        let old = try AntennaDatabase(url: previous, writable: true); try old.prepareImport()
        try old.insert(id: "old", operatorName: "FREE MOBILE", lat: 48, lon: 2, address: "", system: "LTE 700", status: "En service", updated: "2026-09-30", supportID: "1")
        try old.finishImport()
        let db = try AntennaDatabase(url: current, writable: true); try db.prepareImport()
        for system in ["GSM 900", "LTE 700", "5G NR 700"] {
            try db.insert(id: "new", operatorName: "ORANGE", lat: 48, lon: 2, address: "", system: system, status: "En service", updated: "2026-10-29", supportID: "2", height: "30", deployment: "2026-10-01", azimuths: "0|120|240")
        }
        try db.finishImport(); try db.recordComparison(previous: previous)
        let stats = try db.statistics()
        XCTAssertEqual(stats.stationCount, 1); XCTAssertEqual(stats.supportCount, 1); XCTAssertEqual(stats.systemCount, 3)
        XCTAssertEqual(stats.generations.map(\.label), ["2G","4G","5G"])
        XCTAssertEqual(stats.frequencies.first?.count, 2)
        XCTAssertEqual(stats.additions, 1); XCTAssertEqual(stats.removals, 1)
        XCTAssertEqual(stats.deployments.last?.label, "2026-10")
        XCTAssertEqual(stats.deployments.last?.count, 3)
        XCTAssertEqual(try db.stations(generation: "2G").count, 1)
        XCTAssertEqual(try db.systems(for: "new").first?.azimuths, [0,120,240])
        XCTAssertNil(try db.statistics(operatorName: "ORANGE").additions)
        XCTAssertEqual(try db.statistics(operatorName: "FREE MOBILE").stationCount, 0)
    }
    func testMultipleSupportsPreserveAllDirections() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let db = try AntennaDatabase(url: url, writable: true); try db.prepareImport()
        for (support,directions) in [("a","280"),("b","140|220")] {
            try db.insert(id: "station", operatorName: "SFR", lat: 48, lon: 2, address: "", system: "LTE 700", status: "En service", updated: "2026-10-29", supportID: support, deployment: "2026-10-01", azimuths: directions)
        }
        try db.finishImport()
        XCTAssertEqual(try db.systems(for: "station").first?.azimuths, [140,220,280])
        XCTAssertEqual(try db.supports(for: "station").count, 2)
        XCTAssertEqual(try db.primaryDirections(for: ["station"])["station"], [280])
        XCTAssertTrue(try db.primaryDirections(for: ["unknown' OR 1=1 --"]).isEmpty)
        XCTAssertTrue(try db.primaryDirections(for: []).isEmpty)
        XCTAssertEqual(try db.statistics().supportCount, 2)
        XCTAssertEqual(try db.statistics().systemCount, 1)
    }
    func testBearingAndAngularWrap() {
        XCTAssertEqual(Geometry.bearing(lat1: 0, lon1: 0, lat2: 1, lon2: 0), 0, accuracy: 0.01)
        XCTAssertEqual(Geometry.bearing(lat1: 0, lon1: 0, lat2: 0, lon2: 1), 90, accuracy: 0.01)
        XCTAssertEqual(Geometry.angularDifference(350, 10), 20)
        XCTAssertNil(Geometry.freeSpaceLoss(distanceKM: 0, frequencyMHz: 700))
    }
    func testOrientationBudgetAndNearestStations() {
        func station(_ index: Int) -> Station {
            Station(id: String(index), operatorName: "SFR", latitude: 48 + Double(index)*0.001, longitude: 2, address: "", systems: "LTE 700", status: "En service", updated: "", supportID: "", height: "")
        }
        let stations = (0..<100).reversed().map(station)
        let directions = Dictionary(uniqueKeysWithValues: stations.map { ($0.id, [0.0,60,120,180,240,300,360,Double.nan]) })
        let plan = OrientationPlan.make(stations: stations, directions: directions, latitude: 48, longitude: 2)
        XCTAssertEqual(plan.count, OrientationPlan.maximumArrows)
        XCTAssertEqual(plan.first?.stationID, "0")
        XCTAssertLessThanOrEqual(Set(plan.map(\.stationID)).count, OrientationPlan.maximumStations)
        XCTAssertTrue(plan.allSatisfy { $0.azimuth.isFinite && (0..<360).contains($0.azimuth) })
        let repeated = OrientationPlan.make(stations: [station(0)], directions: ["0": [90,90,90]], latitude: 48, longitude: 2)
        XCTAssertEqual(repeated.count, 1)
        XCTAssertTrue(OrientationPlan.make(stations: stations, directions: [:], latitude: 48, longitude: 2).isEmpty)
    }
    func testFavoriteLookupOnlyReturnsRequestedIDs() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let db = try AntennaDatabase(url: url, writable: true); try db.prepareImport()
        for id in ["a", "b", "c'quoted"] {
            try db.insert(id: id, operatorName: "SFR", lat: 48, lon: 2, address: "", system: "LTE 700", status: "En service", updated: "2026-10-29")
        }
        try db.finishImport()
        XCTAssertEqual(try db.stations(ids: ["a", "c'quoted", "missing"]).map(\.id), ["a", "c'quoted"])
        XCTAssertTrue(try db.stations(ids: []).isEmpty)
        XCTAssertTrue(try db.stations(ids: ["unknown' OR 1=1 --"]).isEmpty)
        let many = Set((0..<505).map { "missing-\($0)" } + ["b"])
        XCTAssertEqual(try db.stations(ids: many).map(\.id), ["b"])
    }
    func testUpdateManifestAndAtomicInstall() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.sqlite"), archive = root.appendingPathComponent("antennas.sqlite.gz"), destination = root.appendingPathComponent("installed.sqlite")
        let db = try AntennaDatabase(url: source, writable: true); try db.prepareImport()
        try db.insert(id: "updated", operatorName: "SFR", lat: 48, lon: 2, address: "", system: "LTE 700", status: "En service", updated: "2026-10-29", supportID: "1")
        try db.finishImport()
        FileManager.default.createFile(atPath: archive.path, contents: nil)
        let file = try FileHandle(forWritingTo: archive)
        let gzip = Process(); gzip.executableURL = URL(fileURLWithPath: "/usr/bin/gzip"); gzip.arguments = ["-c",source.path]; gzip.standardOutput = file
        try gzip.run(); gzip.waitUntilExit(); try file.close(); XCTAssertEqual(gzip.terminationStatus, 0)
        let manifest = try DataManifest(sourceVersion: "test", sourceDate: "2026-10-29", url: URL(string: "https://github.com/Logarex/Pylo/releases/download/test/antennas.sqlite.gz")!, sha256: DataUpdates.digest(of: archive), compressedBytes: Data(contentsOf: archive).count, uncompressedBytes: Data(contentsOf: source).count)
        try Data("ancienne copie".utf8).write(to: destination)
        let wrong = DataManifest(sourceVersion: "test", sourceDate: "2026-10-29", url: manifest.url, sha256: String(repeating: "0", count: 64), compressedBytes: manifest.compressedBytes, uncompressedBytes: manifest.uncompressedBytes)
        XCTAssertThrowsError(try DataUpdates.installArchive(archive, manifest: wrong, at: destination))
        XCTAssertEqual(try String(contentsOf: destination, encoding: .utf8), "ancienne copie")
        try DataUpdates.installArchive(archive, manifest: manifest, at: destination)
        XCTAssertEqual(try AntennaDatabase(url: destination).stations(limit: 1).first?.id, "updated")
        let wrongDate = DataManifest(sourceVersion: "test", sourceDate: "2026-10-30", url: manifest.url, sha256: manifest.sha256, compressedBytes: manifest.compressedBytes, uncompressedBytes: manifest.uncompressedBytes)
        XCTAssertThrowsError(try DataUpdates.installArchive(archive, manifest: wrongDate, at: destination))
        XCTAssertEqual(try AntennaDatabase(url: destination).sourceDate(), "2026-10-29")
        let foreign = DataManifest(sourceVersion: "test", sourceDate: "2026-10-29", url: URL(string: "https://example.com/antennas.sqlite.gz")!, sha256: manifest.sha256, compressedBytes: manifest.compressedBytes, uncompressedBytes: manifest.uncompressedBytes)
        XCTAssertThrowsError(try foreign.validate())
        let unknown = DataManifest(sourceVersion: "test", sourceDate: "2026-10-29", url: manifest.url, sha256: "bad", compressedBytes: 0, uncompressedBytes: 0)
        XCTAssertThrowsError(try unknown.validate())
    }
    func testANFRAddressAndValues() {
        XCTAssertEqual(ANFRAddress.readable("r du château d’eau, 75001"), "Rue du château d’eau, 75001")
        XCTAssertEqual(ANFRAddress.readable("12 bis bd. Victor Hugo"), "12 bis Boulevard Victor Hugo")
        XCTAssertEqual(ANFRAddress.readable("rte de la Gare, chem rural"), "Route de la Gare, Chemin rural")
        XCTAssertEqual(ANFRAddress.readable("Résidence R, parc SNCF, R.D. 45"), "Résidence R, parc SNCF, R.D. 45")
        XCTAssertEqual(ANFRAddress.full("r de Paris, 75001",commune: "Paris"), "Rue de Paris, 75001 Paris")
        XCTAssertEqual(ANFRAddress.full("r de Paris, Paris, 75001",commune: "Paris"), "Rue de Paris, Paris, 75001")
        XCTAssertEqual(ANFRValues.azimuths("360|0|90|ND|-1|361|nan|90"), [0,90])
        XCTAssertTrue(ANFRValues.azimuths("ND").isEmpty)
        XCTAssertEqual(Radio.generation("UNKNOWN"), "Inconnue")
    }
    func testSourceRoundTripPreservesOriginalFields() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try AntennaDatabase(url: root,writable:true); try db.prepareImport()
        let refs = try JSONDecoder().decode(ANFRReferences.self,from: Data(#"{"date":"2026-10-31","natures":{"23":"Pylône"},"owners":{"4":"BOUYGUES"},"communes":{"75056":"Paris"},"sources":[]}"#.utf8))
        let row = ["id":"001", "sta_nm_anfr":"station", "sup_id":"support", "adm_lb_nom":"SFR", "emr_lb_systeme":"LTE 700", "generation":"4G", "emr_dt":"", "statut":"Projet approuvé", "list_azimut":"360|ND", "nat_id":"23", "tpo_id":"4", "com_cd_insee":"75056", "adr_lb_add1":"r de l’église", "adr_nm_cp":"75001", "sup_nm_haut":"17,3"]
        try db.appendSource(row,references:refs)
        var second = row; second["id"]="002"; second["emr_lb_systeme"]="UMTS 900"; second["generation"]="3G"
        try db.appendSource(second,references:refs)
        try db.insert(id:"station",operatorName:"SFR",lat:48,lon:2,address:"r de l’église, 75001",system:"LTE 700",status:"Projet approuvé",updated:"2026-10-29",commune:"Paris")
        try db.finishImport()
        let details = try XCTUnwrap(db.sourceDetails(for:"station").first)
        XCTAssertEqual(details.details.nature,"Pylône"); XCTAssertEqual(details.details.owner,"BOUYGUES")
        XCTAssertEqual(details.records.count,2)
        let original = try JSONDecoder().decode([[String:String]].self,from:Data(details.exportJSON.utf8))
        XCTAssertEqual(original,[row,second])
        XCTAssertEqual(try db.stations(ids:["station"]).first?.readableAddress,"Rue de l’église, 75001 Paris")
    }
    func testStationDatesJoinAndMissingValues() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try AntennaDatabase(url: root, writable: true); try db.prepareImport()
        try db.insert(id: "0010030350", operatorName: "SFR", lat: 48, lon: 2, address: "", system: "LTE 700", status: "", updated: "2026-10-29")
        try db.finishImport()
        XCTAssertNil(try db.stationDates(for: "0010030350"))
        let count = try db.importStationDates("STA_NM_ANFR;DTE_IMPLANTATION;DTE_MODIF;DTE_EN_SERVICE\n0010030350;04/09/2009;;01/07/2010\nother;01/01/2000;;\n", source: "octobre 2026")
        XCTAssertEqual(count, 1)
        let dates = try XCTUnwrap(db.stationDates(for: "0010030350"))
        XCTAssertEqual(dates.implantation, "2009-09-04")
        XCTAssertEqual(dates.modification, "")
        XCTAssertEqual(dates.service, "2010-07-01")
        XCTAssertEqual(dates.source, "octobre 2026")
        XCTAssertNil(try db.stationDates(for: "other"))
    }
    func testStatisticsIncludesEmptyMonthsAndMonthEndBoundary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try AntennaDatabase(url: root, writable: true); try db.prepareImport()
        try db.insert(id: "first", operatorName: "SFR", lat: 48, lon: 2, address: "", system: "LTE 700", status: "", updated: "2026-10-31", deployment: "2025-11-01")
        try db.insert(id: "second", operatorName: "FREE MOBILE", lat: 48, lon: 2, address: "", system: "LTE 700", status: "", updated: "2026-10-31", deployment: "2026-10-15")
        try db.finishImport()
        let stats = try db.statistics()
        XCTAssertEqual(stats.deployments.count, 12)
        XCTAssertEqual(stats.deployments.first?.label, "2025-11")
        XCTAssertEqual(stats.deployments.first?.count, 1)
        XCTAssertEqual(stats.deployments[1].count, 0)
        XCTAssertEqual(stats.deployments.last?.label, "2026-10")
        XCTAssertEqual(stats.deployments.last?.count, 1)
        let filtered = try db.statistics(operatorName: "SFR")
        XCTAssertEqual(filtered.stationCount, 1)
        XCTAssertEqual(filtered.deployments.last?.count, 0)
        XCTAssertEqual(try db.sourceDate(), "2026-10-31")
    }
    func testSavedViewportRejectsInvalidCoordinatesAndZoom() {
        let paris = [48.85, 2.35, 0.04, 0.06]
        XCTAssertEqual(MapViewport(values: paris)?.values, paris)
        XCTAssertNil(MapViewport(values: []))
        XCTAssertNil(MapViewport(values: [91, 2, 1, 1]))
        XCTAssertNil(MapViewport(values: [48, 181, 1, 1]))
        XCTAssertNil(MapViewport(values: [48, 2, 0, 1]))
        XCTAssertNil(MapViewport(values: [48, 2, 1, 361]))
        XCTAssertNil(MapViewport(values: [Double.nan, 2, 1, 1]))
    }
    func testECI() { XCTAssertEqual(Radio.enodeB(25601),100); XCTAssertEqual(Radio.sector(25601),1) }
    func testChangeReportDetectsAddedRemovedAndModifiedStations() throws {
        let previous = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let current = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: previous); try? FileManager.default.removeItem(at: current) }
        let old = try AntennaDatabase(url: previous, writable: true); try old.prepareImport()
        try old.insert(id: "kept", operatorName: "ORANGE", lat: 45.76, lon: 4.83, address: "", system: "LTE 800", status: "Projet approuvé", updated: "2026-10-01", supportID: "1", height: "30", azimuths: "0|120")
        try old.insert(id: "kept", operatorName: "ORANGE", lat: 45.76, lon: 4.83, address: "", system: "UMTS 900", status: "En service", updated: "2026-10-01", supportID: "1", height: "30", azimuths: "0|120")
        try old.insert(id: "same", operatorName: "SFR", lat: 45, lon: 4, address: "", system: "LTE 700", status: "En service", updated: "2026-10-01", supportID: "2", azimuths: "240|0")
        try old.insert(id: "gone", operatorName: "SFR", lat: 45, lon: 4, address: "", system: "GSM 900", status: "En service", updated: "2026-10-01")
        try old.finishImport()
        let db = try AntennaDatabase(url: current, writable: true); try db.prepareImport()
        try db.insert(id: "kept", operatorName: "ORANGE", lat: 45.76, lon: 4.83, address: "", system: "LTE 800", status: "En service", updated: "2026-11-05", supportID: "1", height: "30,0", azimuths: "0|120")
        try db.insert(id: "kept", operatorName: "ORANGE", lat: 45.76, lon: 4.83, address: "", system: "5G NR 3500", status: "En service", updated: "2026-11-05", supportID: "1", height: "30", azimuths: "0|120")
        try db.insert(id: "same", operatorName: "SFR", lat: 45, lon: 4, address: "", system: "LTE 700", status: "En service", updated: "2026-11-05", supportID: "2", azimuths: "0|240")
        try db.insert(id: "new", operatorName: "FREE MOBILE", lat: 45.77, lon: 4.84, address: "12 r de la République", system: "5G NR 3500", status: "En service", updated: "2026-11-05", commune: "Lyon")
        try db.finishImport()
        let report = try XCTUnwrap(db.changeReport(since: previous))
        XCTAssertEqual(report.changes.map(\.id), ["gone", "kept", "new"])
        XCTAssertEqual([report.added, report.removed, report.modified], [1, 1, 1])
        let kept = try XCTUnwrap(report.changes.first { $0.id == "kept" })
        XCTAssertEqual(kept.addedSystems, ["5G NR 3500"]); XCTAssertEqual(kept.removedSystems, ["UMTS 900"])
        XCTAssertEqual(kept.statusChanges, [.init(system: "LTE 800", from: "Projet approuvé", to: "En service")])
        XCTAssertEqual(kept.details, [], "Même hauteur écrite autrement et mêmes azimuts : pas de faux changement")
        XCTAssertEqual(AlertDigest.summary(kept), "5G 3500 MHz ajoutée, 3G 900 MHz retirée, 4G 800 MHz mise en service")

        let lyon = AlertZone(name: "Lyon", latitude: 45.76, longitude: 4.83, newAntennasKM: 5)
        let result = AlertDigest.messages(sourceDate: report.sourceDate, report: report, preferences: AlertPreferences(data: true, zones: [lyon], favorites: ["kept", "gone"]))
        XCTAssertEqual(result.messages.map(\.category), [.data, .favorites, .zone])
        XCTAssertEqual(result.messages[0].body, "Publication du 5 novembre 2026 : 1 station ajoutée, 1 retirée et 1 modifiée en France.\nOuvre Pylo en Wi-Fi pour récupérer la nouvelle base.")
        XCTAssertEqual(result.messages[1].title, "2 stations favorites ont changé")
        XCTAssertEqual(result.messages[2].title, "Nouvelle antenne · Lyon")
        XCTAssertEqual(result.messages[2].body, "Free Mobile, à 1,4 km du centre\n12 Rue de la République, Lyon\nNouvelle station en 5G 3500 MHz.")
        XCTAssertEqual(result.history.items.map(\.category), [.favorites, .favorites, .zone])
        XCTAssertTrue(result.history.items[0].removed)

        // Changes radius only: the modified station is reported, the new one is not.
        let watch = AlertZone(name: "Travail", latitude: 45.76, longitude: 4.83, newAntennasKM: nil, changesKM: 1)
        let changed = AlertDigest.messages(sourceDate: report.sourceDate, report: report, preferences: AlertPreferences(data: false, zones: [watch], favorites: []))
        XCTAssertEqual(changed.messages.map(\.title), ["Antenne modifiée · Travail"])
        XCTAssertTrue(changed.messages[0].body.hasSuffix("5G 3500 MHz ajoutée, 3G 900 MHz retirée, 4G 800 MHz mise en service."), changed.messages[0].body)

        // Two zones: a new frequency on an existing station counts as a new antenna, and each line names its zone.
        let both = AlertDigest.messages(sourceDate: report.sourceDate, report: report, preferences: AlertPreferences(data: false, zones: [lyon, AlertZone(name: "Bureau", latitude: 45.77, longitude: 4.84, newAntennasKM: 1, changesKM: 5)], favorites: []))
        XCTAssertEqual(both.messages.map(\.title), ["2 nouvelles antennes dans tes zones"])
        XCTAssertEqual(both.messages[0].body, "• Orange (10 m de Lyon) : nouvelle fréquence : 5G 3500 MHz\n• Free Mobile, Lyon (10 m de Bureau) : nouvelle station en 5G 3500 MHz")

        let quiet = AlertDigest.messages(sourceDate: report.sourceDate, report: report, preferences: AlertPreferences(data: true, zones: [AlertZone(name: "Paris", latitude: 48.85, longitude: 2.35, newAntennasKM: 2, changesKM: 2)], favorites: []))
        XCTAssertEqual(quiet.messages.map(\.category), [.data])
    }
    func testManifestChangesMustStayInTheSameRelease() throws {
        let url = URL(string: "https://github.com/Logarex/Pylo/releases/download/anfr-1/antennas.sqlite.gz")!
        let sha = String(repeating: "a", count: 64)
        let ok = DataManifest(sourceVersion: "v", sourceDate: "2026-11-05", url: url, sha256: sha, compressedBytes: 1, uncompressedBytes: 1, changes: ChangeFile(url: URL(string: "https://github.com/Logarex/Pylo/releases/download/anfr-1/changes.json")!, sha256: sha, bytes: 10))
        XCTAssertNoThrow(try ok.validate())
        let other = DataManifest(sourceVersion: "v", sourceDate: "2026-11-05", url: url, sha256: sha, compressedBytes: 1, uncompressedBytes: 1, changes: ChangeFile(url: URL(string: "https://github.com/Logarex/Pylo/releases/download/anfr-0/changes.json")!, sha256: sha, bytes: 10))
        XCTAssertThrowsError(try other.validate())
        let legacy = try JSONDecoder().decode(DataManifest.self, from: Data(#"{"schemaVersion":2,"sourceVersion":"v","sourceDate":"2026-11-05","url":"\#(url.absoluteString)","sha256":"\#(sha)","compressedBytes":1,"uncompressedBytes":1}"#.utf8))
        XCTAssertNil(legacy.changes)
    }
    func testDistanceAndLabels() {
        XCTAssertEqual(AlertDigest.formatDistance(843), "840 m")
        XCTAssertEqual(AlertDigest.formatDistance(12_600), "13 km")
        XCTAssertEqual(Radio.label("5G NR 3500"), "5G 3500 MHz")
        XCTAssertEqual(Radio.label("GSM 900"), "2G 900 MHz")
        XCTAssertEqual(Radio.bands(["LTE 800", "5G NR 3500", "LTE 2600", "5G NR 700", "LTE 800"]), "5G 700 · 3500 MHz et 4G 800 · 2600 MHz")
    }
}
