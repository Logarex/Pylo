import SwiftUI
import MapKit
import UserNotifications
import BackgroundTasks
import FirebaseCore
import FirebaseMessaging

enum AlertKeys {
    static let data = "alertData", favorites = "alertFavorites", zones = "alertZones"
    /// Date of the last ANFR publication already handled (yyyy-MM-dd).
    static let lastDate = "alertLastSourceDate"
    /// Topics this device is subscribed to, as last confirmed by Firebase.
    static let pushData = "pushTopicData", pushChanges = "pushTopicChanges"
    static func savedZones() -> [AlertZone] {
        UserDefaults.standard.data(forKey: zones).flatMap { try? JSONDecoder().decode([AlertZone].self, from: $0) } ?? []
    }
}

/// Builds the alerts on the iPhone. GitHub only serves the manifest and changes.json, the same files for everyone,
/// so the zones and favorites never leave the device.
enum AlertChecker {
    static let taskID = "org.epimac.pylo.alerts"
    static var needsChanges: Bool {
        UserDefaults.standard.bool(forKey: AlertKeys.favorites) || AlertKeys.savedZones().contains(where: \.isActive)
    }
    static var anyEnabled: Bool { UserDefaults.standard.bool(forKey: AlertKeys.data) || needsChanges }
    /// Fallback when a push is lost: iOS picks the time, usually several times a day for an app used regularly.
    static func schedule() {
        guard anyEnabled else { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskID); return }
        let request = BGAppRefreshTaskRequest(identifier: taskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
    /// The first check after enabling alerts must not announce data the user already has.
    static func setBaseline(sourceDate: String) {
        if UserDefaults.standard.string(forKey: AlertKeys.lastDate) == nil, !sourceDate.isEmpty {
            UserDefaults.standard.set(sourceDate, forKey: AlertKeys.lastDate)
        }
    }
    static func run() async {
        let defaults = UserDefaults.standard
        guard anyEnabled else { return }
        do {
            let manifest = try await DataUpdates.fetchManifest()
            guard manifest.sourceDate > (defaults.string(forKey: AlertKeys.lastDate) ?? "") else { return }
            let favorites = defaults.bool(forKey: AlertKeys.favorites) ? Set(defaults.stringArray(forKey: "favorites") ?? []) : []
            let zones = AlertKeys.savedZones().filter(\.isActive)
            // When the device follows the anfr-data topic, that alert already came by push.
            let preferences = AlertPreferences(data: defaults.bool(forKey: AlertKeys.data) && !defaults.bool(forKey: AlertKeys.pushData), zones: zones, favorites: favorites)
            // A network error here leaves the publication unhandled, so the next wake-up tries again.
            let report = !zones.isEmpty || !favorites.isEmpty ? try await DataUpdates.fetchChanges(manifest) : nil
            let result = AlertDigest.messages(sourceDate: manifest.sourceDate, report: report, preferences: preferences)
            let center = UNUserNotificationCenter.current()
            let status = await center.notificationSettings().authorizationStatus
            if status == .authorized || status == .provisional {
                for message in result.messages {
                    let content = UNMutableNotificationContent()
                    content.title = message.title
                    content.body = message.body
                    content.sound = .default
                    content.threadIdentifier = message.category.rawValue
                    content.userInfo = ["category": message.category.rawValue]
                    try await center.add(UNNotificationRequest(identifier: manifest.sourceDate + "-" + message.category.rawValue, content: content, trigger: nil))
                }
            }
            if !result.history.items.isEmpty { AlertHistoryStore.save(result.history) }
            defaults.set(manifest.sourceDate, forKey: AlertKeys.lastDate)
        } catch {}
    }
}

/// Firebase Cloud Messaging, free. The device only joins two public topics:
/// anfr-data (visible alert, same text for everyone) and anfr-changes (silent signal that wakes Pylo).
/// Google never receives the zones or the favorites.
@MainActor enum PushService {
    static var isAvailable: Bool { FirebaseApp.app() != nil }
    /// Without GoogleService-Info.plist, Pylo keeps working with background refresh only.
    static func configure() {
        guard FirebaseApp.app() == nil, Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil else { return }
        FirebaseApp.configure()
    }
    static func sync() {
        guard isAvailable else { return }
        let wantsData = UserDefaults.standard.bool(forKey: AlertKeys.data)
        let wantsChanges = AlertChecker.needsChanges
        if wantsData || wantsChanges { UIApplication.shared.registerForRemoteNotifications() }
        guard Messaging.messaging().apnsToken != nil else { return }
        update(topic: "anfr-data", wanted: wantsData, key: AlertKeys.pushData)
        update(topic: "anfr-changes", wanted: wantsChanges, key: AlertKeys.pushChanges)
    }
    private static func update(topic: String, wanted: Bool, key: String) {
        guard UserDefaults.standard.bool(forKey: key) != wanted else { return }
        if wanted {
            Messaging.messaging().subscribe(toTopic: topic) { error in
                if error == nil { UserDefaults.standard.set(true, forKey: key) }
            }
        } else {
            // Marked off right away: a duplicate alert is better than a missing one.
            UserDefaults.standard.set(false, forKey: key)
            Messaging.messaging().unsubscribe(fromTopic: topic)
        }
    }
}

enum AlertHistoryStore {
    private static var url: URL { URL.applicationSupportDirectory.appendingPathComponent("alerts.json") }
    static func load() -> AlertHistory? { (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(AlertHistory.self, from: $0) } }
    static func save(_ history: AlertHistory) {
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        try? JSONEncoder().encode(history).write(to: url, options: .atomic)
    }
}

/// Opens the list of recent alerts when a notification is tapped.
@MainActor @Observable final class AlertInbox {
    static let shared = AlertInbox()
    var showRecent = false
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        PushService.configure()
        if PushService.isAvailable { Messaging.messaging().delegate = self }
        PushService.sync()
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        guard PushService.isAvailable else { return }
        Messaging.messaging().apnsToken = deviceToken
        PushService.sync()
    }
    /// Silent push on anfr-changes: a new publication is online, build the zone and favorite alerts now.
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        await AlertChecker.run()
        return .newData
    }
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in PushService.sync() }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let category = response.notification.request.content.userInfo["category"] as? String
        // The data alert just opens Pylo, which checks for the new base on its own.
        guard let category, category != AlertMessage.Category.data.rawValue else { return }
        await MainActor.run { AlertInbox.shared.showRecent = true }
    }
}

