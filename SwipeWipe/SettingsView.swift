import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: SwipeWipeModel
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("swipewipe.appearanceMode") private var appearanceModeRaw = SwipeWipeAppearance.dark.rawValue
    private var palette: CyberpunkPalette { CyberpunkPalette(colorScheme: colorScheme) }

    var body: some View {
        Form {
            Section {
                Picker("UI appearance", selection: $appearanceModeRaw) {
                    ForEach(SwipeWipeAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                Text("Choose the neon interface theme. Dark uses a deep night palette; Light uses a bright high-contrast control-deck palette.")
                    .font(.footnote)
                    .foregroundStyle(palette.muted)
            } header: {
                Text("INTERFACE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(palette.yellow)
            }
            .listRowBackground(palette.surface)

            Section {
                DatePicker(
                    "Show media from",
                    selection: $model.startDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                Picker("Review order", selection: $model.reviewOrder) {
                    ForEach(ReviewOrder.allCases) { order in
                        Text(order.title).tag(order)
                    }
                }
                Text("Choose whether to review older or newer items first. The default is oldest to newest. The date filter and order apply to photos and videos.")
                    .font(.footnote)
                    .foregroundStyle(palette.muted)

                Toggle("Show kept media again", isOn: $model.showKeptAgain)
                Text("When enabled, media you've previously kept can appear in a new review round. They still appear at most once per round.")
                    .font(.footnote)
                    .foregroundStyle(palette.muted)
            }
            header: {
                Text("REVIEW")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(palette.cyan)
            }
            .listRowBackground(palette.surface)

            Section {
                Picker("Remove after", selection: $model.graceMinutes) {
                    Text("Direct removal").tag(0)
                    ForEach(1...30, id: \.self) { minutes in
                        Text("\(minutes) minute\(minutes == 1 ? "" : "s")").tag(minutes)
                    }
                }
                Text(model.graceMinutes == 0
                     ? "Direct removal collects swiped items into a batch. Open Delete queue and tap Delete Now to remove the whole batch with one Photos confirmation. Once removed, it cannot be undone in SwipeWipe."
                     : "Queued items remain in the Delete queue until the timer expires. SwipeWipe groups photos whose deadlines are close together for up to 15 seconds, then submits them in one Photos deletion request. You can undo them before removal.")
                    .font(.footnote)
                    .foregroundStyle(palette.muted)

                Text("Timing note: iOS may suspend the app in the background. A queued item is removed when its deadline has passed and SwipeWipe is active again; the app cannot guarantee deletion at the exact second while closed.")
                    .font(.footnote)
                    .foregroundStyle(palette.muted)
            }
            header: {
                Text("DELETION SAFETY")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(palette.magenta)
            }
            .listRowBackground(palette.surface)

            Section {
                Label("Full Photos Access is required.", systemImage: "photo.stack")
                Text("SwipeWipe won't start the review interface with Limited Access. You can change this in iPhone Settings → SwipeWipe → Photos → Full Access.")
                    .font(.footnote)
                    .foregroundStyle(palette.muted)
                Label("Photo analysis happens on this device.", systemImage: "lock.shield")
                Text("SwipeWipe doesn't upload your photo library. Photo access and deletion are managed by Apple's Photos framework.")
                    .font(.footnote)
                    .foregroundStyle(palette.muted)
            }
            header: {
                Text("PRIVACY")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(palette.cyan)
            }
            .listRowBackground(palette.surface)

            Section {
                HStack {
                    Text("Media in library")
                    Spacer()
                    Text("\(model.assetCount)")
                        .foregroundStyle(palette.muted)
                        .monospacedDigit()
                }
                HStack {
                    Text("Kept")
                    Spacer()
                    Text("\(model.keptIDs.count)")
                        .foregroundStyle(palette.muted)
                        .monospacedDigit()
                }
                HStack {
                    Text("Queued for deletion")
                    Spacer()
                    Text("\(model.pendingDeletes.count)")
                        .foregroundStyle(palette.muted)
                        .monospacedDigit()
                }
            } header: {
                Text("Library summary")
                    .foregroundStyle(palette.cyan)
            }
            .listRowBackground(palette.surface)

            Section {
                VStack(spacing: 4) {
                    Text("Developed with ❤️ by Alejandro Tidele")
                        .font(.caption)
                        .foregroundStyle(palette.muted)
                    Link("atidele.dev", destination: URL(string: "https://atidele.dev")!)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }
            .listRowBackground(Color.clear)
        }
        .scrollContentBackground(.hidden)
        .background(palette.backdrop)
        .tint(palette.cyan)
        .toolbar(.hidden, for: .navigationBar)
    }
}
