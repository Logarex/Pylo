import Foundation
public struct Station: Identifiable, Hashable, Sendable {
    public let id: String
    public let operatorName: String
    public let latitude: Double
    public let longitude: Double
    public let address: String
    public let systems: String
    public let status: String
    public let updated: String
}
public enum Radio {
    public static func generation(_ system: String) -> String {
        if system.contains("5G") { return "5G" }
        if system.contains("LTE") { return "4G" }
        if system.contains("UMTS") { return "3G" }
        return "2G"
    }
    public static func enodeB(_ eci: UInt32) -> UInt32 { eci / 256 }
    public static func sector(_ eci: UInt32) -> UInt32 { eci % 256 }
}
/// RFC-style CSV scanner: quoted separators, escaped quotes and embedded newlines.
public enum CSV {
    public static func rows(_ text: String, consume: ([String]) throws -> Void) rethrows {
        var row: [String] = [], field: [UInt8] = [], quoted = false
        let bytes = Array(text.utf8); var i = 0
        func decoded(_ bytes: [UInt8]) -> String { String(decoding: bytes, as: UTF8.self) }
        while i < bytes.count {
            let c = bytes[i]
            if c == 34 {
                if quoted && i + 1 < bytes.count && bytes[i+1] == 34 { field.append(34); i += 1 }
                else { quoted.toggle() }
            } else if c == 59 && !quoted { row.append(decoded(field)); field.removeAll(keepingCapacity: true) }
            else if c == 10 && !quoted {
                row.append(decoded(field)); try consume(row); row.removeAll(keepingCapacity: true); field.removeAll(keepingCapacity: true)
            } else if c != 13 || quoted { field.append(c) }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty { row.append(decoded(field)); try consume(row) }
    }
}
