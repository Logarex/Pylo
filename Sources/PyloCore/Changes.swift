import Foundation

public func operatorDisplayName(_ name: String) -> String {
    switch name {
    case "SFR", "SRR", "SPT", "UTS Caraibes": return name
    case "FREE MOBILE": return "Free Mobile"
    case "BOUYGUES TELECOM": return "Bouygues Telecom"
    case "ORANGE": return "Orange"
    case "PMT-VODAFONE": return "PMT-Vodafone"
    case "TELCO OI": return "Telco OI"
    case "VITI SAS": return "Viti SAS"
    default: return name.capitalized
    }
}

/// What changed for one station between two ANFR publications.
public struct StationChange: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable { case added, removed, modified }
    public struct StatusChange: Codable, Sendable, Hashable {
        public let system: String
        public let from: String
        public let to: String
        public init(system: String, from: String, to: String) { self.system = system; self.from = from; self.to = to }
    }
    public let id: String
    public let kind: Kind
    public let operatorName: String
    public let latitude: Double
    public let longitude: Double
    public let address: String
    public let commune: String
    public let addedSystems: [String]
    public let removedSystems: [String]
    public let statusChanges: [StatusChange]
    /// Codes : orientation, height, location, supports. Kept as strings so new codes don't break older apps.
    public let details: [String]
    public init(id: String, kind: Kind, operatorName: String, latitude: Double, longitude: Double, address: String, commune: String, addedSystems: [String] = [], removedSystems: [String] = [], statusChanges: [StatusChange] = [], details: [String] = []) {
        self.id = id; self.kind = kind; self.operatorName = operatorName; self.latitude = latitude; self.longitude = longitude
        self.address = address; self.commune = commune; self.addedSystems = addedSystems; self.removedSystems = removedSystems
        self.statusChanges = statusChanges; self.details = details
    }
}

/// Published next to each database as changes.json : every station added, removed or modified since the previous publication.
public struct ChangeReport: Codable, Sendable {
    public let schemaVersion: Int
    public let sourceDate: String
    public let previousDate: String
    public let added: Int
    public let removed: Int
    public let modified: Int
    public let changes: [StationChange]
    public init(sourceDate: String, previousDate: String, changes: [StationChange]) {
        schemaVersion = 1; self.sourceDate = sourceDate; self.previousDate = previousDate; self.changes = changes
        added = changes.filter { $0.kind == .added }.count
        removed = changes.filter { $0.kind == .removed }.count
        modified = changes.filter { $0.kind == .modified }.count
    }
}

