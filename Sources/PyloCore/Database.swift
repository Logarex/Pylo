import Foundation
import CSQLite
public enum DatabaseError: Error, LocalizedError {
    case sqlite(String)
    public var errorDescription: String? { if case .sqlite(let s) = self { return s }; return nil }
}
public final class AntennaDatabase {
    private var db: OpaquePointer?
    public init(url: URL, writable: Bool = false) throws {
        let flags = writable ? SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE : SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK else { throw DatabaseError.sqlite("Impossible d’ouvrir la base ANFR.") }
    }
    deinit { sqlite3_close(db) }
    public func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw DatabaseError.sqlite(String(cString: sqlite3_errmsg(db))) }
    }
    private func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "''") + "'" }
    public func prepareImport() throws {
        try execute("PRAGMA journal_mode=DELETE; CREATE TABLE stations(id TEXT PRIMARY KEY, operatorName TEXT, latitude REAL, longitude REAL, address TEXT, systems TEXT, status TEXT, updated TEXT); BEGIN TRANSACTION;")
    }
    public func insert(id: String, operatorName: String, lat: Double, lon: Double, address: String, system: String, status: String, updated: String) throws {
        try execute("INSERT INTO stations VALUES(\(quote(id)),\(quote(operatorName)),\(lat),\(lon),\(quote(address)),\(quote(system)),\(quote(status)),\(quote(updated))) ON CONFLICT(id) DO UPDATE SET systems=CASE WHEN instr(stations.systems, excluded.systems)=0 THEN stations.systems || ' · ' || excluded.systems ELSE stations.systems END, status=CASE WHEN instr(stations.status, excluded.status)=0 THEN stations.status || ' · ' || excluded.status ELSE stations.status END;")
    }
    public func finishImport() throws { try execute("COMMIT; CREATE INDEX coordinates ON stations(latitude,longitude); PRAGMA user_version=1; VACUUM;") }
    public func stations(south: Double = -90, north: Double = 90, west: Double = -180, east: Double = 180, generation: String = "", operatorName: String = "", limit: Int = 600) throws -> [Station] {
        let sql = "SELECT * FROM stations WHERE latitude BETWEEN \(south) AND \(north) AND longitude BETWEEN \(west) AND \(east) \(operatorName.isEmpty ? "" : "AND operatorName=" + quote(operatorName)) \(generation.isEmpty ? "" : "AND systems LIKE " + quote("%" + (generation == "5G" ? "5G" : generation == "4G" ? "LTE" : "UMTS") + "%")) ORDER BY id LIMIT \(max(1, min(limit, 200000)))"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw DatabaseError.sqlite("Format de base non reconnu.") }
        defer { sqlite3_finalize(stmt) }
        func string(_ col: Int32) -> String { sqlite3_column_text(stmt, col).map { String(cString: $0) } ?? "" }
        var result: [Station] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let systems = string(5)
            if !generation.isEmpty && !systems.components(separatedBy: " · ").contains(where: { Radio.generation($0) == generation }) { continue }
            result.append(Station(id: string(0), operatorName: string(1), latitude: sqlite3_column_double(stmt,2), longitude: sqlite3_column_double(stmt,3), address: string(4), systems: systems, status: string(6), updated: string(7)))
        }
        return result
    }
    public func validate() throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA quick_check", -1, &stmt, nil) == SQLITE_OK else { throw DatabaseError.sqlite("Base invalide.") }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, String(cString: sqlite3_column_text(stmt,0)) == "ok", !(try stations(limit: 1)).isEmpty else { throw DatabaseError.sqlite("Base vide ou endommagée.") }
    }
}
