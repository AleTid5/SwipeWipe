import SwiftUI

struct DuplicatesView: View {
    @EnvironmentObject private var model: SwipeWipeModel

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Find exact duplicate media files")
                        .font(.headline)
                    Text("SwipeWipe compares the original media resource bytes on your device. It doesn't upload your pictures. iCloud-only originals are skipped unless they're already downloaded.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if model.isScanningDuplicates {
                        ProgressView(value: model.duplicateScanProgress)
                        Text("Scanning \(Int(model.duplicateScanProgress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        Task { await model.scanExactDuplicates() }
                    } label: {
                        Label(model.isScanningDuplicates ? "Scanning…" : "Scan for duplicates", systemImage: "sparkles.magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isScanningDuplicates || !model.hasPhotoAccess)
                }
                .padding(.vertical, 5)
            }

            if !model.duplicateGroups.isEmpty {
                Section {
                    Text("Preselected copies are suggested for removal. Leave at least one item unchecked in each group to keep an original.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ForEach(Array(model.duplicateGroups.enumerated()), id: \.element.id) { entry in
                        let index = entry.offset
                        let group = entry.element
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Group \(index + 1) · \(group.assetIDs.count) identical media files")
                                .font(.subheadline.weight(.semibold))
                            ForEach(Array(group.assetIDs.enumerated()), id: \.element) { copyIndex, identifier in
                                if let asset = model.asset(with: identifier) {
                                    HStack(spacing: 10) {
                                        PhotoThumbnail(asset: asset)
                                            .frame(width: 64, height: 64)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(copyIndex == 0 ? "Suggested original" : "Exact copy")
                                                .font(.subheadline.weight(.medium))
                                            Text(asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "Date unavailable")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Toggle("Remove", isOn: Binding(
                                            get: { model.duplicateSelection.contains(identifier) },
                                            set: { model.setDuplicateSelected(identifier, selected: $0) }
                                        ))
                                        .labelsHidden()
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Duplicate groups")
                }
            } else if !model.isScanningDuplicates {
                Section {
                    ContentUnavailableView(
                        "No results yet",
                        systemImage: "square.on.square",
                        description: Text("Run a scan to find exact duplicate media files in your selected date range.")
                    )
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
        .navigationTitle("Duplicates")
        .safeAreaInset(edge: .bottom) {
            if !model.duplicateSelection.isEmpty {
                Button {
                    Task { await model.queueSelectedDuplicates() }
                } label: {
                    Text("Queue \(model.duplicateSelection.count) selected for removal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .padding()
                .background(.bar)
            }
        }
    }
}
