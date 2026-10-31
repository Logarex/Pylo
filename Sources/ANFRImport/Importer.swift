import Foundation
import PyloCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
struct Dataset: Decodable { let resources: [Resource] }
struct Resource: Codable { let id: String; let url: String; let title: String; let last_modified: String? }
struct CatalogSelection: Codable { let version: String; let resource: Resource; let datesResource: Resource? }
@main struct Importer {
    static func main() async throws {
        let args = CommandLine.arguments
        if args.count == 3 && args[1] == "--references" {
            try await refreshReferences(at: URL(fileURLWithPath: args[2]))
            return
        }
        if args.count == 3 && args[1] == "--verify-update" {
            let manifest = try await DataUpdates.fetchManifest()
            try await DataUpdates.install(manifest, at: URL(fileURLWithPath: args[2]))
            print("Mise à jour vérifiée et installée : \(manifest.sourceDate)")
            return
        }
        if args.count == 3 && args[1] == "--catalog" {
            let (_, resource) = try await latestResource()
            let dates = try await latestDatesResource()
            let selected = CatalogSelection(version: resource.id + ":" + (resource.last_modified ?? resource.title) + "|" + dates.id + ":" + (dates.last_modified ?? dates.title), resource: resource, datesResource: dates)
            try JSONEncoder().encode(selected).write(to: URL(fileURLWithPath: args[2]), options: .atomic)
            return
        }
        if args.count == 7 && args[1] == "--manifest" {
            let archive = URL(fileURLWithPath: args[2]), sqlite = URL(fileURLWithPath: args[3])
            let selected = try JSONDecoder().decode(CatalogSelection.self, from: Data(contentsOf: URL(fileURLWithPath: args[4])))
            let db = try AntennaDatabase(url: sqlite); try db.validate(requireEnriched: true)
            let manifest = try DataManifest(sourceVersion: selected.version, sourceDate: db.sourceDate(), url: URL(string: args[5])!, sha256: DataUpdates.digest(of: archive), compressedBytes: FileManager.default.attributesOfItem(atPath: archive.path)[.size] as! Int, uncompressedBytes: FileManager.default.attributesOfItem(atPath: sqlite.path)[.size] as! Int)
            try manifest.validate()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(manifest).write(to: URL(fileURLWithPath: args[6]), options: .atomic)
            return
        }
        let output = URL(fileURLWithPath: args.count > 1 ? args[1] : "antennas.sqlite")
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let csv: URL
        if args.count > 2 { csv = URL(fileURLWithPath: args[2]) }
        else {
            let (meta, latest) = try await latestResource()
            let resource: Resource
            if let selection = ProcessInfo.processInfo.environment["PYLO_SELECTED_RESOURCE"] {
                resource = try JSONDecoder().decode(CatalogSelection.self, from: Data(contentsOf: URL(fileURLWithPath: selection))).resource
            } else { resource = latest }
            guard let url = URL(string: resource.url), url.scheme == "https", url.host == "static.data.gouv.fr" else { throw DatabaseError.sqlite("Aucune archive officielle reconnue") }
            print("Source : \(resource.url)")
            let (archive, downloadResponse) = try await URLSession.shared.download(from: url)
            guard (downloadResponse as? HTTPURLResponse)?.statusCode == 200 else { throw DatabaseError.sqlite("Téléchargement ANFR impossible") }
            let zip = work.appendingPathComponent("source.zip")
            try FileManager.default.moveItem(at: archive, to: zip)
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); process.arguments = ["-q", zip.path, "-d", work.path]
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0, let found = try FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil).first(where: { $0.pathExtension == "csv" }) else { throw DatabaseError.sqlite("Archive ANFR invalide") }
            csv = found
            try meta.write(to: output.deletingLastPathComponent().appendingPathComponent("source.json"), options: .atomic)
        }
        let referenceURL = ProcessInfo.processInfo.environment["PYLO_REFERENCES"].map { URL(fileURLWithPath: $0) } ?? Bundle.module.url(forResource: "references", withExtension: "json")!
        let references = try JSONDecoder().decode(ANFRReferences.self, from: Data(contentsOf: referenceURL))
        let temporary = work.appendingPathComponent("antennas.sqlite")
        let db = try AntennaDatabase(url: temporary, writable: true); try db.prepareImport()
        var header: [String] = []; var count = 0
        var quality = ["missingDates":0,"unknownAzimuthRows":0,"north360Rows":0,"unknownNatureCodes":0,"unknownOwnerCodes":0,"unknownCommuneCodes":0,"zeroHeightRows":0]
        var sourceIDs: Set<String> = []
        let text = try String(contentsOf: csv, encoding: .utf8)
        try CSV.rows(text) { row in
            if header.isEmpty {
                header = row.map { $0.replacingOccurrences(of: "\u{feff}", with: "").trimmingCharacters(in: .whitespacesAndNewlines) }
                guard ["id","adm_lb_nom","sup_id","emr_lb_systeme","emr_dt","sta_nm_dpt","code_insee","generation","date_maj","sta_nm_anfr","nat_id","sup_nm_haut","tpo_id","adr_lb_lieu","adr_lb_add1","adr_lb_add2","adr_lb_add3","adr_nm_cp","com_cd_insee","coordonnees","coord","statut","list_azimut"].allSatisfy(header.contains) else { throw DatabaseError.sqlite("Le schéma ANFR a changé : mise à jour interrompue.") }
                return
            }
            guard row.count == header.count else { throw DatabaseError.sqlite("Ligne CSV mal formée") }
            func value(_ name: String) -> String { header.firstIndex(of: name).map { row[$0] } ?? "" }
            guard ["2G","3G","4G","5G"].contains(value("generation")) else { return }
            guard !value("id").isEmpty, sourceIDs.insert(value("id")).inserted else { throw DatabaseError.sqlite("Identifiant de ligne ANFR vide ou en doublon") }
            if value("emr_dt").isEmpty { quality["missingDates",default:0] += 1 }
            if ANFRValues.azimuths(value("list_azimut")).isEmpty { quality["unknownAzimuthRows",default:0] += 1 }
            if value("list_azimut").split(separator:"|").contains("360") { quality["north360Rows",default:0] += 1 }
            if references.natures[value("nat_id")] == nil { quality["unknownNatureCodes",default:0] += 1 }
            if references.owners[value("tpo_id")] == nil { quality["unknownOwnerCodes",default:0] += 1 }
            if references.communes[value("com_cd_insee")] == nil { quality["unknownCommuneCodes",default:0] += 1 }
            if Double(value("sup_nm_haut").replacingOccurrences(of:",",with:".")) == 0 { quality["zeroHeightRows",default:0] += 1 }
            let coord = value("coordonnees").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard coord.count == 2, let lat = Double(coord[0]), let lon = Double(coord[1]), (-90...90).contains(lat), (-180...180).contains(lon), !value("sta_nm_anfr").isEmpty else { throw DatabaseError.sqlite("Coordonnées ANFR invalides") }
            let address = ["adr_lb_lieu","adr_lb_add1","adr_lb_add2","adr_lb_add3","adr_nm_cp"].map(value).filter { !$0.isEmpty }.joined(separator: ", ")
            try db.appendSource(Dictionary(uniqueKeysWithValues: zip(header,row)), references: references)
            try db.insert(id: value("sta_nm_anfr"), operatorName: value("adm_lb_nom"), lat: lat, lon: lon, address: address, system: value("emr_lb_systeme"), status: value("statut"), updated: value("date_maj"), supportID: value("sup_id"), height: value("sup_nm_haut"), deployment: value("emr_dt"), azimuths: value("list_azimut"), commune: references.communes[value("com_cd_insee")] ?? ""); count += 1
        }
        guard count > 1000 else { throw DatabaseError.sqlite("Import anormalement petit, ancienne base conservée.") }
        try db.finishImport()
        let datesResource: Resource
        if let path = ProcessInfo.processInfo.environment["PYLO_SELECTED_RESOURCE"], let selected = try JSONDecoder().decode(CatalogSelection.self, from: Data(contentsOf: URL(fileURLWithPath: path))).datesResource { datesResource = selected }
        else { datesResource = try await latestDatesResource() }
        guard let datesURL = URL(string: datesResource.url), datesURL.scheme == "https", datesURL.host == "static.data.gouv.fr" else { throw DatabaseError.sqlite("Archive de dates ANFR non reconnue") }
        let (datesArchive, datesResponse) = try await URLSession.shared.download(from: datesURL)
        guard (datesResponse as? HTTPURLResponse)?.statusCode == 200 else { throw DatabaseError.sqlite("Archive de dates ANFR indisponible") }
        let datesZip = work.appendingPathComponent("dates.zip")
        try FileManager.default.moveItem(at: datesArchive, to: datesZip)
        let unzip = Process(); unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); unzip.arguments = ["-q", datesZip.path, "SUP_STATION.txt", "-d", work.path]
        try unzip.run(); unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else { throw DatabaseError.sqlite("Table des dates ANFR absente") }
        let datesData = try Data(contentsOf: work.appendingPathComponent("SUP_STATION.txt"))
        guard let datesText = String(data: datesData, encoding: .utf8) ?? String(data: datesData, encoding: .isoLatin1) else { throw DatabaseError.sqlite("Encodage des dates ANFR invalide") }
        let matchedDates = try db.importStationDates(datesText, source: datesResource.title)
        guard matchedDates > 1000 else { throw DatabaseError.sqlite("Trop peu de stations reliées aux dates ANFR") }
        quality["stationsWithDateRecord"] = matchedDates
        try JSONEncoder().encode(datesResource).write(to: output.deletingLastPathComponent().appendingPathComponent("dates-source.json"), options: .atomic)
        if let previous = ProcessInfo.processInfo.environment["PYLO_PREVIOUS_DATABASE"] { try db.recordComparison(previous: URL(fileURLWithPath: previous)) }
        try db.validate()
        let data = try Data(contentsOf: temporary); try data.write(to: output, options: .atomic)
        quality["sourceRows"] = count; quality["sourceColumns"] = header.count
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(quality).write(to: output.deletingLastPathComponent().appendingPathComponent("quality.json"), options: .atomic)
        print("Import terminé : \(count) systèmes ; \(data.count / 1_000_000) Mo.")
    }
    static func refreshReferences(at destination: URL) async throws {
        struct Commune: Decodable { let code: String; let nom: String }
        func download(_ url: URL) async throws -> Data {
            let (data,response) = try await URLSession.shared.data(from:url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw DatabaseError.sqlite("Référentiel officiel indisponible") }
            return data
        }
        let catalog = try await download(URL(string:"https://data-backoffice.anfr.fr/api/3/action/package_show?id=observatoire_2g_3g_4g")!)
        let json = try JSONSerialization.jsonObject(with:catalog) as? [String:Any]
        guard let result = json?["result"] as? [String:Any], let resources = result["resources"] as? [[String:Any]] else { throw DatabaseError.sqlite("Catalogue des nomenclatures ANFR invalide") }
        var mappings: [String:[String:String]] = [:]
        var sources: [String] = []
        for (name,key) in [("NAT_ID.txt","natures"),("TPO_ID.txt","owners")] {
            guard let raw = resources.first(where: { $0["name"] as? String == name })?["url"] as? String,
                  let url = URL(string:raw),url.scheme == "https",url.host == "data.anfr.fr" else { throw DatabaseError.sqlite("Nomenclature ANFR introuvable") }
            let data = try await download(url)
            guard let text = String(data:data,encoding:.utf8) ?? String(data:data,encoding:.isoLatin1) else { throw DatabaseError.sqlite("Encodage du référentiel ANFR inconnu") }
            var values: [String:String] = [:]
            CSV.rows(text) { row in if row.count >= 2, Int(row[0]) != nil { values[row[0]] = row[1] } }
            guard values.count > 20 else { throw DatabaseError.sqlite("Nomenclature ANFR vide ou incomplète") }
            mappings[key] = values; sources.append(raw)
        }
        let geo = "https://geo.api.gouv.fr/communes?fields=code,nom&format=json"
        let communes = try JSONDecoder().decode([Commune].self, from: await download(URL(string:geo)!))
        guard communes.count > 20000 else { throw DatabaseError.sqlite("Référentiel des communes incomplet") }
        let boroughURL = "https://geo.api.gouv.fr/communes?type=arrondissement-municipal&fields=code,nom&format=json"
        let boroughs = try JSONDecoder().decode([Commune].self, from: await download(URL(string:boroughURL)!))
        var communeNames = Dictionary(uniqueKeysWithValues: communes.map { ($0.code,$0.nom) })
        for borough in boroughs { communeNames[borough.code] = borough.nom }
        sources.append(contentsOf: [geo,boroughURL])
        let output: [String:Any] = ["date":String(ISO8601DateFormatter().string(from:Date()).prefix(10)),"natures":mappings["natures"]!,"owners":mappings["owners"]!,"communes":communeNames,"sources":sources]
        try JSONSerialization.data(withJSONObject:output,options:[.sortedKeys]).write(to:destination,options:.atomic)
    }
    static func latestDatesResource() async throws -> Resource {
        let url = URL(string: "https://www.data.gouv.fr/api/1/datasets/donnees-sur-les-installations-radioelectriques-de-plus-de-5-watts-1/")!
        let (data,response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw DatabaseError.sqlite("Catalogue des installations ANFR indisponible") }
        let dataset = try JSONDecoder().decode(Dataset.self, from: data)
        guard let resource = dataset.resources.filter({ $0.url.hasSuffix("-data.zip") && $0.title.lowercased().contains("supports") }).sorted(by: { ($0.last_modified ?? "") > ($1.last_modified ?? "") }).first else { throw DatabaseError.sqlite("Archive des installations ANFR introuvable") }
        return resource
    }
    static func latestResource() async throws -> (Data, Resource) {
        let endpoint = URL(string: "https://www.data.gouv.fr/api/1/datasets/6ab291cf426d615c84196260/")!
        let (meta, response) = try await URLSession.shared.data(from: endpoint)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw DatabaseError.sqlite("Catalogue ANFR indisponible") }
        let dataset = try JSONDecoder().decode(Dataset.self, from: meta)
        guard let resource = dataset.resources.filter({ $0.url.hasSuffix(".zip") && $0.title.lowercased().contains("observatoire") }).sorted(by: { ($0.last_modified ?? $0.title) > ($1.last_modified ?? $1.title) }).first else { throw DatabaseError.sqlite("Aucune archive ANFR reconnue") }
        return (meta, resource)
    }

}