extension AntennaDatabase {
    private struct Snapshot {
        struct StationRow { let operatorName: String; let latitude: Double; let longitude: Double; let address: String; let commune: String }
        struct SupportRow: Equatable { let height: String; let azimuths: [Double] }
        var stations: [String: StationRow] = [:]
        var systems: [String: [String: String]] = [:]
        var supports: [String: [String: SupportRow]] = [:]
    }
    private static func normalizedStatus(_ raw: String) -> String {
        Set(raw.components(separatedBy: " · ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }).sorted().joined(separator: " · ")
    }
    private static func normalizedHeight(_ raw: String) -> String {
        Double(raw.replacingOccurrences(of: ",", with: ".")).map { String(format: "%.1f", $0) } ?? raw
    }
    private func snapshot() throws -> Snapshot {
        var result = Snapshot()
        for row in try rows("SELECT * FROM stations") {
            result.stations[row[0]] = .init(operatorName: row[1], latitude: Double(row[2]) ?? 0, longitude: Double(row[3]) ?? 0, address: row[4], commune: row.count > 10 ? row[10] : "")
        }
        for row in try rows("SELECT stationID,name,status FROM systems") {
            result.systems[row[0], default: [:]][row[1]] = Self.normalizedStatus(row[2])
        }
        for row in try rows("SELECT stationID,supportID,height,azimuths FROM supports") {
            result.supports[row[0], default: [:]][row[1]] = .init(height: Self.normalizedHeight(row[2]), azimuths: ANFRValues.azimuths(row[3]))
        }
        return result
    }
    /// Compares this database with the previous publication. Returns nil when the previous base uses an older schema.
    public func changeReport(since previous: URL) throws -> ChangeReport? {
        let old = try AntennaDatabase(url: previous)
        guard try old.rows("PRAGMA user_version").first?.first == "2" else { return nil }
        let before = try old.snapshot(), after = try snapshot()
        var changes: [StationChange] = []
        for id in Set(before.stations.keys).union(after.stations.keys).sorted() {
            let oldSystems = before.systems[id] ?? [:], newSystems = after.systems[id] ?? [:]
            switch (before.stations[id], after.stations[id]) {
            case (nil, let station?):
                changes.append(StationChange(id: id, kind: .added, operatorName: station.operatorName, latitude: station.latitude, longitude: station.longitude, address: station.address, commune: station.commune, addedSystems: newSystems.keys.sorted()))
            case (let station?, nil):
                changes.append(StationChange(id: id, kind: .removed, operatorName: station.operatorName, latitude: station.latitude, longitude: station.longitude, address: station.address, commune: station.commune, removedSystems: oldSystems.keys.sorted()))
            case (let was?, let station?):
                let added = Set(newSystems.keys).subtracting(oldSystems.keys).sorted()
                let removed = Set(oldSystems.keys).subtracting(newSystems.keys).sorted()
                let statuses = Set(oldSystems.keys).intersection(newSystems.keys).sorted().compactMap { name -> StationChange.StatusChange? in
                    let from = oldSystems[name] ?? "", to = newSystems[name] ?? ""
                    return from == to ? nil : .init(system: name, from: from, to: to)
                }
                var details: [String] = []
                let oldSupports = before.supports[id] ?? [:], newSupports = after.supports[id] ?? [:]
                let common = Set(oldSupports.keys).intersection(newSupports.keys)
                if common.contains(where: { oldSupports[$0]?.azimuths != newSupports[$0]?.azimuths }) { details.append("orientation") }
                if common.contains(where: { oldSupports[$0]?.height != newSupports[$0]?.height }) { details.append("height") }
                if abs(was.latitude - station.latitude) > 0.0003 || abs(was.longitude - station.longitude) > 0.0003 { details.append("location") }
                if Set(oldSupports.keys) != Set(newSupports.keys) { details.append("supports") }
                guard !added.isEmpty || !removed.isEmpty || !statuses.isEmpty || !details.isEmpty else { continue }
                changes.append(StationChange(id: id, kind: .modified, operatorName: station.operatorName, latitude: station.latitude, longitude: station.longitude, address: station.address, commune: station.commune, addedSystems: added, removedSystems: removed, statusChanges: statuses, details: details))
            default: continue
            }
        }
        return ChangeReport(sourceDate: try sourceDate(), previousDate: try old.sourceDate(), changes: changes)
    }
}

// MARK: - Notifications

/// A watched place. Each radius is optional: nil means that kind of alert is off for this zone.
public struct AlertZone: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var latitude: Double
    public var longitude: Double
    /// New stations, or new frequencies on an existing station.
    public var newAntennasKM: Double?
    /// Any other change: frequency removed, status, orientation, height, station removed.
    public var changesKM: Double?
    public init(id: UUID = UUID(), name: String, latitude: Double, longitude: Double, newAntennasKM: Double? = 5, changesKM: Double? = nil) {
        self.id = id; self.name = name; self.latitude = latitude; self.longitude = longitude
        self.newAntennasKM = newAntennasKM; self.changesKM = changesKM
    }
    public var isActive: Bool { newAntennasKM != nil || changesKM != nil }
    public func distance(to change: StationChange) -> Double {
        Geometry.distanceMeters(lat1: latitude, lon1: longitude, lat2: change.latitude, lon2: change.longitude)
    }
}

public struct AlertPreferences: Sendable {
    public var data: Bool
    public var zones: [AlertZone]
    public var favorites: Set<String>
    public init(data: Bool, zones: [AlertZone], favorites: Set<String>) { self.data = data; self.zones = zones; self.favorites = favorites }
}

public struct AlertMessage: Sendable, Equatable {
    public enum Category: String, Codable, Sendable { case data, favorites, zone, zoneChanges }
    public let category: AlertMessage.Category
    public let title: String
    public let body: String
}

/// One line of the "Dernières alertes" screen.
public struct AlertItem: Codable, Sendable, Identifiable, Equatable {
    public var id: String { category.rawValue + ":" + stationID }
    public let category: AlertMessage.Category
    public let stationID: String
    public let title: String
    public let detail: String
    public let removed: Bool
}

public struct AlertHistory: Codable, Sendable {
    public let sourceDate: String
    public let items: [AlertItem]
    public init(sourceDate: String, items: [AlertItem]) { self.sourceDate = sourceDate; self.items = items }
}

public enum AlertDigest {
    private struct Match { let change: StationChange; let zone: AlertZone; let distance: Double }

