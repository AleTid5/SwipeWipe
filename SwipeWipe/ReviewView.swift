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
                    undoControl

                    VStack(alignment: .trailing, spacing: 3) {
                        Text("\(model.assetCount)")
                            .font(.system(.title3, design: .monospaced).weight(.bold))
                            .foregroundStyle(palette.cyan)
                        Text("MEDIA ITEMS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundStyle(palette.muted)
                    }
                }
                .padding(.horizontal, 16)

                ZStack {
                    // Future items sit behind the active card. Their edges and
                    // thumbnails peek out to communicate the review order.
                    ForEach(Array(model.previewAssets.enumerated().reversed()), id: \.element.localIdentifier) { entry in
                        FutureDeckCard(asset: entry.element, number: entry.offset + 1, palette: palette)
                            .padding(.horizontal, CGFloat(entry.offset + 1) * 9)
                            .offset(y: CGFloat(entry.offset + 1) * 10)
                            .scaleEffect(1 - CGFloat(entry.offset + 1) * 0.018, anchor: .top)
                            .zIndex(Double(3 - entry.offset))
                    }

                    PhotoSwipeCard(
                        asset: asset,
                        onKeep: { Task { await model.keep(asset) } },
                        onDelete: { Task { await model.queueForDeletion(asset) } }
                    )
                    .id(asset.localIdentifier)
                    .padding(.horizontal, 14)
                    .zIndex(10)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .padding(.bottom, 8)

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

    private var undoControl: some View {
        Button {
            Task { await model.undoLastReviewAction() }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(model.canUndoReviewAction ? palette.yellow : palette.muted.opacity(0.35))
                Text(model.canUndoReviewAction ? "UNDO \(model.undoReviewActionCount)" : "UNDO")
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .tracking(0.7)
                    .foregroundStyle(model.canUndoReviewAction ? palette.yellow : palette.muted.opacity(0.45))
            }
            .frame(width: 58, height: 46)
            .background(palette.raisedSurface.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(palette.yellow.opacity(model.canUndoReviewAction ? 0.7 : 0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!model.canUndoReviewAction)
        .accessibilityLabel(model.nextUndoDescription)
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
            if model.canUndoReviewAction {
                undoControl
                    .padding(.bottom, 8)
            }
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

private struct FutureDeckCard: View {
    let asset: PHAsset
    let number: Int
    let palette: CyberpunkPalette

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            PhotoThumbnail(asset: asset, contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.raisedSurface)

            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .center,
                endPoint: .bottom
            )

            HStack(spacing: 6) {
                Text("UP NEXT 0\(number)")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(palette.yellow)
                Text(asset.mediaType == .video ? "VIDEO" : "PHOTO")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(palette.cyan.opacity(0.7), lineWidth: 1.2)
        )
        .shadow(color: palette.magenta.opacity(0.13), radius: 12, y: 7)
        .allowsHitTesting(false)
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
