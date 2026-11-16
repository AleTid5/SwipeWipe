import AVKit
import Photos
import SwiftUI

struct ReviewView: View {
    @EnvironmentObject private var model: SwipeWipeModel
    @Environment(\.colorScheme) private var colorScheme
    private var palette: CyberpunkPalette { CyberpunkPalette(colorScheme: colorScheme) }

    var body: some View {
        VStack(spacing: 12) {
            if !model.hasPhotoAccess {
                accessMessage
            } else if let asset = model.currentAsset {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MEDIA CLEANUP // LIVE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(palette.cyan)
                        Text("Your camera roll")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(palette.text)
                        Text("\(model.remainingCount) left in this round")
                            .font(.caption)
                            .foregroundStyle(palette.muted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(model.assetCount)")
                            .font(.system(.title3, design: .monospaced).weight(.bold))
                            .foregroundStyle(palette.yellow)
                        Text("MEDIA ITEMS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundStyle(palette.muted)
                    }
                }
                .padding(.horizontal, 16)

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

                HStack(spacing: 12) {
                    actionButton(
                        title: "DELETE",
                        subtitle: "SWIPE LEFT",
                        symbol: "trash",
                        color: palette.red
                    ) {
                        Task { await model.queueForDeletion(asset) }
                    }
                    actionButton(
                        title: "KEEP",
                        subtitle: "SWIPE RIGHT",
                        symbol: "heart.fill",
                        color: palette.green
                    ) {
                        Task { await model.keep(asset) }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            } else {
                emptyState
            }

            if let message = model.statusMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(palette.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(palette.backdrop.ignoresSafeArea())
    }

    /// Three upcoming media items displayed as a vertical deck, not a carousel.
    private var upcomingPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(palette.magenta)
                Text("UP NEXT // DECK")
                    .foregroundStyle(palette.cyan)
                Spacer()
                Text("\(model.previewAssets.count) QUEUED")
                    .foregroundStyle(palette.muted)
            }
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .tracking(1.1)

            VStack(spacing: 5) {
                ForEach(Array(model.previewAssets.enumerated()), id: \.element.localIdentifier) { index, asset in
                    HStack(spacing: 10) {
                        ZStack(alignment: .topLeading) {
                            PhotoThumbnail(asset: asset, contentMode: .fill)
                                .frame(width: 92, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            Text(String(format: "%02d", index + 1))
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .foregroundStyle(Color.black)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 3)
                                .background(palette.yellow, in: RoundedRectangle(cornerRadius: 4))
                                .padding(3)
                            if asset.mediaType == .video {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(4)
                                    .background(.black.opacity(0.72), in: Circle())
                                    .frame(width: 92, height: 56, alignment: .center)
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(asset.mediaType == .video ? "VIDEO FILE" : asset.mediaType == .audio ? "AUDIO FILE" : "PHOTO FILE")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(0.8)
                                .foregroundStyle(asset.mediaType == .video ? palette.magenta : palette.cyan)
                            Text(asset.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "DATE UNKNOWN")
                                .font(.caption2)
                                .foregroundStyle(palette.muted)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(palette.muted.opacity(0.8))
                    }
                    .padding(6)
                    .background(palette.raisedSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(palette.outline.opacity(1 - Double(index) * 0.18), lineWidth: 1)
                    )
                    .padding(.leading, CGFloat(index) * 3)
                    .padding(.trailing, CGFloat(2 - index) * 3)
                }
            }
        }
        .padding(9)
        .background(palette.surface.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(LinearGradient(colors: [palette.cyan.opacity(0.55), palette.magenta.opacity(0.30)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
        )
        .padding(.horizontal, 14)
    }

    private var accessMessage: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44))
                .foregroundStyle(palette.cyan)
            Text("Access your photos")
                .font(.title2.bold())
            Text("SwipeWipe needs read/write Photos access to show your pictures and remove the ones you choose. With Limited Access, only selected photos are available.")
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.muted)
            Button("Allow photo access") {
                Task { await model.loadPhotos() }
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.cyan)
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
                .foregroundStyle(palette.green)
            Text("You're all caught up")
                .font(.title2.bold())
            Text(model.showKeptAgain
                 ? "You've reviewed every item in this round. Start another round to see them again."
                 : "No more unseen items match your date filter. Kept items stay out of the queue unless you enable them in Settings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.muted)
            if model.showKeptAgain {
                Button("Start another round") {
                    model.startNewRound()
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.cyan)
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
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.title3.weight(.black))
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(palette.text)
                    Text(subtitle)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(color.opacity(palette.isDark ? 0.12 : 0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(color.opacity(0.75), lineWidth: 1.2))
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
    @Environment(\.colorScheme) private var colorScheme
    private var palette: CyberpunkPalette { CyberpunkPalette(colorScheme: colorScheme) }

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
                        stamp("DELETE", color: palette.red)
                        Spacer()
                    } else if offset.width > 35 {
                        Spacer()
                        stamp("KEEP", color: palette.green)
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
            .background(palette.raisedSurface)
        }
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(LinearGradient(colors: [palette.cyan.opacity(0.75), palette.magenta.opacity(0.42)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.4)
        )
        .shadow(color: palette.cyan.opacity(palette.isDark ? 0.12 : 0.08), radius: 14, y: 7)
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
