import AVKit
import Photos
import SwiftUI

struct ReviewView: View {
    @EnvironmentObject private var model: SwipeWipeModel

    var body: some View {
        VStack(spacing: 12) {
            if !model.hasPhotoAccess {
                accessMessage
            } else if let asset = model.currentAsset {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Your camera roll")
                            .font(.headline)
                        Text("\(model.remainingCount) left in this round")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(model.assetCount) items")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                if !model.previewAssets.isEmpty {
                    upcomingPreview
                }

                PhotoSwipeCard(
                    asset: asset,
                    onKeep: { Task { await model.keep(asset) } },
                    onDelete: { Task { await model.queueForDeletion(asset) } }
                )
                .id(asset.localIdentifier)
                .padding(.horizontal, 14)
                .frame(maxHeight: .infinity)

                HStack(spacing: 28) {
                    actionButton(
                        title: "Delete",
                        subtitle: "Swipe left",
                        symbol: "trash",
                        color: .red
                    ) {
                        Task { await model.queueForDeletion(asset) }
                    }
                    actionButton(
                        title: "Keep",
                        subtitle: "Swipe right",
                        symbol: "heart.fill",
                        color: .green
                    ) {
                        Task { await model.keep(asset) }
                    }
                }
                .padding(.bottom, 8)
            } else {
                emptyState
            }

            if let message = model.statusMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }
        }
        .navigationTitle("SwipeWipe")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var upcomingPreview: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("UP NEXT")
                .font(.caption2.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            HStack(spacing: 8) {
                ForEach(Array(model.previewAssets.enumerated()), id: \.element.localIdentifier) { index, asset in
                    VStack(spacing: 3) {
                        ZStack(alignment: .topTrailing) {
                            PhotoThumbnail(asset: asset, contentMode: .fill)
                                .frame(maxWidth: .infinity)
                                .frame(height: 58)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            if asset.mediaType == .video {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(5)
                                    .background(.black.opacity(0.65), in: Circle())
                                    .padding(4)
                            }
                        }
                        Text("\(index + 1)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal)
    }

    private var accessMessage: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Access your photos")
                .font(.title2.bold())
            Text("SwipeWipe needs read/write Photos access to show your pictures and remove the ones you choose. With Limited Access, only selected photos are available.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Allow photo access") {
                Task { await model.loadPhotos() }
            }
            .buttonStyle(.borderedProminent)
            if model.authorizationStatus == .denied || model.authorizationStatus == .restricted {
                Text("You can change access in Settings → Privacy & Security → Photos → SwipeWipe.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("You're all caught up")
                .font(.title2.bold())
            Text(model.showKeptAgain
                 ? "You've reviewed every item in this round. Start another round to see them again."
                 : "No more unseen items match your date filter. Kept items stay out of the queue unless you enable them in Settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if model.showKeptAgain {
                Button("Start another round") {
                    model.startNewRound()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func actionButton(
        title: String,
        subtitle: String,
        symbol: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.title2.bold())
                    .frame(width: 62, height: 62)
                    .background(color.opacity(0.13), in: Circle())
                    .foregroundStyle(color)
                Text(title).font(.headline)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(minWidth: 100)
        }
        .buttonStyle(.plain)
    }
}

private struct PhotoSwipeCard: View {
    let asset: PHAsset
    let onKeep: () -> Void
    let onDelete: () -> Void

    @State private var offset: CGSize = .zero
    @State private var showVideoPlayer = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                PhotoThumbnail(asset: asset, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)

                if asset.mediaType == .video {
                    Button {
                        showVideoPlayer = true
                    } label: {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 62))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.65))
                            .shadow(radius: 8)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Play video")
                } else if asset.mediaType == .audio {
                    Image(systemName: "waveform")
                        .font(.system(size: 58))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                HStack {
                    if offset.width < -35 {
                        stamp("DELETE", color: .red)
                        Spacer()
                    } else if offset.width > 35 {
                        Spacer()
                        stamp("KEEP", color: .green)
                    }
                }
                .padding(18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        if asset.mediaType == .video {
                            Image(systemName: "video.fill")
                                .foregroundStyle(.secondary)
                            Text("Video · \(durationText(asset.duration))")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        } else if asset.mediaType == .audio {
                            Image(systemName: "waveform")
                                .foregroundStyle(.secondary)
                            Text("Audio")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "Date unavailable")
                        .font(.headline)
                    Text("\(asset.pixelWidth) × \(asset.pixelHeight)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if asset.isFavorite {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                }
            }
            .padding(14)
            .background(.regularMaterial)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(.quaternary, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 7)
        .offset(x: offset.width, y: offset.height * 0.15)
        .rotationEffect(.degrees(Double(offset.width / 22)))
        .gesture(
            DragGesture()
                .onChanged { value in offset = value.translation }
                .onEnded { value in
                    if value.translation.width > 110 {
                        onKeep()
                    } else if value.translation.width < -110 {
                        onDelete()
                    }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        offset = .zero
                    }
                }
        )
        .sheet(isPresented: $showVideoPlayer) {
            VideoPlayerSheet(asset: asset)
        }
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func stamp(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 24, weight: .black, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 3))
            .rotationEffect(.degrees(-10))
    }
}

private struct VideoPlayerSheet: View {
    let asset: PHAsset

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if let player {
                    VideoPlayer(player: player)
                        .onAppear { player.play() }
                        .onDisappear { player.pause() }
                } else if isLoading {
                    ProgressView("Loading video…")
                } else {
                    ContentUnavailableView("Video unavailable", systemImage: "video.slash")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        player?.pause()
                        dismiss()
                    }
                }
            }
        }
        .task { loadVideo() }
    }

    private func loadVideo() {
        let options = PHVideoRequestOptions()
        options.deliveryMode = .automatic
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { videoAsset, _, _ in
            DispatchQueue.main.async {
                if let videoAsset {
                    player = AVPlayer(playerItem: AVPlayerItem(asset: videoAsset))
                }
                isLoading = false
            }
        }
    }
}