    /// The same text for everyone: sent by push from GitHub Actions, or posted locally when push isn't available.
    public static func publication(sourceDate: String, report: ChangeReport?) -> AlertMessage {
        var body = "Publication du " + longDate(sourceDate)
        if let report {
            let parts = [(report.added, "ajoutée"), (report.removed, "retirée"), (report.modified, "modifiée")].filter { $0.0 > 0 }.enumerated().map { index, part in count(of: part.0, index == 0 ? "station" : nil, part.1) }
            body += parts.isEmpty ? ". Aucune station ajoutée, retirée ou modifiée." : " : " + joined(parts) + " en France."
        } else { body += "." }
        body += "\nOuvre Pylo en Wi-Fi pour récupérer la nouvelle base."
        return AlertMessage(category: .data, title: "Nouvelles données ANFR", body: body)
    }

    /// Builds the personal notifications for one publication. `report` is nil when the publication has no changes.json.
    public static func messages(sourceDate: String, report: ChangeReport?, preferences: AlertPreferences) -> (messages: [AlertMessage], history: AlertHistory) {
        var messages: [AlertMessage] = [], items: [AlertItem] = []
        if preferences.data { messages.append(publication(sourceDate: sourceDate, report: report)) }
        let changes = report?.changes ?? []

        let followed = changes.filter { preferences.favorites.contains($0.id) }
        for change in followed {
            items.append(AlertItem(category: .favorites, stationID: change.id, title: heading(change), detail: capitalized(summary(change)) + ".", removed: change.kind == .removed))
        }
        if followed.count == 1, let change = followed.first {
            messages.append(AlertMessage(category: .favorites, title: change.kind == .removed ? "Station favorite retirée" : "Changement sur une station favorite", body: heading(change) + "\n" + capitalized(summary(change)) + "."))
        } else if followed.count > 1 {
            messages.append(AlertMessage(category: .favorites, title: "\(followed.count) stations favorites ont changé", body: list(followed.map { heading($0) + " : " + summary($0) })))
        }

        let zones = preferences.zones.filter(\.isActive)
        func closest(_ change: StationChange, _ radius: KeyPath<AlertZone, Double?>) -> Match? {
            zones.compactMap { zone -> Match? in
                guard let km = zone[keyPath: radius] else { return nil }
                let distance = zone.distance(to: change)
                return distance <= km * 1000 ? Match(change: change, zone: zone, distance: distance) : nil
            }.min { $0.distance < $1.distance }
        }
        let others = changes.filter { !preferences.favorites.contains($0.id) }
        let fresh = others.filter { $0.kind == .added || ($0.kind == .modified && !$0.addedSystems.isEmpty) }
            .compactMap { closest($0, \.newAntennasKM) }.sorted { $0.distance < $1.distance }
        let freshIDs = Set(fresh.map(\.change.id))
        let modified = others.filter { $0.kind != .added && !freshIDs.contains($0.id) }
            .compactMap { closest($0, \.changesKM) }.sorted { $0.distance < $1.distance }

        for match in fresh {
            items.append(AlertItem(category: .zone, stationID: match.change.id, title: heading(match.change), detail: capitalized(novelty(match.change)) + ", à " + formatDistance(match.distance) + " de " + match.zone.name + ".", removed: false))
        }
        for match in modified {
            items.append(AlertItem(category: .zoneChanges, stationID: match.change.id, title: heading(match.change), detail: capitalized(summary(match.change)) + ", à " + formatDistance(match.distance) + " de " + match.zone.name + ".", removed: match.change.kind == .removed))
        }
        if let message = zoneMessage(fresh, category: .zone, one: { _ in "Nouvelle antenne" }, many: { "\($0) nouvelles antennes" }, text: novelty) { messages.append(message) }
        if let message = zoneMessage(modified, category: .zoneChanges, one: { $0.kind == .removed ? "Antenne retirée" : "Antenne modifiée" }, many: { "\($0) antennes modifiées" }, text: summary) { messages.append(message) }
        return (messages, AlertHistory(sourceDate: sourceDate, items: items))
    }

