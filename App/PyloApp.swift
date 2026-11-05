import SwiftUI
@main struct PyloApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = AppStore()
    var body: some Scene {
        WindowGroup { ContentView().environment(store).environment(\.locale, Locale(identifier: "fr_FR")).tint(Palette.accent) }
            .backgroundTask(.appRefresh(AlertChecker.taskID)) {
                AlertChecker.schedule()
                await AlertChecker.run()
            }
    }
}
