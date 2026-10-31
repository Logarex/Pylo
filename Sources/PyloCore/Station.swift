import Foundation
public struct Station: Identifiable, Hashable, Sendable {
    public let id: String
    public let operatorName: String
    public let latitude: Double
    public let longitude: Double
    public let address: String
    public var readableAddress: String { ANFRAddress.full(address, commune: commune) }
    public let systems: String
    public let status: String
    public let updated: String
    public let supportID: String
    public let height: String
    public var commune: String = ""
}
public enum Radio {
    public static func generation(_ system: String) -> String {
        if system.contains("5G") { return "5G" }
        if system.contains("LTE") { return "4G" }
        if system.contains("UMTS") { return "3G" }
        if system.contains("GSM") { return "2G" }
        return "Inconnue"
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

public struct RadioSystem: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let status: String
    public let date: String
    public let azimuths: [Double]
    public var generation: String { Radio.generation(name) }
}
public struct StatItem: Identifiable, Sendable {
    public var id: String { label }
    public let label: String
    public let count: Int
}
public struct NetworkStatistics: Sendable {
    public let stationCount: Int
    public let supportCount: Int
    public let systemCount: Int
    public let sourceDate: String
    public let operators: [StatItem]
    public let generations: [StatItem]
    public let frequencies: [StatItem]
    public let deployments: [StatItem]
    public let additions: Int?
    public let removals: Int?
    public let previousDate: String?
}
public enum Geometry {
    public static func bearing(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let a = lat1 * .pi / 180, b = lat2 * .pi / 180, d = (lon2-lon1) * .pi / 180
        return (atan2(sin(d)*cos(b), cos(a)*sin(b)-sin(a)*cos(b)*cos(d)) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }
    public static func angularDifference(_ a: Double, _ b: Double) -> Double { abs((a-b+540).truncatingRemainder(dividingBy: 360)-180) }
    public static func freeSpaceLoss(distanceKM: Double, frequencyMHz: Double) -> Double? {
        guard distanceKM > 0, frequencyMHz > 0 else { return nil }
        return 32.44 + 20 * log10(distanceKM) + 20 * log10(frequencyMHz)
    }
}

public struct AntennaSupport: Identifiable, Sendable {
    public let id: String
    public let height: String
    public let latitude: Double
    public let longitude: Double
    public let azimuths: [Double]
}

public struct StationDates: Sendable {
    public let implantation: String
    public let modification: String
    public let service: String
    public let source: String
}
