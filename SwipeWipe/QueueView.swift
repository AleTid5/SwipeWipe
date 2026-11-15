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
    @State private var selectedDayGroup: QueueDayGroup?
    private var palette: CyberpunkPalette { CyberpunkPalette(colorScheme: colorScheme) }

    private let collageColumns = [
        GridItem(.flexible(), spacing: 5),
        GridItem(.flexible(), spacing: 5)
    ]

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
                        Button {
                            selectedDayGroup = group
                        } label: {
                            dayCollage(for: group)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(palette.background)
                        .accessibilityLabel("Open \(group.items.count) queued items for \(dayTitle(for: group.date))")
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
                            .foregroundStyle(palette.muted)
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
        .sheet(item: $selectedDayGroup) { group in
            QueueDayDetailSheet(group: group)
                .environmentObject(model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

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
            return QueueDayGrouping.dayKey(for: creationDate)
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

    private func dayCollage(for group: QueueDayGroup) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            LazyVGrid(columns: collageColumns, spacing: 5) {
                ForEach(Array(group.items.prefix(QueueCollageLayout.maximumVisibleTiles).enumerated()), id: \.element.id) { index, item in
                    collageTile(
                        for: item,
                        overflow: index == QueueCollageLayout.maximumVisibleTiles - 1
                            ? QueueCollageLayout.overflowCount(for: group.items.count)
                            : 0
                    )
                }
            }

            HStack {
                Text("OPEN DAY COLLAGE")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(palette.cyan)
                Spacer()
                Text("REVIEW \(group.items.count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.muted)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.magenta)
            }
        }
        .padding(9)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(LinearGradient(colors: [palette.cyan.opacity(0.55), palette.magenta.opacity(0.28)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        )
        .padding(.vertical, 3)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func collageTile(for item: QueueRowItem, overflow: Int) -> some View {
        ZStack {
            if let asset = item.asset {
                PhotoThumbnail(asset: asset, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 112)
                    .clipped()
                if asset.mediaType == .video {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(7)
                        .background(.black.opacity(0.65), in: Circle())
                }
            } else {
                Rectangle()
                    .fill(palette.raisedSurface)
                    .frame(height: 112)
                    .overlay(Image(systemName: "photo").foregroundStyle(palette.muted))
            }

            if overflow > 0 {
                Rectangle()
                    .fill(.black.opacity(0.68))
                VStack(spacing: 2) {
                    Text("+\(overflow)")
                        .font(.system(size: 25, weight: .black, design: .monospaced))
                        .foregroundStyle(.white)
                    Text("PICTURES")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(palette.cyan)
                }
            }
        }
        .frame(height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(palette.outline.opacity(0.55), lineWidth: 1))
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
}

private struct QueueDayDetailSheet: View {
    let group: QueueDayGroup

    @EnvironmentObject private var model: SwipeWipeModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    private var palette: CyberpunkPalette { CyberpunkPalette(colorScheme: colorScheme) }
    private var activeItems: [QueueRowItem] {
        let pendingIDs = Set(model.pendingDeletes.map(\.assetID))
        return group.items.filter { pendingIDs.contains($0.pending.assetID) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 9) {
                    ForEach(activeItems) { item in
                        if let asset = model.asset(with: item.pending.assetID) {
                            detailRow(item: item, asset: asset)
                        }
                    }
                    if activeItems.isEmpty {
                        ContentUnavailableView(
                            "DAY CLEARED",
                            systemImage: "checkmark.circle",
                            description: Text("All items in this day group have been restored or removed.")
                        )
                        .foregroundStyle(palette.muted)
                    }
                }
                .padding(14)
            }
            .background(palette.backdrop)
            .navigationTitle(group.date?.formatted(date: .complete, time: .omitted) ?? "Date unknown")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(palette.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(palette.cyan)
    }

    private func detailRow(item: QueueRowItem, asset: PHAsset) -> some View {
        HStack(spacing: 11) {
            PhotoThumbnail(asset: asset, contentMode: .fill)
                .frame(width: 92, height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.outline, lineWidth: 1))

            VStack(alignment: .leading, spacing: 5) {
                Text((asset.mediaType == .video ? "VIDEO · " : asset.mediaType == .audio ? "AUDIO · " : "PHOTO · ") + (asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "DATE UNKNOWN"))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(palette.text)
                Text(countdown(for: item.pending))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(!item.pending.isManualBatchItem && item.pending.dueAt <= model.now ? palette.red : palette.muted)

                HStack(spacing: 12) {
                    Button("UNDO") {
                        model.undoDeletion(for: item.pending.assetID)
                    }
                    .font(.system(size: 10, weight: .black, design: .monospaced))

                    if !item.pending.isManualBatchItem && item.pending.dueAt <= model.now {
                        Button("RETRY") {
                            Task { await model.retryExpiredDeletes() }
                        }
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.outline.opacity(0.7), lineWidth: 1))
    }

    private func countdown(for item: PendingDeletion) -> String {
        if item.isManualBatchItem { return "READY — WAITING FOR DELETE NOW" }
        let seconds = max(0, Int(item.dueAt.timeIntervalSince(model.now)))
        if seconds == 0 { return "DELETION OVERDUE" }
        return "DELETES IN \(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}
