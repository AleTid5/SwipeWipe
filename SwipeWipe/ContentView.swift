import SwiftUI
import UIKit

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
    }

    private var photoAccessRequired: some View {
        VStack(spacing: 18) {
            Image(systemName: "photo.stack")
                .font(.system(size: 52))
                .foregroundStyle(.tint)

            Text("Full Photos Access Required")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text(accessExplanation)
                .font(.body)
                .foregroundStyle(.secondary)
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

            Button("Check access again") {
                Task { await model.refreshAndProcess() }
            }
            .buttonStyle(.bordered)
        }
        .padding(28)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
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