extension AppStore {
    func alertSettingsChanged() {
        AlertChecker.schedule()
        PushService.sync()
    }
    func checkAlerts() async {
        if let lastAlertCheck, Date().timeIntervalSince(lastAlertCheck) < 3600 { return }
        lastAlertCheck = Date()
        await AlertChecker.run()
    }
    func requestAlertPermission() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        if granted { AlertChecker.setBaseline(sourceDate: dataSourceDate) }
        return granted
    }
}

enum ZoneRadius {
    static let choices: [Double] = [0.5, 1, 2, 3, 5, 10, 20, 50]
    static func label(_ km: Double) -> String { km < 1 ? "\(Int(km * 1000)) m" : "\(Int(km)) km" }
    static func summary(_ zone: AlertZone) -> String {
        let parts = [zone.newAntennasKM.map { "nouvelles antennes à " + label($0) }, zone.changesKM.map { "changements à " + label($0) }].compactMap { $0 }
        return parts.isEmpty ? "En pause" : AlertDigest.capitalized(parts.joined(separator: " · "))
    }
}

struct AlertsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var authorization: UNAuthorizationStatus = .notDetermined
    @State private var refreshStatus: UIBackgroundRefreshStatus = .available
    @State private var history: AlertHistory?
    @State private var editing: UUID?
    private var anyEnabled: Bool { store.alertData || store.alertFavorites || store.alertZones.contains(where: \.isActive) }

    var body: some View {
        List {
            Section {
                Text("Pylo peut te prévenir quand l’ANFR publie de nouvelles données, quand une antenne apparaît près d’un lieu que tu choisis, ou quand une de tes stations change.")
            }
            if authorization == .denied {
                Section {
                    Label("Les notifications de Pylo sont désactivées dans Réglages.", systemImage: "bell.slash")
                    Button("Ouvrir les réglages de notifications") { openURL(URL(string: UIApplication.openNotificationSettingsURLString)!) }
                }
            }
            if anyEnabled && refreshStatus != .available {
                Section {
                    Label("L’actualisation en arrière-plan est coupée pour Pylo, ou par le mode économie d’énergie. Les alertes de zone et de favoris n’arriveront qu’en ouvrant l’app.", systemImage: "exclamationmark.triangle")
                    Button("Ouvrir Réglages") { openURL(URL(string: UIApplication.openSettingsURLString)!) }
                }
            }
            Section {
                Toggle("Nouvelles données ANFR", isOn: alert(\.alertData))
            } footer: {
                Text("Environ une fois par semaine, avec le nombre de stations ajoutées, retirées et modifiées en France.")
            }
            Section {
                Toggle("Changements sur mes favoris", isOn: alert(\.alertFavorites))
            } footer: {
                Text(store.favorites.isEmpty
                     ? "Tu n’as pas encore de favori. Tu peux en ajouter depuis la fiche d’une station."
                     : "\(store.favorites.count) station\(store.favorites.count > 1 ? "s" : "") suivie\(store.favorites.count > 1 ? "s" : ""). Fréquence ajoutée ou retirée, mise en service, orientation, hauteur, ou station retirée des données.")
            }
            Section {
                ForEach(store.alertZones) { zone in
                    NavigationLink {
                        ZoneEditor(zone: zone)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(zone.name).font(.headline)
                            Text(ZoneRadius.summary(zone)).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { store.alertZones.remove(atOffsets: $0) }
                Button("Ajouter une zone", systemImage: "plus.circle") { addZone() }
            } header: {
                Text("Zones surveillées")
            } footer: {
                Text("Pour chaque zone, tu choisis un rayon pour les nouvelles antennes et un autre pour les changements. Les zones restent sur ton iPhone : Pylo télécharge la liste des changements pour toute la France et fait le tri lui-même.")
            }
            Section("Délai") {
                if PushService.isAvailable {
                    Text("Dès qu’une publication est en ligne, Pylo reçoit un signal. L’alerte de nouvelles données arrive en quelques minutes.")
                    Text("Pour les zones et les favoris, iOS réveille Pylo pour faire le tri. C’est en général rapide, mais iOS peut le repousser si la batterie est faible ou si tu as fermé Pylo en le balayant vers le haut.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("iOS réveille Pylo de temps en temps pour vérifier. L’alerte peut arriver quelques heures après la publication.")
                    Text("Si tu fermes Pylo en le balayant vers le haut, iOS ne le réveille plus avant la prochaine ouverture.")
                        .foregroundStyle(.secondary)
                }
            }
            if let history, !history.items.isEmpty {
                Section {
                    NavigationLink { RecentAlertsView() } label: { LabeledContent("Dernières alertes", value: "\(history.items.count)") }
                } footer: { Text("Publication du \(AlertDigest.longDate(history.sourceDate)).") }
            }
        }
        .navigationTitle("Notifications")
        .navigationDestination(item: $editing) { id in
            if let zone = store.alertZones.first(where: { $0.id == id }) { ZoneEditor(zone: zone) }
        }
        .task { await refreshSystemState() }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await refreshSystemState() } } }
    }

    private func alert(_ keyPath: ReferenceWritableKeyPath<AppStore, Bool>) -> Binding<Bool> {
        Binding {
            store[keyPath: keyPath]
        } set: { enabled in
            guard enabled else { store[keyPath: keyPath] = false; return }
            Task {
                if await store.requestAlertPermission() { store[keyPath: keyPath] = true }
                await refreshSystemState()
            }
        }
    }
    private func addZone() {
        Task {
            guard await store.requestAlertPermission() else { await refreshSystemState(); return }
            let center = store.location.coordinate ?? store.region.center
            let zone = AlertZone(name: "Zone \(store.alertZones.count + 1)", latitude: center.latitude, longitude: center.longitude, newAntennasKM: 5, changesKM: nil)
            store.alertZones.append(zone)
            editing = zone.id
            await refreshSystemState()
        }
    }
    private func refreshSystemState() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        refreshStatus = UIApplication.shared.backgroundRefreshStatus
        history = AlertHistoryStore.load()
    }
}

