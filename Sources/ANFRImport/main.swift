import Foundation
import PyloCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
struct Dataset: Decodable { let resources: [Resource] }
struct Resource: Decodable { let url: String; let title: String; let last_modified: String? }
@main struct Importer {
    static func main() async throws {
        let args = CommandLine.arguments
        let output = URL(fileURLWithPath: args.count > 1 ? args[1] : "antennas.sqlite")
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let csv: URL
        if args.count > 2 { csv = URL(fileURLWithPath: args[2]) }
        else {
            let endpoint = URL(string: "https://www.data.gouv.fr/api/1/datasets/6ab291cf426d615c84196260/")!
            let (meta, response) = try await URLSession.shared.data(from: endpoint)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw DatabaseError.sqlite("Catalogue ANFR indisponible") }
            let dataset = try JSONDecoder().decode(Dataset.self, from: meta)
            guard let resource = dataset.resources.filter({ $0.url.hasSuffix(".zip") && $0.title.lowercased().contains("observatoire") }).sorted(by: { ($0.last_modified ?? $0.title) > ($1.last_modified ?? $1.title) }).first,
                  let url = URL(string: resource.url), url.scheme == "https", url.host == "static.data.gouv.fr" else { throw DatabaseError.sqlite("Aucune archive officielle reconnue") }
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
}
