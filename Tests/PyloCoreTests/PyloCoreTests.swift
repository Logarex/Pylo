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
        XCTAssertEqual(stats.deployments.first?.label, "2026-10")
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
    func testECI() { XCTAssertEqual(Radio.enodeB(25601),100); XCTAssertEqual(Radio.sector(25601),1) }
}
