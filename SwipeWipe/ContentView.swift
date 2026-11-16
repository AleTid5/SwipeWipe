import SwiftUI
import UIKit

/// User-selectable appearance. Dark is the default cyberpunk cockpit look.
enum SwipeWipeAppearance: String, CaseIterable, Identifiable {
    case dark
    case light

    var id: String { rawValue }
    var title: String { self == .dark ? "Dark" : "Light" }
    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
}

/// Shared neon palette used by every screen to keep the UI visually consistent.
struct CyberpunkPalette {
    let isDark: Bool

    init(colorScheme: ColorScheme) {
        isDark = colorScheme == .dark
    }

    var background: Color { Color(hex: isDark ? 0x070A10 : 0xF2F0E8) }
    var surface: Color { Color(hex: isDark ? 0x101722 : 0xFFFFFF) }
    var raisedSurface: Color { Color(hex: isDark ? 0x172231 : 0xE6E9E7) }
    var text: Color { Color(hex: isDark ? 0xF4F7FA : 0x141B24) }
    var muted: Color { Color(hex: isDark ? 0x9AAABD : 0x5F6B78) }
    var cyan: Color { Color(hex: isDark ? 0x00E5FF : 0x007F99) }
    var magenta: Color { Color(hex: isDark ? 0xFF2EA6 : 0xC00070) }
    var yellow: Color { Color(hex: isDark ? 0xFFE600 : 0xA88400) }
    var green: Color { Color(hex: isDark ? 0x45F2A4 : 0x087D52) }
    var red: Color { Color(hex: isDark ? 0xFF5477 : 0xC51D48) }
    var outline: Color { cyan.opacity(isDark ? 0.38 : 0.30) }

    var backdrop: LinearGradient {
        LinearGradient(
            colors: [background, surface.opacity(isDark ? 0.92 : 0.72), background],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension Color {
    init(hex: UInt) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension View {
    @ViewBuilder
    func badgeWhenNonzero(_ count: Int) -> some View {
        if count > 0 {
            self.badge(count)
        } else {
            self
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var model: SwipeWipeModel
    @Environment(\.colorScheme) private var colorScheme
    private var palette: CyberpunkPalette { CyberpunkPalette(colorScheme: colorScheme) }
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !model.hasCheckedAuthorization {
                ProgressView("Checking Photos access…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.hasFullPhotoAccess {
                mainTabs
            } else {
                photoAccessRequired
            }
        }
        .background(palette.background.ignoresSafeArea())
        .tint(palette.cyan)
        .task { await model.loadPhotos() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.refreshAndProcess() }
            }
        }
    }

    private var mainTabs: some View {
        TabView {
            NavigationStack { ReviewView() }
                .tabItem { Label("Review", systemImage: "rectangle.stack") }

            NavigationStack { QueueView() }
            .tabItem { Label("Delete queue", systemImage: "clock.arrow.circlepath") }
            .badgeWhenNonzero(model.pendingDeletes.count)

            NavigationStack { DuplicatesView() }
                .tabItem { Label("Duplicates", systemImage: "square.on.square") }

            NavigationStack { SettingsView() }
                .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        }
        .tint(palette.cyan)
        .toolbarBackground(palette.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .background(palette.background)
    }

    private var photoAccessRequired: some View {
        VStack(spacing: 18) {
            Image(systemName: "photo.stack")
                .font(.system(size: 52))
                .foregroundStyle(palette.cyan)

            Text("Full Photos Access Required")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text(accessExplanation)
                .font(.body)
                .foregroundStyle(palette.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Open Settings", systemImage: "gear")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.cyan)

            Button("Check access again") {
                Task { await model.refreshAndProcess() }
            }
            .buttonStyle(.bordered)
        }
        .padding(28)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.backdrop.ignoresSafeArea())
    }

    private var accessExplanation: String {
        if model.authorizationStatus == .limited {
            return "SwipeWipe needs Full Access to review and organize your entire photo library. Limited Access doesn't include every photo. Open Settings, choose SwipeWipe → Photos, and change access to Full Access."
        }
        if model.authorizationStatus == .denied || model.authorizationStatus == .restricted {
            return "SwipeWipe needs Full Access to your photo library. Open Settings, choose SwipeWipe → Photos, and enable Full Access. Return here and tap Check access again."
        }
        return "Allow Full Access to your photo library so SwipeWipe can review, identify duplicates, and manage photos across your library."
    }
}