    private static func zoneMessage(_ matches: [Match], category: AlertMessage.Category, one: (StationChange) -> String, many: (Int) -> String, text: (StationChange) -> String) -> AlertMessage? {
        guard let first = matches.first else { return nil }
        let names = Set(matches.map(\.zone.name))
        let place = names.count == 1 ? " · " + first.zone.name : " dans tes zones"
        if matches.count == 1 {
            let address = ANFRAddress.full(first.change.address, commune: first.change.commune)
            return AlertMessage(category: category, title: one(first.change) + place, body: operatorDisplayName(first.change.operatorName) + ", à " + formatDistance(first.distance) + " du centre" + (address.isEmpty ? "" : "\n" + address) + "\n" + capitalized(text(first.change)) + ".")
        }
        return AlertMessage(category: category, title: many(matches.count) + place, body: list(matches.map { match in
            heading(match.change) + " (" + formatDistance(match.distance) + (names.count > 1 ? " de " + match.zone.name : "") + ") : " + text(match.change)
        }))
    }

    static func heading(_ change: StationChange) -> String {
        let place = change.commune.isEmpty ? ANFRAddress.readable(change.address) : change.commune
        return operatorDisplayName(change.operatorName) + (place.isEmpty ? "" : ", " + place)
    }
    static func novelty(_ change: StationChange) -> String {
        let labels = Radio.bands(change.addedSystems)
        if change.kind == .added { return "nouvelle station en " + labels }
        return (change.addedSystems.count > 1 ? "nouvelles fréquences : " : "nouvelle fréquence : ") + labels
    }
    /// "5G 3500 MHz ajoutée, 4G 800 MHz mise en service"
    static func summary(_ change: StationChange) -> String {
        if change.kind == .removed { return "la station n’apparaît plus dans les données de l’ANFR" }
        if change.kind == .added { return novelty(change) }
        func agreed(_ systems: [String], _ participle: String) -> String { Radio.bands(systems) + " " + participle + (systems.count > 1 ? "s" : "") }
        var parts: [String] = []
        if !change.addedSystems.isEmpty { parts.append(agreed(change.addedSystems, "ajoutée")) }
        if !change.removedSystems.isEmpty { parts.append(agreed(change.removedSystems, "retirée")) }
        var remaining = change.statusChanges
        func take(_ test: (StationChange.StatusChange) -> Bool) -> [String] {
            let matched = remaining.filter(test); remaining.removeAll(where: test); return matched.map(\.system)
        }
        let opened = take { $0.to.contains("En service") && !$0.from.contains("En service") }
        if !opened.isEmpty { parts.append(agreed(opened, "mise") + " en service") }
        let ready = take { $0.to.contains("Techniquement opérationnel") && !$0.to.contains("En service") && !$0.from.contains("Techniquement opérationnel") }
        if !ready.isEmpty { parts.append(agreed(ready, "installée") + ", pas encore en service") }
        let back = take { $0.to == "Projet approuvé" }
        if !back.isEmpty { parts.append(agreed(back, "repassée") + " au stade de projet") }
        for status in remaining { parts.append(Radio.label(status.system) + " désormais « " + status.to + " »") }
        let details = ["orientation": "orientation des antennes modifiée", "height": "hauteur du support modifiée", "location": "position de la station corrigée", "supports": "supports modifiés"]
        parts += change.details.compactMap { details[$0] }
        return parts.isEmpty ? "informations mises à jour" : parts.joined(separator: ", ")
    }
    static func list(_ lines: [String]) -> String {
        let shown = lines.prefix(3).map { "• " + $0 }
        let rest = lines.count - shown.count
        return (shown + (rest > 0 ? ["Et \(rest) autre\(rest > 1 ? "s" : ""). Touche pour tout voir."] : [])).joined(separator: "\n")
    }
    static func joined(_ items: [String], last: String = " et ") -> String {
        items.count <= 1 ? (items.first ?? "") : items.dropLast().joined(separator: ", ") + last + items.last!
    }
    static func capitalized(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }
    /// "214 stations ajoutées", or "37 retirées" when the noun was already said.
    static func count(of value: Int, _ noun: String?, _ adjective: String) -> String {
        let number = value.formatted(.number.locale(Locale(identifier: "fr_FR")))
        let plural = value > 1 ? "s" : ""
        return [number, noun.map { $0 + plural }, adjective + plural].compactMap { $0 }.joined(separator: " ")
    }
    public static func formatDistance(_ meters: Double) -> String {
        if meters < 1000 { return "\(max(10, Int((meters / 10).rounded()) * 10)) m" }
        let km = meters / 1000
        return (km < 10 ? String(format: "%.1f", km).replacingOccurrences(of: ".", with: ",") : String(Int(km.rounded()))) + " km"
    }
    public static func longDate(_ iso: String) -> String {
        let parser = DateFormatter(); parser.locale = Locale(identifier: "en_US_POSIX"); parser.timeZone = TimeZone(secondsFromGMT: 0); parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: String(iso.prefix(10))) else { return iso }
        let output = DateFormatter(); output.locale = Locale(identifier: "fr_FR"); output.timeZone = parser.timeZone; output.dateFormat = "d MMMM yyyy"
        return output.string(from: date)
    }
}

extension Radio {
    /// ["LTE 800", "5G NR 3500", "LTE 2600", "5G NR 700"] → "5G 700 · 3500 MHz et 4G 800 · 2600 MHz"
    public static func bands(_ systems: [String]) -> String {
        let order = ["5G", "4G", "3G", "2G"]
        var known: [String: [Int]] = [:], other: [String] = []
        for system in Set(systems) {
            let generation = generation(system)
            if order.contains(generation), let band = system.split(separator: " ").last.flatMap({ Int($0) }) { known[generation, default: []].append(band) }
            else { other.append(system) }
        }
        let groups = order.compactMap { g in known[g].map { g + " " + $0.sorted().map(String.init).joined(separator: " · ") + " MHz" } }
        return AlertDigest.joined(groups + other.sorted())
    }
    /// "LTE 800" → "4G 800 MHz"
    public static func label(_ system: String) -> String {
        let generation = generation(system)
        guard let band = system.split(separator: " ").last, Int(band) != nil else { return system }
        return (generation == "Inconnue" ? system : generation + " " + band) + " MHz"
    }
}

extension Geometry {
    public static func distanceMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6_371_000.0, p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dp = (lat2 - lat1) * .pi / 180, dl = (lon2 - lon1) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }
}
