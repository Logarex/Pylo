import Foundation
import CSQLite
public enum DatabaseError: Error, LocalizedError {
    case sqlite(String)
    public var errorDescription: String? { if case .sqlite(let s) = self { return s }; return nil }
}
public final class AntennaDatabase {
    private var db: OpaquePointer?
    private var sourceSupports: Set<String> = []
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
        try execute("PRAGMA journal_mode=DELETE; CREATE TABLE stations(id TEXT PRIMARY KEY, operatorName TEXT, latitude REAL, longitude REAL, address TEXT, systems TEXT, status TEXT, updated TEXT, supportID TEXT, height TEXT, commune TEXT); CREATE TABLE systems(stationID TEXT, name TEXT, generation TEXT, frequency TEXT, status TEXT, deployment TEXT, azimuths TEXT, PRIMARY KEY(stationID,name)); CREATE TABLE supports(stationID TEXT, supportID TEXT, height TEXT, latitude REAL, longitude REAL, azimuths TEXT, PRIMARY KEY(stationID,supportID)); CREATE TABLE anfr_details(stationID TEXT,supportID TEXT,info TEXT,records TEXT,PRIMARY KEY(stationID,supportID)); CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT); BEGIN TRANSACTION;")
    }
    public func insert(id: String, operatorName: String, lat: Double, lon: Double, address: String, system: String, status: String, updated: String, supportID: String = "", height: String = "", deployment: String = "", azimuths: String = "", commune: String = "") throws {
        try execute("INSERT INTO stations VALUES(\(quote(id)),\(quote(operatorName)),\(lat),\(lon),\(quote(address)),\(quote(system)),\(quote(status)),\(quote(updated)),\(quote(supportID)),\(quote(height)),\(quote(commune))) ON CONFLICT(id) DO UPDATE SET systems=CASE WHEN instr(stations.systems, excluded.systems)=0 THEN stations.systems || ' · ' || excluded.systems ELSE stations.systems END, status=CASE WHEN instr(stations.status, excluded.status)=0 THEN stations.status || ' · ' || excluded.status ELSE stations.status END;")
        let frequency = system.split(separator: " ").last.map(String.init) ?? "Inconnue"
        try execute("INSERT INTO systems VALUES(\(quote(id)),\(quote(system)),\(quote(Radio.generation(system))),\(quote(frequency)),\(quote(status)),\(quote(deployment)),\(quote(azimuths))) ON CONFLICT(stationID,name) DO UPDATE SET azimuths=systems.azimuths || '|' || excluded.azimuths, status=CASE WHEN instr(systems.status,excluded.status)=0 THEN systems.status || ' · ' || excluded.status ELSE systems.status END, deployment=CASE WHEN systems.deployment='' THEN excluded.deployment WHEN excluded.deployment='' THEN systems.deployment ELSE min(systems.deployment,excluded.deployment) END;")
        try execute("INSERT INTO supports VALUES(\(quote(id)),\(quote(supportID)),\(quote(height)),\(lat),\(lon),\(quote(azimuths))) ON CONFLICT(stationID,supportID) DO UPDATE SET azimuths=CASE WHEN instr(supports.azimuths,excluded.azimuths)=0 THEN supports.azimuths || '|' || excluded.azimuths ELSE supports.azimuths END;")
    }
    public func appendSource(_ row: [String:String], references: ANFRReferences) throws {
        let station = row["sta_nm_anfr"] ?? "", support = row["sup_id"] ?? ""
        let record = ANFRSourceRecord(id: row["id"] ?? "", system: row["emr_lb_systeme"] ?? "", generation: row["generation"] ?? "", date: row["emr_dt"] ?? "", status: row["statut"] ?? "", azimuths: row["list_azimut"] ?? "")
        let json = String(decoding: try JSONEncoder().encode(record), as: UTF8.self)
        if sourceSupports.insert(station + ":" + support).inserted {
            let fields = row.filter { !["id","emr_lb_systeme","generation","emr_dt","statut","list_azimut"].contains($0.key) }
            let info = ANFRSupportDetails(fields: fields, nature: references.natures[row["nat_id"] ?? ""] ?? "", owner: references.owners[row["tpo_id"] ?? ""] ?? "", commune: references.communes[row["com_cd_insee"] ?? ""] ?? "", referenceDate: references.date)
            let encoded = String(decoding: try JSONEncoder().encode(info), as: UTF8.self)
            try execute("INSERT INTO anfr_details VALUES(\(quote(station)),\(quote(support)),\(quote(encoded)),\(quote("["+json+"]")))")
        } else {
            try execute("UPDATE anfr_details SET records=substr(records,1,length(records)-1) || \(quote(","+json+"]")) WHERE stationID=\(quote(station)) AND supportID=\(quote(support))")
        }
    }
    public func sourceDetails(for id: String) throws -> [ANFRSourceSupport] {
        guard !(try rows("SELECT name FROM sqlite_master WHERE type='table' AND name='anfr_details'")).isEmpty else { return [] }
        return try rows("SELECT supportID,info,records FROM anfr_details WHERE stationID=\(quote(id)) ORDER BY supportID").map {
            ANFRSourceSupport(id: $0[0], details: try JSONDecoder().decode(ANFRSupportDetails.self, from: Data($0[1].utf8)), records: try JSONDecoder().decode([ANFRSourceRecord].self,from: Data($0[2].utf8)))
        }
    }
    public func finishImport() throws { try execute("COMMIT; CREATE INDEX coordinates ON stations(latitude,longitude); CREATE INDEX system_station ON systems(stationID); CREATE INDEX station_operator ON stations(operatorName); INSERT OR REPLACE INTO metadata SELECT 'sourceDate',max(substr(updated,1,10)) FROM stations; PRAGMA user_version=2; VACUUM;") }
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
            result.append(Station(id: string(0), operatorName: string(1), latitude: sqlite3_column_double(stmt,2), longitude: sqlite3_column_double(stmt,3), address: string(4), systems: systems, status: string(6), updated: string(7), supportID: sqlite3_column_count(stmt) > 8 ? string(8) : "", height: sqlite3_column_count(stmt) > 9 ? string(9) : "", commune: sqlite3_column_count(stmt) > 10 ? string(10) : ""))
        }
        return result
    }
    public func stations(ids: Set<String>) throws -> [Station] {
        guard !ids.isEmpty else { return [] }
        let values = ids.sorted()
        var result: [Station] = []
        for start in stride(from: 0, to: values.count, by: 500) {
            let chunk = values[start..<min(start+500, values.count)].map(quote).joined(separator: ",")
            let found = try rows("SELECT * FROM stations WHERE id IN (\(chunk))")
            result += found.map { Station(id: $0[0], operatorName: $0[1], latitude: Double($0[2]) ?? 0, longitude: Double($0[3]) ?? 0, address: $0[4], systems: $0[5], status: $0[6], updated: $0[7], supportID: $0[8], height: $0[9], commune: $0.count > 10 ? $0[10] : "") }
        }
        return result.sorted { a,b in a.operatorName == b.operatorName ? a.id < b.id : a.operatorName < b.operatorName }
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
            RadioSystem(name: $0[0], status: $0[1], date: $0[2], azimuths: ANFRValues.azimuths($0[3]))
        }
    }
    public func supports(for id: String) throws -> [AntennaSupport] {
        try rows("SELECT supportID,height,latitude,longitude,azimuths FROM supports WHERE stationID=\(quote(id)) ORDER BY supportID").map {
            AntennaSupport(id: $0[0], height: $0[1], latitude: Double($0[2]) ?? 0, longitude: Double($0[3]) ?? 0, azimuths: ANFRValues.azimuths($0[4]))
        }
    }
    public func primaryDirections(for stationIDs: [String]) throws -> [String: [Double]] {
        guard !stationIDs.isEmpty else { return [:] }
        let ids = stationIDs.prefix(600).map(quote).joined(separator: ",")
        return Dictionary(uniqueKeysWithValues: try rows("SELECT p.stationID,p.azimuths FROM supports p JOIN stations s ON p.stationID=s.id AND p.supportID=s.supportID WHERE s.id IN (\(ids))").map { row in
            (row[0], ANFRValues.azimuths(row[1]))
        })
    }
    public func sourceDate() throws -> String {
        if !(try rows("SELECT name FROM sqlite_master WHERE name='metadata'")).isEmpty,
           let value = try rows("SELECT value FROM metadata WHERE key='sourceDate'").first?.first, !value.isEmpty { return value }
        return try rows("SELECT max(substr(updated,1,10)) FROM stations").first?.first ?? ""
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
    public func importStationDates(_ text: String, source: String) throws -> Int {
        try execute("CREATE TABLE IF NOT EXISTS station_dates(stationID TEXT PRIMARY KEY,implantation TEXT,modification TEXT,service TEXT,source TEXT); BEGIN TRANSACTION;")
        var header: [String] = []; var imported = 0
        let stationIDs = Set(try rows("SELECT id FROM stations").map { $0[0] })
        let parser = DateFormatter(); parser.locale = Locale(identifier: "en_US_POSIX"); parser.timeZone = TimeZone(secondsFromGMT: 0); parser.dateFormat = "dd/MM/yyyy"; parser.isLenient = false
        let output = DateFormatter(); output.locale = parser.locale; output.timeZone = parser.timeZone; output.dateFormat = "yyyy-MM-dd"
        var dateCache: [String:String] = [:]
        try CSV.rows(text) { row in
            if header.isEmpty {
                header = row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\u{feff}", with: "") }
                guard ["STA_NM_ANFR","DTE_IMPLANTATION","DTE_MODIF","DTE_EN_SERVICE"].allSatisfy(header.contains) else { throw DatabaseError.sqlite("Colonnes de dates ANFR non reconnues") }
                return
            }
            guard row.count == header.count else { throw DatabaseError.sqlite("Ligne de dates ANFR invalide") }
            func field(_ key: String) -> String { row[header.firstIndex(of: key)!] }
            func iso(_ raw: String) throws -> String {
                guard !raw.isEmpty else { return "" }
                if let cached = dateCache[raw] { return cached }
                guard let date = parser.date(from: raw), parser.string(from: date) == raw else { throw DatabaseError.sqlite("Date ANFR non reconnue : " + raw) }
                let value = output.string(from: date); dateCache[raw] = value; return value
            }
            let id = field("STA_NM_ANFR")
            guard stationIDs.contains(id) else { return }
            let dates = try [iso(field("DTE_IMPLANTATION")),iso(field("DTE_MODIF")),iso(field("DTE_EN_SERVICE"))]
            try execute("INSERT INTO station_dates SELECT id,\(quote(dates[0])),\(quote(dates[1])),\(quote(dates[2])),\(quote(source)) FROM stations WHERE id=\(quote(id));")
            imported += Int(sqlite3_changes(db))
        }
        try execute("COMMIT;")
        return imported
    }
    public func stationDates(for id: String) throws -> StationDates? {
        guard !(try rows("SELECT name FROM sqlite_master WHERE type='table' AND name='station_dates'")).isEmpty else { return nil }
        guard let row = try rows("SELECT implantation,modification,service,source FROM station_dates WHERE stationID=\(quote(id))").first else { return nil }
        return StationDates(implantation: row[0], modification: row[1], service: row[2], source: row[3])
    }
    public func statistics(operatorName: String = "") throws -> NetworkStatistics {
        let filter = operatorName.isEmpty ? "" : " WHERE operatorName=" + quote(operatorName)
        let joinFilter = operatorName.isEmpty ? "" : " AND stationID IN (SELECT id FROM stations WHERE operatorName=" + quote(operatorName) + ")"
        func count(_ sql: String) throws -> Int { Int(try rows(sql).first?.first ?? "0") ?? 0 }
        func items(_ sql: String) throws -> [StatItem] { try rows(sql).map { StatItem(label: $0[0], count: Int($0[1]) ?? 0) } }
        let meta = Dictionary(uniqueKeysWithValues: try rows("SELECT key,value FROM metadata").map { ($0[0],$0[1]) })
        let date = try sourceDate()
        let declared = try items("SELECT substr(deployment,1,7),count(*) FROM systems WHERE length(deployment)>=10 AND substr(deployment,1,7) >= strftime('%Y-%m'," + quote(date) + ",'start of month','-11 months') AND substr(deployment,1,7) <= substr(" + quote(date) + ",1,7)" + joinFilter + " GROUP BY substr(deployment,1,7) ORDER BY substr(deployment,1,7)")
        let monthly = Dictionary(uniqueKeysWithValues: declared.map { ($0.label, $0.count) })
        let components = date.split(separator: "-").compactMap { Int($0) }
        var timeline: [StatItem] = []
        if components.count == 3 {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            if let end = calendar.date(from: DateComponents(year: components[0], month: components[1], day: 1)) {
                for offset in -11...0 {
                    if let month = calendar.date(byAdding: .month, value: offset, to: end) {
                        let parts = calendar.dateComponents([.year,.month], from: month)
                        let key = String(format: "%04d-%02d", parts.year!, parts.month!)
                        timeline.append(StatItem(label: key, count: monthly[key] ?? 0))
                    }
                }
            }
        }
        return try NetworkStatistics(
            stationCount: count("SELECT count(*) FROM stations" + filter),
            supportCount: count("SELECT count(DISTINCT NULLIF(supportID,'')) FROM supports WHERE 1=1" + joinFilter),
            systemCount: count("SELECT count(*) FROM systems WHERE 1=1" + joinFilter),
            sourceDate: date,
            operators: items("SELECT operatorName,count(*) FROM stations" + filter + " GROUP BY operatorName ORDER BY count(*) DESC"),
            generations: items("SELECT generation,count(DISTINCT stationID) FROM systems WHERE 1=1" + joinFilter + " GROUP BY generation ORDER BY generation"),
            frequencies: items("SELECT frequency,count(*) FROM systems WHERE 1=1" + joinFilter + " GROUP BY frequency ORDER BY CAST(frequency AS REAL)"),
            deployments: timeline,
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
