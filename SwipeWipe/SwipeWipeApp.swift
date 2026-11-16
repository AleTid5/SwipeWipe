import SwiftUI

@main
struct SwipeWipeApp: App {
    @StateObject private var model = SwipeWipeModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
    }
}