struct ZoneEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var zone: AlertZone
    @State private var waitingForPosition = false
    init(zone: AlertZone) { _zone = State(initialValue: zone) }

    var body: some View {
        List {
            Section("Nom") {
                TextField("Maison, travail…", text: $zone.name)
            }
            Section {
                ZoneMap(zone: zone)
                    .frame(height: 210)
                    .listRowInsets(EdgeInsets())
                Button("Centrer sur ma position", systemImage: "location") {
                    if let coordinate = store.location.coordinate { move(to: coordinate) }
                    else { waitingForPosition = true; store.location.locate() }
                }
                Button("Centrer sur la carte d’Explorer", systemImage: "map") { move(to: store.region.center) }
                if waitingForPosition { Text("Recherche de ta position…").font(.footnote).foregroundStyle(.secondary) }
            } header: {
                Text("Centre")
            } footer: {
                Text("Pour placer la zone ailleurs, déplace la carte d’Explorer puis reviens ici.")
            }
            radiusSection(title: "Nouvelles antennes", radius: $zone.newAntennasKM, fallback: 5,
                          footer: "Une nouvelle station, ou une nouvelle fréquence sur une station existante.")
            radiusSection(title: "Changements sur les antennes", radius: $zone.changesKM, fallback: 1,
                          footer: "Fréquence retirée, mise en service, orientation ou hauteur modifiée, station retirée des données.")
            Section {
                Button("Supprimer la zone", systemImage: "trash", role: .destructive) {
                    store.alertZones.removeAll { $0.id == zone.id }
                    dismiss()
                }
            }
        }
        .navigationTitle(zone.name.isEmpty ? "Zone" : zone.name)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: zone) {
            guard let index = store.alertZones.firstIndex(where: { $0.id == zone.id }) else { return }
            store.alertZones[index] = zone
        }
        .onChange(of: store.location.positionRevision) {
            if waitingForPosition, let coordinate = store.location.coordinate { waitingForPosition = false; move(to: coordinate) }
        }
    }

    private func radiusSection(title: String, radius: Binding<Double?>, fallback: Double, footer: String) -> some View {
        Section {
            Toggle(title, isOn: Binding(get: { radius.wrappedValue != nil }, set: { radius.wrappedValue = $0 ? fallback : nil }))
            if let value = radius.wrappedValue {
                Picker("Rayon", selection: Binding(get: { value }, set: { radius.wrappedValue = $0 })) {
                    ForEach(ZoneRadius.choices, id: \.self) { Text(ZoneRadius.label($0)).tag($0) }
                }
            }
        } footer: { Text(footer) }
    }
    private func move(to coordinate: CLLocationCoordinate2D) {
        zone.latitude = coordinate.latitude
        zone.longitude = coordinate.longitude
    }
}

