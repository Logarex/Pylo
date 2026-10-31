import Foundation
public enum ANFRAddress {
    private static let streetPattern = try? NSRegularExpression(pattern: #"(?i)^(\d+(?:[-/]\d+)?[a-z]?(?:\s+(?:bis|ter|quater))?\s+)?(r|rte|bd|boul|av|ave|chem|imp|pl|all|sq|fg|faub|pass)\.?(?=\s)"#)
    private static let expanded = ["r":"Rue","rte":"Route","bd":"Boulevard","boul":"Boulevard","av":"Avenue","ave":"Avenue","chem":"Chemin","imp":"Impasse","pl":"Place","all":"Allée","sq":"Square","fg":"Faubourg","faub":"Faubourg","pass":"Passage"]
    public static func full(_ raw: String, commune: String) -> String {
        let clean = readable(raw)
        guard !commune.isEmpty, !clean.components(separatedBy: ",").contains(where: { $0.trimmingCharacters(in: .whitespaces).localizedCaseInsensitiveCompare(commune) == .orderedSame }) else { return clean }
        let last = clean.components(separatedBy: ",").last?.trimmingCharacters(in: .whitespaces) ?? ""
        return clean + (clean.isEmpty ? "" : last.count == 5 && last.allSatisfy(\.isNumber) ? " " : ", ") + commune
    }
    public static func readable(_ original: String) -> String {
        original.components(separatedBy: ",").map { part in
            let clean = part.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            guard let regex = streetPattern, let match = regex.firstMatch(in: clean, range: NSRange(clean.startIndex...,in: clean)), let typeRange = Range(match.range(at: 2), in: clean), let allRange = Range(match.range,in: clean) else { return clean }
            guard let value = expanded[clean[typeRange].lowercased()] else { return clean }
            let prefix = Range(match.range(at: 1), in: clean).map { String(clean[$0]) } ?? ""
            return prefix + value + clean[allRange.upperBound...]
        }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
public enum ANFRValues {
    public static func azimuths(_ raw: String) -> [Double] {
        Array(Set(raw.split(separator: "|").compactMap { Double($0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",",with: ".")) }.filter { $0.isFinite && (0...360).contains($0) }.map { $0 == 360 ? 0 : $0 })).sorted()
    }
}
public struct ANFRReferences: Codable, Sendable {
    public let date: String
    public let natures: [String:String]
    public let owners: [String:String]
    public let communes: [String:String]
    public let sources: [String]
}
public struct ANFRSupportDetails: Codable, Sendable {
    public let fields: [String:String]
    public let nature: String
    public let owner: String
    public let commune: String
    public let referenceDate: String
    public var readableAddress: String {
        let raw = ["adr_lb_lieu","adr_lb_add1","adr_lb_add2","adr_lb_add3","adr_nm_cp"].compactMap { fields[$0] }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: ", ")
        return ANFRAddress.full(raw, commune: commune)
    }
}
public struct ANFRSourceRecord: Codable, Identifiable, Sendable {
    public let id: String
    public let system: String
    public let generation: String
    public let date: String
    public let status: String
    public let azimuths: String
    enum CodingKeys: String, CodingKey { case id = "i", system = "s", generation = "g", date = "d", status = "t", azimuths = "a" }
}
public struct ANFRSourceSupport: Identifiable, Sendable {
    public let id: String
    public let details: ANFRSupportDetails
    public let records: [ANFRSourceRecord]
    public var exportJSON: String {
        let rows = records.map { record in
            var row = details.fields
            row["id"] = record.id; row["emr_lb_systeme"] = record.system; row["generation"] = record.generation
            row["emr_dt"] = record.date; row["statut"] = record.status; row["list_azimut"] = record.azimuths
            return row
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]
        return (try? encoder.encode(rows)).flatMap { String(data:$0,encoding:.utf8) } ?? ""
    }
}
