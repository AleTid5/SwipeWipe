import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: SwipeWipeModel

    var body: some View {
        Form {
            Section("Review") {
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
                    .foregroundStyle(.secondary)

                Toggle("Show kept media again", isOn: $model.showKeptAgain)
                Text("When enabled, media you've previously kept can appear in a new review round. They still appear at most once per round.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Deletion safety") {
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
                    .foregroundStyle(.secondary)

                Text("Timing note: iOS may suspend the app in the background. A queued item is removed when its deadline has passed and SwipeWipe is active again; the app cannot guarantee deletion at the exact second while closed.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Label("Full Photos Access is required.", systemImage: "photo.stack")
                Text("SwipeWipe won't start the review interface with Limited Access. You can change this in iPhone Settings → SwipeWipe → Photos → Full Access.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Label("Photo analysis happens on this device.", systemImage: "lock.shield")
                Text("SwipeWipe doesn't upload your photo library. Photo access and deletion are managed by Apple's Photos framework.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("Media in library")
                    Spacer()
                    Text("\(model.assetCount)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                HStack {
                    Text("Kept")
                    Spacer()
                    Text("\(model.keptIDs.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                HStack {
                    Text("Queued for deletion")
                    Spacer()
                    Text("\(model.pendingDeletes.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } header: {
                Text("Library summary")
            }

            Section {
                VStack(spacing: 4) {
                    Text("Developed with ❤️ by Alejandro Tidele")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link("atidele.dev", destination: URL(string: "https://atidele.dev")!)
                        .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Settings")
    }
}