/// Filled circle: new antennas. Orange outline: changes.
struct ZoneMap: View {
    let zone: AlertZone
    var body: some View {
        let center = CLLocationCoordinate2D(latitude: zone.latitude, longitude: zone.longitude)
        let widest = max(zone.newAntennasKM ?? 0, zone.changesKM ?? 0, 0.5)
        let latitudeSpan = widest * 2.6 / 111
        let region = MKCoordinateRegion(center: center, span: MKCoordinateSpan(latitudeDelta: latitudeSpan, longitudeDelta: latitudeSpan / max(0.2, cos(zone.latitude * .pi / 180))))
        Map(position: .constant(.region(region)), interactionModes: []) {
            if let km = zone.newAntennasKM {
                MapCircle(center: center, radius: km * 1000)
                    .foregroundStyle(Palette.accent.opacity(0.12))
                    .stroke(Palette.accent, lineWidth: 2)
            }
            if let km = zone.changesKM {
                MapCircle(center: center, radius: km * 1000)
                    .foregroundStyle(.clear)
                    .stroke(.orange, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
            Marker(zone.name, systemImage: "scope", coordinate: center).tint(Palette.accent)
        }
        .id("\(zone.latitude),\(zone.longitude),\(zone.newAntennasKM ?? 0),\(zone.changesKM ?? 0)")
        .accessibilityLabel(ZoneRadius.summary(zone))
    }
}

struct RecentAlertsView: View {
    @Environment(AppStore.self) private var store
    @State private var history = AlertHistoryStore.load()
    @State private var local: [String: Station] = [:]
    private let sections: [(AlertMessage.Category, String)] = [(.favorites, "Mes favoris"), (.zone, "Nouvelles antennes"), (.zoneChanges, "Changements dans mes zones")]
    var body: some View {
        List {
            if let history {
                ForEach(sections, id: \.0) { category, title in
                    let items = history.items.filter { $0.category == category }
                    if !items.isEmpty {
                        Section(title) {
                            ForEach(items) { item in
                                if !item.removed, let station = local[item.stationID] {
                                    NavigationLink { StationDetail(station: station) } label: { row(item) }
                                } else { row(item) }
                            }
                        }
                    }
                }
                if !history.items.isEmpty {
                    Section {
                        Text("Publication de l’ANFR du \(AlertDigest.longDate(history.sourceDate)). La fiche d’une nouvelle station s’ouvre une fois la base mise à jour, en Wi-Fi.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .overlay {
            if history?.items.isEmpty ?? true {
                ContentUnavailableView("Aucune alerte récente", systemImage: "bell", description: Text("Les changements sur tes favoris et dans tes zones apparaîtront ici."))
            }
        }
        .navigationTitle("Dernières alertes")
        .task(id: store.databaseRevision) {
            guard let ids = history?.items.map(\.stationID), !ids.isEmpty,
                  let stations = try? await store.savedStations(ids: Set(ids)) else { return }
            local = Dictionary(stations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }
    private func row(_ item: AlertItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(item.title).font(.headline)
            Text(item.detail).font(.subheadline).foregroundStyle(item.removed ? Color.orange : Color.secondary)
        }.padding(.vertical, 3)
    }
}
