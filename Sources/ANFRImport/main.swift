import Foundation
import PyloCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
struct Dataset: Decodable { let resources: [Resource] }
struct Resource: Codable { let id: String; let url: String; let title: String; let last_modified: String? }
struct CatalogSelection: Codable { let version: String; let resource: Resource }
@main struct Importer {
    static func main() async throws {
        let args = CommandLine.arguments
        if args.count == 3 && args[1] == "--verify-update" {
            let manifest = try await DataUpdates.fetchManifest()
            try await DataUpdates.install(manifest, at: URL(fileURLWithPath: args[2]))
            print("Mise à jour vérifiée et installée : \(manifest.sourceDate)")
            return
        }
        if args.count == 3 && args[1] == "--catalog" {
            let (_, resource) = try await latestResource()
            let selected = CatalogSelection(version: resource.id + ":" + (resource.last_modified ?? resource.title), resource: resource)
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
        let temporary = work.appendingPathComponent("antennas.sqlite")
        let db = try AntennaDatabase(url: temporary, writable: true); try db.prepareImport()
        var header: [String] = []; var count = 0
        let text = try String(contentsOf: csv, encoding: .utf8)
        try CSV.rows(text) { row in
            if header.isEmpty {
                header = row
                guard ["sta_nm_anfr","adm_lb_nom","coordonnees","generation","emr_lb_systeme","statut","date_maj","sup_id","sup_nm_haut","emr_dt","list_azimut"].allSatisfy(header.contains) else { throw DatabaseError.sqlite("Le schéma ANFR a changé : mise à jour interrompue.") }
                return
            }
            guard row.count == header.count else { throw DatabaseError.sqlite("Ligne CSV mal formée") }
            func value(_ name: String) -> String { header.firstIndex(of: name).map { row[$0] } ?? "" }
            guard ["2G","3G","4G","5G"].contains(value("generation")) else { return }
            let coord = value("coordonnees").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard coord.count == 2, let lat = Double(coord[0]), let lon = Double(coord[1]), (-90...90).contains(lat), (-180...180).contains(lon), !value("sta_nm_anfr").isEmpty else { throw DatabaseError.sqlite("Coordonnées ANFR invalides") }
            let address = ["adr_lb_lieu","adr_lb_add1","adr_lb_add2","adr_lb_add3","adr_nm_cp"].map(value).filter { !$0.isEmpty }.joined(separator: ", ")
            try db.insert(id: value("sta_nm_anfr"), operatorName: value("adm_lb_nom"), lat: lat, lon: lon, address: address, system: value("emr_lb_systeme"), status: value("statut"), updated: value("date_maj"), supportID: value("sup_id"), height: value("sup_nm_haut"), deployment: value("emr_dt"), azimuths: value("list_azimut")); count += 1
        }
        guard count > 1000 else { throw DatabaseError.sqlite("Import anormalement petit, ancienne base conservée.") }
        try db.finishImport()
        if let previous = ProcessInfo.processInfo.environment["PYLO_PREVIOUS_DATABASE"] { try db.recordComparison(previous: URL(fileURLWithPath: previous)) }
        try db.validate()
        let data = try Data(contentsOf: temporary); try data.write(to: output, options: .atomic)
        print("Import terminé : \(count) systèmes ; \(data.count / 1_000_000) Mo.")
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
