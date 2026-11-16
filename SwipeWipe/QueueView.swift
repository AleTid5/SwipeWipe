import SwiftUI
import Photos

private struct QueueRowItem: Identifiable {
    let pending: PendingDeletion
    let asset: PHAsset?

    var id: String { pending.assetID }
}

private struct QueueDayGroup: Identifiable {
    let date: Date?
    let items: [QueueRowItem]

    var id: String {
        date.map { String(Int($0.timeIntervalSince1970)) } ?? "unknown-date"
    }
}

struct QueueView: View {
    @EnvironmentObject private var model: SwipeWipeModel
    @Environment(\.colorScheme) private var colorScheme
    private var palette: CyberpunkPalette { CyberpunkPalette(colorScheme: colorScheme) }

    var body: some View {
        List {
            if model.pendingDeletes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.badge.checkmark")
                        .font(.system(size: 44))
                        .foregroundStyle(palette.green)
                    Text("QUEUE EMPTY // NOTHING PENDING")
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(palette.text)
                    Text("Photos and videos marked for deletion will appear here until their undo timer expires.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(palette.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 44)
                .listRowBackground(palette.background)
            } else {
                ForEach(dayGroups) { group in
                    Section {
                        ForEach(group.items) { queuedItem in
                            if let asset = queuedItem.asset {
                                HStack(spacing: 12) {
                                    PhotoThumbnail(asset: asset)
                                        .frame(width: 76, height: 76)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.outline, lineWidth: 1))

                                    VStack(alignment: .leading, spacing: 5) {
                                        Text((asset.mediaType == .video ? "Video · " : "") + (asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "Media item"))
                                            .font(.subheadline.weight(.semibold))
                                        Text(countdown(for: queuedItem.pending))
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundStyle(!queuedItem.pending.isManualBatchItem && queuedItem.pending.dueAt <= model.now ? palette.red : palette.muted)

                                        HStack(spacing: 12) {
                                            Button("Undo deletion") {
                                                model.undoDeletion(for: queuedItem.pending.assetID)
                                            }
                                            .font(.caption.weight(.semibold))

                                            if !queuedItem.pending.isManualBatchItem && queuedItem.pending.dueAt <= model.now {
                                                Button("Retry now") {
                                                    Task { await model.retryExpiredDeletes() }
                                                }
                                                .font(.caption.weight(.semibold))
                                            }
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(8)
                                .background(palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(palette.outline.opacity(0.7), lineWidth: 1))
                                .padding(.vertical, 3)
                                .listRowBackground(palette.background)
                            }
                        }
                    } header: {
                        HStack {
                            Text(dayTitle(for: group.date).uppercased())
                                .foregroundStyle(palette.cyan)
                                .tracking(0.8)
                            Spacer()
                            Text("\(group.items.count) ITEMS")
                                .foregroundStyle(palette.yellow)
                        }
                        .font(.subheadline.weight(.semibold))
                        .textCase(nil)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.backdrop)
        .tint(palette.cyan)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if model.manualBatchCount > 0 || !model.pendingDeletes.isEmpty {
                VStack(spacing: 8) {
                    if model.manualBatchCount > 0 {
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

                    if !model.pendingDeletes.isEmpty {
                        Button("Undo all · \(model.pendingDeletes.count) items") {
                            model.undoAllDeletions()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                .background(palette.surface)
                .overlay(alignment: .top) { Rectangle().fill(palette.outline).frame(height: 1) }
            }
        }
    }

    /// Resolve the queued PhotoKit assets once for grouping and row rendering.
    /// Items are grouped by their capture day, rather than the time they entered the queue.
    private var queueItems: [QueueRowItem] {
        model.pendingDeletes.map { pending in
            QueueRowItem(
                pending: pending,
                asset: model.asset(with: pending.assetID)
            )
        }
    }

    private var dayGroups: [QueueDayGroup] {
        let grouped = Dictionary(grouping: queueItems) { item -> Date? in
            guard let creationDate = item.asset?.creationDate else { return nil }
            return Calendar.current.startOfDay(for: creationDate)
        }

        let orderedDays = grouped.keys.compactMap { $0 }.sorted { lhs, rhs in
            model.reviewOrder.isOldestFirst ? lhs < rhs : lhs > rhs
        }

        var result = orderedDays.compactMap { day -> QueueDayGroup? in
            guard let items = grouped[day] else { return nil }
            return QueueDayGroup(date: day, items: sortItems(items))
        }

        if let undatedItems = grouped[nil], !undatedItems.isEmpty {
            result.append(QueueDayGroup(date: nil, items: sortItems(undatedItems)))
        }

        return result
    }

    private func sortItems(_ items: [QueueRowItem]) -> [QueueRowItem] {
        items.sorted { lhs, rhs in
            let lhsDate = lhs.asset?.creationDate ?? lhs.pending.dueAt
            let rhsDate = rhs.asset?.creationDate ?? rhs.pending.dueAt
            if lhsDate == rhsDate {
                return lhs.pending.dueAt < rhs.pending.dueAt
            }
            return model.reviewOrder.isOldestFirst ? lhsDate < rhsDate : lhsDate > rhsDate
        }
    }

    private func dayTitle(for date: Date?) -> String {
        guard let date else { return "Date unknown" }
        if Calendar.current.isDateInToday(date) {
            return "Today · \(date.formatted(date: .abbreviated, time: .omitted))"
        }
        if Calendar.current.isDateInYesterday(date) {
            return "Yesterday · \(date.formatted(date: .abbreviated, time: .omitted))"
        }
        return date.formatted(date: .complete, time: .omitted)
    }

    private func countdown(for item: PendingDeletion) -> String {
        if item.isManualBatchItem { return "Ready — waiting for Delete Now" }
        let seconds = max(0, Int(item.dueAt.timeIntervalSince(model.now)))
        if seconds == 0 { return "Deletion overdue — retrying when possible" }
        return "Deletes in \(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}
