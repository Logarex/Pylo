import SwiftUI
@main struct PyloApp: App {
    @State private var store = AppStore()
    var body: some Scene { WindowGroup { ContentView().environment(store).tint(.blue) } }
}
