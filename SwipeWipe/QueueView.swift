import SwiftUI

struct QueueView: View {
    @EnvironmentObject private var model: SwipeWipeModel

    var body: some View {
        List {
            if model.pendingDeletes.isEmpty {
                ContentUnavailableView(
                    "Nothing queued",
                    systemImage: "clock.badge.checkmark",
                    description: Text("Photos and videos marked for deletion will appear here until their undo timer expires.")
                )
            } else {
                Section {
                    ForEach(model.pendingDeletes.sorted { $0.dueAt < $1.dueAt }) { item in
                        if let asset = model.asset(with: item.assetID) {
                            HStack(spacing: 12) {
                                PhotoThumbnail(asset: asset)
                                    .frame(width: 76, height: 76)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 5) {
                                    Text((asset.mediaType == .video ? "Video · " : "") + (asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "Media item"))
                                        .font(.subheadline.weight(.semibold))
                                    Text(countdown(for: item))
                                        .font(.caption)
                                        .foregroundStyle(!item.isManualBatchItem && item.dueAt <= model.now ? .red : .secondary)
                                    HStack(spacing: 12) {
                                        Button("Undo deletion") {
                                            model.undoDeletion(for: item.assetID)
                                        }
                                        .font(.caption.weight(.semibold))
                                        if !item.isManualBatchItem && item.dueAt <= model.now {
                                            Button("Retry now") {
                                                Task { await model.retryExpiredDeletes() }
                                            }
                                            .font(.caption.weight(.semibold))
                                        }
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    HStack {
                        Text("Pending removal")
                        Spacer()
                        Button("Undo all") { model.undoAllDeletions() }
                            .font(.caption.weight(.semibold))
                    }
                }
            }
        }
        .navigationTitle("Delete queue")
        .safeAreaInset(edge: .bottom) {
            if model.manualBatchCount > 0 {
                VStack(spacing: 8) {
                    Button {
                        Task { await model.deleteManualBatchNow() }
                    } label: {
                        if model.isDeletingManualBatch {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Delete Now · \(model.manualBatchCount) items")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isDeletingManualBatch || !model.hasFullPhotoAccess)

                    Text("Photos will ask once to confirm the entire batch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.bar)
            }
        }
        .toolbar {
            if !model.pendingDeletes.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Undo all") { model.undoAllDeletions() }
                }
            }
        }
    }

    private func countdown(for item: PendingDeletion) -> String {
        if item.isManualBatchItem { return "Ready — waiting for Delete Now" }
        let seconds = max(0, Int(item.dueAt.timeIntervalSince(model.now)))
        if seconds == 0 { return "Deletion overdue — retrying when possible" }
        return "Deletes in \(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}
