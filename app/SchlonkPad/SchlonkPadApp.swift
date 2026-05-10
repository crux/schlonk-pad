import SwiftUI

@main
struct SchlonkPadApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 380, idealWidth: 420, minHeight: 200)
        }
        .windowResizability(.contentSize)
    }
}
