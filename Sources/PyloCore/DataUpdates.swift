import Foundation
import CryptoKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct DataManifest: Codable, Sendable {
    public let schemaVersion: Int
    public let sourceVersion: String
    public let sourceDate: String
    public let url: URL
    public let sha256: String
    public let compressedBytes: Int
    public let uncompressedBytes: Int
    public init(sourceVersion: String, sourceDate: String, url: URL, sha256: String, compressedBytes: Int, uncompressedBytes: Int) {
        schemaVersion = 2; self.sourceVersion = sourceVersion; self.sourceDate = sourceDate
        self.url = url; self.sha256 = sha256; self.compressedBytes = compressedBytes; self.uncompressedBytes = uncompressedBytes
    }
    public func validate() throws {
        guard schemaVersion == 2, !sourceVersion.isEmpty, sourceDate.count == 10,
              url.scheme == "https", url.host == "github.com",
              url.path.hasPrefix("/Logarex/Pylo/releases/download/"), url.lastPathComponent == "antennas.sqlite.gz",
              sha256.count == 64, sha256.allSatisfy({ $0.isHexDigit }),
              (1...100_000_000).contains(compressedBytes), (1...512_000_000).contains(uncompressedBytes) else {
            throw DatabaseError.sqlite("Cette mise à jour n’est pas compatible avec Pylo.")
        }
    }
}
public enum DataUpdates {
    public static let manifestURL = URL(string: "https://raw.githubusercontent.com/Logarex/Pylo/main/data/manifest.json")!
    public static func digest(of url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    public static func fetchManifest() async throws -> DataManifest {
        var components = URLComponents(url: manifestURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "check", value: UUID().uuidString)]
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 65536 else { throw DatabaseError.sqlite("La vérification est momentanément indisponible.") }
        let manifest = try JSONDecoder().decode(DataManifest.self, from: data)
        try manifest.validate(); return manifest
    }
    /// Download into a temporary file, check its fingerprint, validate SQLite, then atomically replace it.
    public static func install(_ manifest: DataManifest, at destination: URL) async throws {
        try manifest.validate()
        let config = URLSessionConfiguration.ephemeral
        config.allowsCellularAccess = false
        #if !os(Linux)
        config.allowsExpensiveNetworkAccess = false
        config.allowsConstrainedNetworkAccess = false
        #endif
        config.timeoutIntervalForResource = 300
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let (archive, response) = try await session.download(from: manifest.url)
        defer { try? FileManager.default.removeItem(at: archive) }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw DatabaseError.sqlite("Le téléchargement est momentanément indisponible.") }
        try await Task.detached(priority: .utility) {
            try installArchive(archive, manifest: manifest, at: destination)
        }.value
    }
    public static func installArchive(_ archive: URL, manifest: DataManifest, at destination: URL) throws {
        try manifest.validate()
            let fm = FileManager.default
            let bytes = try fm.attributesOfItem(atPath: archive.path)[.size] as? Int
            guard bytes == manifest.compressedBytes, try digest(of: archive) == manifest.sha256.lowercased() else { throw DatabaseError.sqlite("Le fichier reçu est incomplet ou différent de celui publié. Ta base actuelle est conservée.") }
            let staging = destination.deletingLastPathComponent().appendingPathComponent("update-\(UUID().uuidString).sqlite")
            defer { try? fm.removeItem(at: staging) }
            try AntennaDatabase.unpack(source: archive, destination: staging)
            let size = try fm.attributesOfItem(atPath: staging.path)[.size] as? Int
            guard size == manifest.uncompressedBytes else { throw DatabaseError.sqlite("La base téléchargée n’a pas la taille attendue.") }
            let db = try AntennaDatabase(url: staging); try db.validate(requireEnriched: true)
            guard try db.sourceDate() == manifest.sourceDate else { throw DatabaseError.sqlite("La version de la base ne correspond pas à la publication.") }
            if fm.fileExists(atPath: destination.path) { _ = try fm.replaceItemAt(destination, withItemAt: staging) }
            else { try fm.moveItem(at: staging, to: destination) }
    }

}
