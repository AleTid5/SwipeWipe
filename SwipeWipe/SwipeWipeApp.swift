import SwiftUI

@main
struct SwipeWipeApp: App {
    @StateObject private var model = SwipeWipeModel()
    @AppStorage("swipewipe.appearanceMode") private var appearanceModeRaw = SwipeWipeAppearance.dark.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .preferredColorScheme(
                    SwipeWipeAppearance(rawValue: appearanceModeRaw)?.colorScheme ?? .dark
                )
        }
    }
}
