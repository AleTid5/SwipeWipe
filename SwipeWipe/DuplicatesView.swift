import Photos
import SwiftUI

struct DuplicatesView: View {
    @EnvironmentObject private var model: SwipeWipeModel
    @Environment(\.colorScheme) private var colorScheme
    private var palette: CyberpunkPalette { CyberpunkPalette(colorScheme: colorScheme) }

    var body: some View {
        List {
            Section {
                scanCard
                    .padding(12)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(LinearGradient(colors: [palette.cyan.opacity(0.55), palette.magenta.opacity(0.30)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    )
                    .padding(.vertical, 5)
                    .listRowBackground(palette.background)
            }

            if !model.duplicateGroups.isEmpty {
                Section {
                    Text("PRESELECTED COPIES // REVIEW BEFORE QUEUE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(palette.muted)
                    ForEach(Array(model.duplicateGroups.enumerated()), id: \.element.id) { entry in
                        let index = entry.offset
                        let group = entry.element
                        duplicateGroupCard(group, groupIndex: index)
                            .padding(10)
                            .background(palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(palette.outline.opacity(0.7), lineWidth: 1)
                            )
                            .padding(.vertical, 4)
                            .listRowBackground(palette.background)
                    }
                } header: {
                    Text("DUPLICATE GROUPS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.4)
                        .textCase(nil)
                        .foregroundStyle(palette.cyan)
                }
            } else if !model.isScanningDuplicates {
                Section {
                    emptyState
                        .listRowBackground(palette.background)
                }
            }

            if model.duplicateScanSkippedCount > 0 {
                Section {
                    Label("\(model.duplicateScanSkippedCount) items couldn't be scanned. Some may be stored only in iCloud.", systemImage: "icloud.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.backdrop)
        .tint(palette.cyan)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if !model.duplicateSelection.isEmpty {
                Button {
                    Task { await model.queueSelectedDuplicates() }
                } label: {
                    Text("QUEUE \(model.duplicateSelection.count) FOR REMOVAL")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .tracking(1.1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .background(palette.surface)
                .overlay(alignment: .top) { Rectangle().fill(palette.outline).frame(height: 1) }
            }
        }
    }

    // MARK: - Scan card

    private var scanCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DUPLICATE SCAN // LOCAL")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(palette.cyan)
            Text("Find exact duplicate media files")
                .font(.headline.weight(.bold))
                .foregroundStyle(palette.text)
            Text("Compares the original media bytes on your device. Nothing is uploaded. iCloud-only originals are skipped unless already downloaded.")
                .font(.footnote)
                .foregroundStyle(palette.muted)

            if model.isScanningDuplicates {
                scanProgress
                Button {
                    model.cancelDuplicateScan()
                } label: {
                    Label("CANCEL SCAN", systemImage: "xmark")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .tracking(1)
                }
                .buttonStyle(.bordered)
                .tint(palette.red)
            } else {
                Button {
                    Task { await model.scanExactDuplicates() }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "sparkles.magnifyingglass")
                            .font(.title3.weight(.black))
                            .foregroundStyle(palette.magenta)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SCAN FOR DUPLICATES")
                                .font(.system(size: 12, weight: .black, design: .monospaced))
                                .tracking(1.1)
                                .foregroundStyle(palette.text)
                            Text("EXACT BYTE MATCH // ON-DEVICE")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(palette.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 13)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(palette.magenta.opacity(palette.isDark ? 0.12 : 0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(palette.magenta.opacity(0.75), lineWidth: 1.2))
                }
                .buttonStyle(.plain)
                .disabled(!model.hasPhotoAccess)
            }

            if let message = model.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(palette.muted)
            }
        }
    }

    private var scanProgress: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.raisedSurface)
                    Capsule()
                        .fill(LinearGradient(colors: [palette.cyan, palette.magenta], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, proxy.size.width * model.duplicateScanProgress))
                        .animation(.linear(duration: 0.2), value: model.duplicateScanProgress)
                }
            }
            .frame(height: 8)

            HStack {
                Text("SCANNING // \(Int(model.duplicateScanProgress * 100))%")
                    .foregroundStyle(palette.cyan)
                Spacer()
                Text("\(model.duplicateScanScanned) / \(max(model.duplicateScanTotal, model.duplicateScanScanned, 1))")
                    .foregroundStyle(palette.muted)
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(1)
        }
    }

    // MARK: - Duplicate group cards

    private func duplicateGroupCard(_ group: DuplicateGroup, groupIndex: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("GROUP \(String(format: "%02d", groupIndex + 1)) · \(group.assetIDs.count) IDENTICAL")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(palette.magenta)
                Spacer()
                Menu {
                    Button("Keep one") { setGroup(group, selected: false, exceptFirst: true) }
                    Button("Select copies") { setGroup(group, selected: true, exceptFirst: true) }
                    Button("Deselect all") { setGroup(group, selected: false, exceptFirst: false) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(palette.muted)
                        .frame(width: 32, height: 28)
                        .contentShape(Rectangle())
                }
            }

            ForEach(Array(group.assetIDs.enumerated()), id: \.element) { copyIndex, identifier in
                if let asset = model.asset(with: identifier) {
                    duplicateRow(asset: asset, isSuggestedOriginal: copyIndex == 0, identifier: identifier)
                }
            }
        }
    }

    private func duplicateRow(asset: PHAsset, isSuggestedOriginal: Bool, identifier: String) -> some View {
        let isSelected = model.duplicateSelection.contains(identifier)
        return Button {
            model.setDuplicateSelected(identifier, selected: !isSelected)
        } label: {
            HStack(spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    PhotoThumbnail(asset: asset)
                        .frame(width: 80, height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .opacity(isSelected ? 0.55 : 1)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white, palette.red)
                            .offset(x: 7, y: -7)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(isSuggestedOriginal ? "SUGGESTED ORIGINAL" : "EXACT COPY")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(isSuggestedOriginal ? palette.green : palette.magenta)
                    Text(asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "DATE UNKNOWN")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(palette.muted)
                    Text("\(asset.pixelWidth) × \(asset.pixelHeight)")
                        .font(.caption2)
                        .foregroundStyle(palette.muted.opacity(0.8))
                }
                Spacer(minLength: 0)
                Text(isSelected ? "REMOVE" : "KEEP")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(isSelected ? palette.red : palette.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        (isSelected ? palette.red : palette.green).opacity(palette.isDark ? 0.14 : 0.08),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
            }
            .padding(6)
            .background(palette.raisedSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? palette.red.opacity(0.75) : palette.outline.opacity(0.5), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSelected ? "Queued for removal" : "Keep this copy")
    }

    /// Apply a selection state to every item of a group.
    /// When `exceptFirst` is set, the suggested original (first item) is always left unselected.
    private func setGroup(_ group: DuplicateGroup, selected: Bool, exceptFirst: Bool) {
        for (index, identifier) in group.assetIDs.enumerated() {
            if exceptFirst && index == 0 { continue }
            model.setDuplicateSelected(identifier, selected: selected)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.on.square")
                .font(.system(size: 44))
                .foregroundStyle(palette.cyan)
            Text("NO RESULTS YET")
                .font(.system(size: 13, weight: .black, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(palette.text)
            Text("Run a scan to find exact duplicate media files in your selected date range.")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }
}
