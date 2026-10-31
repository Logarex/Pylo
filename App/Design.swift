import SwiftUI
import CoreTelephony
import Network

enum Palette {
    static let accent = Color("AccentColor")
    static func operatorColor(_ name: String) -> Color {
        if name.contains("ORANGE") { return .orange }
        if name.contains("FREE") { return Color(red: 0.16, green: 0.17, blue: 0.20) }
        if name == "SFR" || name == "SRR" { return Color(red: 0.90, green: 0.04, blue: 0.16) }
        if name.contains("BOUYGUES") { return Color(red: 0, green: 0.57, blue: 0.68) }
        let seed = name.utf8.reduce(0) { ($0 * 31 + Int($1)) % 997 }
        return Color(hue: Double(seed % 360) / 360, saturation: 0.7, brightness: 0.65)
    }
    static func generation(_ name: String) -> Color {
        switch name { case "2G": .brown; case "3G": .indigo; case "4G": .teal; default: accent }
    }
}
struct InfoCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    init(_ title: String, subtitle: String = "", @ViewBuilder content: () -> Content) { self.title = title; self.subtitle = subtitle; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 5) { Text(title).font(.title3.bold()); if !subtitle.isEmpty { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) } }
            content
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
    }
}
@MainActor @Observable final class DeviceNetworkInfo {
    private let telephony = CTTelephonyNetworkInfo()
    private let monitor = NWPathMonitor()
    var connection = "Vérification…"
    var expensive = false
    var constrained: Bool?
    var lastUpdated: Date?
    private var hasPath = false
    @ObservationIgnored private var radioTask: Task<Void, Never>?
    var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
    var connectionIcon: String { connection == "Wi-Fi" ? "wifi" : connection == "Réseau mobile" ? "antenna.radiowaves.left.and.right" : "network" }
    var radioStatus: String { technologies.isEmpty ? (isSimulator ? "Indisponible sur simulateur" : "Non transmis par iOS") : technologies.joined(separator: " · ") }
    var radioExplanation: String {
        if isSimulator { return "Le simulateur ne possède pas de modem cellulaire. La technologie 2G/3G/4G/5G doit être vérifiée sur un vrai iPhone." }
        if technologies.isEmpty { return "iOS n’a pas fourni la technologie cellulaire à Pylo lors de cette lecture. Cela ne signifie pas que tu n’as pas de réseau. Le menu Field Test peut donner plus d’informations." }
        return "Technologies déclarées par les lignes SIM disponibles. Elles ne décrivent pas forcément la connexion qui transporte ton trafic internet, notamment en Wi-Fi."
    }
    var reducedDataStatus: String {
        guard let constrained else { return hasPath ? "Sans connexion active" : "Vérification…" }
        return constrained ? "Activé sur cette connexion" : "Désactivé sur cette connexion"
    }
    var technologies: [String] = []
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in self?.apply(path) }
        }
        monitor.start(queue: DispatchQueue(label: "fr.logarex.pylo.network"))
        radioTask = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .CTServiceRadioAccessTechnologyDidChange).map({ _ in true }) {
                guard let self else { return }
                self.refreshRadio()
            }
        }
        refreshRadio()
    }
    private func apply(_ path: NWPath) {
        hasPath = true
        connection = path.status != .satisfied ? "Hors ligne" : path.usesInterfaceType(.wifi) ? "Wi-Fi" : path.usesInterfaceType(.cellular) ? "Réseau mobile" : "Autre connexion"
        expensive = path.isExpensive
        constrained = path.status == .satisfied ? path.isConstrained : nil
        refreshRadio()
    }
    func refresh() {
        if hasPath { apply(monitor.currentPath) }
        else { refreshRadio() }
    }
    func refreshRadio() {
        lastUpdated = Date()
        technologies = Array(Set((telephony.serviceCurrentRadioAccessTechnology ?? [:]).values.map { value in
            switch value {
            case CTRadioAccessTechnologyGPRS: return "2G · GPRS"
            case CTRadioAccessTechnologyEdge: return "2G · EDGE"
            case CTRadioAccessTechnologyWCDMA: return "3G · UMTS"
            case CTRadioAccessTechnologyHSDPA: return "3G · HSDPA"
            case CTRadioAccessTechnologyHSUPA: return "3G · HSUPA"
            case CTRadioAccessTechnologyLTE: return "4G · LTE"
            case CTRadioAccessTechnologyNRNSA: return "5G NR · NSA"
            case CTRadioAccessTechnologyNR: return "5G NR"
            default: return value.replacingOccurrences(of: "CTRadioAccessTechnology", with: "")
            }
        })).sorted()
    }
    deinit { radioTask?.cancel(); monitor.cancel() }
}
func operatorDisplayName(_ name: String) -> String {
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
