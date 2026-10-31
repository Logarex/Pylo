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
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK else { sqlite3_close(db); db = nil; throw DatabaseError.sqlite("Impossible d’ouvrir la base ANFR.") }
    }
    deinit { sqlite3_close(db) }
    public func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw DatabaseError.sqlite(String(cString: sqlite3_errmsg(db))) }
    }
    private func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "''") + "'" }
    public func prepareImport() throws {
        try execute("PRAGMA journal_mode=DELETE; CREATE TABLE stations(id TEXT PRIMARY KEY, operatorName TEXT, latitude REAL, longitude REAL, address TEXT, systems TEXT, status TEXT, updated TEXT, supportID TEXT, height TEXT); CREATE TABLE systems(stationID TEXT, name TEXT, generation TEXT, frequency TEXT, status TEXT, deployment TEXT, azimuths TEXT, PRIMARY KEY(stationID,name)); CREATE TABLE supports(stationID TEXT, supportID TEXT, height TEXT, latitude REAL, longitude REAL, azimuths TEXT, PRIMARY KEY(stationID,supportID)); CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT); BEGIN TRANSACTION;")
    }
    public func insert(id: String, operatorName: String, lat: Double, lon: Double, address: String, system: String, status: String, updated: String, supportID: String = "", height: String = "", deployment: String = "", azimuths: String = "") throws {
        try execute("INSERT INTO stations VALUES(\(quote(id)),\(quote(operatorName)),\(lat),\(lon),\(quote(address)),\(quote(system)),\(quote(status)),\(quote(updated)),\(quote(supportID)),\(quote(height))) ON CONFLICT(id) DO UPDATE SET systems=CASE WHEN instr(stations.systems, excluded.systems)=0 THEN stations.systems || ' · ' || excluded.systems ELSE stations.systems END, status=CASE WHEN instr(stations.status, excluded.status)=0 THEN stations.status || ' · ' || excluded.status ELSE stations.status END;")
        let frequency = system.split(separator: " ").last.map(String.init) ?? "Inconnue"
        try execute("INSERT INTO systems VALUES(\(quote(id)),\(quote(system)),\(quote(Radio.generation(system))),\(quote(frequency)),\(quote(status)),\(quote(deployment)),\(quote(azimuths))) ON CONFLICT(stationID,name) DO UPDATE SET azimuths=systems.azimuths || '|' || excluded.azimuths, status=CASE WHEN instr(systems.status,excluded.status)=0 THEN systems.status || ' · ' || excluded.status ELSE systems.status END, deployment=CASE WHEN systems.deployment='' THEN excluded.deployment WHEN excluded.deployment='' THEN systems.deployment ELSE min(systems.deployment,excluded.deployment) END;")
        try execute("INSERT INTO supports VALUES(\(quote(id)),\(quote(supportID)),\(quote(height)),\(lat),\(lon),\(quote(azimuths))) ON CONFLICT(stationID,supportID) DO UPDATE SET azimuths=CASE WHEN instr(supports.azimuths,excluded.azimuths)=0 THEN supports.azimuths || '|' || excluded.azimuths ELSE supports.azimuths END;")
    }
    public func finishImport() throws { try execute("COMMIT; CREATE INDEX coordinates ON stations(latitude,longitude); CREATE INDEX system_station ON systems(stationID); PRAGMA user_version=2; VACUUM;") }
    public func stations(south: Double = -90, north: Double = 90, west: Double = -180, east: Double = 180, generation: String = "", operatorName: String = "", limit: Int = 600) throws -> [Station] {
        let sql = "SELECT * FROM stations WHERE latitude BETWEEN \(south) AND \(north) AND longitude BETWEEN \(west) AND \(east) \(operatorName.isEmpty ? "" : "AND operatorName=" + quote(operatorName)) \(generation.isEmpty ? "" : "AND systems LIKE " + quote("%" + (generation == "5G" ? "5G" : generation == "4G" ? "LTE" : generation == "3G" ? "UMTS" : "GSM") + "%")) ORDER BY id LIMIT \(max(1, min(limit, 200000)))"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw DatabaseError.sqlite("Format de base non reconnu.") }
        defer { sqlite3_finalize(stmt) }
        func string(_ col: Int32) -> String { sqlite3_column_text(stmt, col).map { String(cString: $0) } ?? "" }
        var result: [Station] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let systems = string(5)
            if !generation.isEmpty && !systems.components(separatedBy: " · ").contains(where: { Radio.generation($0) == generation }) { continue }
            result.append(Station(id: string(0), operatorName: string(1), latitude: sqlite3_column_double(stmt,2), longitude: sqlite3_column_double(stmt,3), address: string(4), systems: systems, status: string(6), updated: string(7), supportID: sqlite3_column_count(stmt) > 8 ? string(8) : "", height: sqlite3_column_count(stmt) > 9 ? string(9) : ""))
        }
        return result
    }
    private func rows(_ sql: String) throws -> [[String]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw DatabaseError.sqlite("Cette base doit être mise à jour pour afficher ces informations.") }
        defer { sqlite3_finalize(stmt) }
        var result: [[String]] = []
        var status = sqlite3_step(stmt)
        while status == SQLITE_ROW {
            result.append((0..<sqlite3_column_count(stmt)).map { sqlite3_column_text(stmt,$0).map { String(cString: $0) } ?? "" })
            status = sqlite3_step(stmt)
        }
        guard status == SQLITE_DONE else { throw DatabaseError.sqlite("Lecture interrompue.") }
        return result
    }
    public func systems(for id: String) throws -> [RadioSystem] {
        try rows("SELECT name,status,deployment,azimuths FROM systems WHERE stationID=\(quote(id)) ORDER BY generation,name").map {
            RadioSystem(name: $0[0], status: $0[1], date: $0[2], azimuths: Array(Set($0[3].split(separator: "|").compactMap { Double($0) }.filter { (0..<360).contains($0) })).sorted())
        }
    }
    public func supports(for id: String) throws -> [AntennaSupport] {
        try rows("SELECT supportID,height,latitude,longitude,azimuths FROM supports WHERE stationID=\(quote(id)) ORDER BY supportID").map {
            AntennaSupport(id: $0[0], height: $0[1], latitude: Double($0[2]) ?? 0, longitude: Double($0[3]) ?? 0, azimuths: Array(Set($0[4].split(separator: "|").compactMap { Double($0) }.filter { (0..<360).contains($0) })).sorted())
        }
    }
    public func primaryDirections(for stationIDs: [String]) throws -> [String: [Double]] {
        guard !stationIDs.isEmpty else { return [:] }
        let ids = stationIDs.prefix(600).map(quote).joined(separator: ",")
        return Dictionary(uniqueKeysWithValues: try rows("SELECT p.stationID,p.azimuths FROM supports p JOIN stations s ON p.stationID=s.id AND p.supportID=s.supportID WHERE s.id IN (\(ids))").map { row in
            (row[0], Array(Set(row[1].split(separator: "|").compactMap { Double($0) }.filter { $0.isFinite && (0..<360).contains($0) })).sorted())
        })
    }
    public func recordComparison(previous: URL) throws {
        let old = try AntennaDatabase(url: previous)
        guard try old.rows("PRAGMA user_version").first?.first == "2" else { return }
        let before = Set(try old.rows("SELECT id FROM stations").compactMap(\.first))
        let after = Set(try rows("SELECT id FROM stations").compactMap(\.first))
        let date = try old.rows("SELECT max(substr(updated,1,10)) FROM stations").first?.first ?? ""
        for (key,value) in [("added", String(after.subtracting(before).count)), ("removed",String(before.subtracting(after).count)), ("previousDate", date)] {
            try execute("INSERT OR REPLACE INTO metadata VALUES(\(quote(key)),\(quote(value)))")
        }
    }
    public func statistics(operatorName: String = "") throws -> NetworkStatistics {
        let filter = operatorName.isEmpty ? "" : " WHERE operatorName=" + quote(operatorName)
        let joinFilter = operatorName.isEmpty ? "" : " AND stationID IN (SELECT id FROM stations WHERE operatorName=" + quote(operatorName) + ")"
        func count(_ sql: String) throws -> Int { Int(try rows(sql).first?.first ?? "0") ?? 0 }
        func items(_ sql: String) throws -> [StatItem] { try rows(sql).map { StatItem(label: $0[0], count: Int($0[1]) ?? 0) } }
        let meta = Dictionary(uniqueKeysWithValues: try rows("SELECT key,value FROM metadata").map { ($0[0],$0[1]) })
        let date = try rows("SELECT max(substr(updated,1,10)) FROM stations").first?.first ?? ""
        return try NetworkStatistics(
            stationCount: count("SELECT count(*) FROM stations" + filter),
            supportCount: count("SELECT count(DISTINCT NULLIF(supportID,'')) FROM supports WHERE 1=1" + joinFilter),
            systemCount: count("SELECT count(*) FROM systems WHERE 1=1" + joinFilter),
            sourceDate: date,
            operators: items("SELECT operatorName,count(*) FROM stations" + filter + " GROUP BY operatorName ORDER BY count(*) DESC"),
            generations: items("SELECT generation,count(DISTINCT stationID) FROM systems WHERE 1=1" + joinFilter + " GROUP BY generation ORDER BY generation"),
            frequencies: items("SELECT frequency,count(*) FROM systems WHERE 1=1" + joinFilter + " GROUP BY frequency ORDER BY CAST(frequency AS REAL)"),
            deployments: items("SELECT substr(deployment,1,7),count(*) FROM systems WHERE length(deployment)>=10 AND substr(deployment,1,7) >= strftime('%Y-%m'," + quote(date) + ",'-11 months') AND substr(deployment,1,7) <= substr(" + quote(date) + ",1,7)" + joinFilter + " GROUP BY substr(deployment,1,7) ORDER BY substr(deployment,1,7)"),
            additions: operatorName.isEmpty ? meta["added"].flatMap(Int.init) : nil,
            removals: operatorName.isEmpty ? meta["removed"].flatMap(Int.init) : nil,
            previousDate: operatorName.isEmpty ? meta["previousDate"] : nil)
    }
    public static func unpack(source: URL, destination: URL) throws {
        guard let gzip = gzopen(source.path, "rb") else { throw DatabaseError.sqlite("Base embarquée introuvable.") }
        defer { gzclose(gzip) }
        let temporary = destination.appendingPathExtension("partial")
        FileManager.default.createFile(atPath: temporary.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let output = try FileHandle(forWritingTo: temporary)
        defer { try? output.close() }
        var buffer = [UInt8](repeating: 0, count: 65536)
        var total = 0
        while true {
            let count = gzread(gzip, &buffer, UInt32(buffer.count))
            guard count >= 0 else { throw DatabaseError.sqlite("Base compressée endommagée.") }
            if count == 0 { break }
            total += Int(count)
            guard total < 512 * 1024 * 1024 else { throw DatabaseError.sqlite("Base trop volumineuse.") }
            try output.write(contentsOf: Data(buffer.prefix(Int(count))))
        }
        try output.close()
        try AntennaDatabase(url: temporary).validate()
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
    public func validate(requireEnriched: Bool = false) throws {
        if requireEnriched {
            guard try rows("PRAGMA user_version").first?.first == "2", !(try rows("SELECT stationID,name,generation,frequency,status,deployment,azimuths FROM systems LIMIT 1")).isEmpty else { throw DatabaseError.sqlite("Importe une base ANFR récente au format Pylo 2.") }
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA quick_check", -1, &stmt, nil) == SQLITE_OK else { throw DatabaseError.sqlite("Base invalide.") }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW, String(cString: sqlite3_column_text(stmt,0)) == "ok", !(try stations(limit: 1)).isEmpty else { throw DatabaseError.sqlite("Base vide ou endommagée.") }
    }
}
