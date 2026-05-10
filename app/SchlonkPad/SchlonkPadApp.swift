import SwiftUI

@main
struct SchlonkPadApp: App {
    @StateObject private var store = DownloadStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 380, idealWidth: 420, minHeight: 200)
        }
        .windowResizability(.contentSize)
    }
}
