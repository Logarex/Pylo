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
    func testECI() { XCTAssertEqual(Radio.enodeB(25601),100); XCTAssertEqual(Radio.sector(25601),1) }
}
