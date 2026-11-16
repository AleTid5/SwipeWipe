import Photos
import SwiftUI
import UIKit

struct PhotoThumbnail: View {
    let asset: PHAsset
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(uiColor: .secondarySystemBackground)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else if asset.mediaType == .audio {
                    Image(systemName: "waveform")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                }
            }
        }
        .task(id: asset.localIdentifier) {
            loadImage()
        }
    }

    private func loadImage() {
        image = nil
        guard asset.mediaType != .audio else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = true
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 1400, height: 1800),
            contentMode: .aspectFit,
            options: options
        ) { result, info in
            guard (info?[PHImageCancelledKey] as? Bool) != true else { return }
            DispatchQueue.main.async {
                if let result { image = result }
            }
        }
    }
}
