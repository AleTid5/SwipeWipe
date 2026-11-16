import Foundation
import Photos
import UIKit
import Vision

@MainActor
final class PhotoLibraryService {
    func requestReadWriteAccess() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard current == .notDetermined else { return current }
        return await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    func currentAuthorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    /// Returns a lightweight Photos fetch result. Individual PHAsset objects are
    /// materialized only as small windows are requested by the model.
    func makeFetchResult(startDate: Date, oldestFirst: Bool) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: oldestFirst)]
        options.predicate = NSPredicate(format: "creationDate >= %@ OR creationDate == nil", startDate as NSDate)
        // No mediaType predicate: include photos, Live Photos, videos, and other
        // media assets exposed by the user's Photos library.
        return PHAsset.fetchAssets(with: options)
    }

    func fetchChunk(
        from result: PHFetchResult<PHAsset>,
        startIndex: Int,
        limit: Int
    ) -> [PHAsset] {
        guard limit > 0,
              let range = ReviewWindowPolicy.chunkRange(startIndex: startIndex, totalCount: result.count)
        else { return [] }
        let boundedEnd = min(range.upperBound, startIndex + limit)
        let boundedRange = range.lowerBound..<boundedEnd
        var chunk: [PHAsset] = []
        chunk.reserveCapacity(boundedRange.count)
        for index in boundedRange {
            chunk.append(result.object(at: index))
        }
        return chunk
    }

    func asset(withLocalIdentifier identifier: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
    }

    /// Creates an on-device Vision feature print from a small, locally available
    /// image thumbnail. iCloud-only originals are intentionally not downloaded
    /// during a duplicate scan.
    func featurePrint(for asset: PHAsset) async -> VNFeaturePrintObservation? {
        guard asset.mediaType == .image else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false

        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 256, height: 256),
                contentMode: .aspectFit,
                options: options
            ) { image, info in
                guard
                    (info?[PHImageCancelledKey] as? Bool) != true,
                    (info?[PHImageErrorKey] as? Error) == nil,
                    let cgImage = image?.cgImage
                else {
                    continuation.resume(returning: nil)
                    return
                }

                let request = VNGenerateImageFeaturePrintRequest()
                request.imageCropAndScaleOption = .scaleFit
                do {
                    try VNImageRequestHandler(cgImage: cgImage).perform([request])
                    continuation.resume(returning: request.results?.first)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func deleteAssets(withLocalIdentifiers identifiers: [String]) async -> (success: Bool, message: String?) {
        guard !identifiers.isEmpty else { return (true, nil) }

        return await withCheckedContinuation { continuation in
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
            guard assets.count > 0 else {
                continuation.resume(returning: (true, nil))
                return
            }

            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.deleteAssets(assets)
            } completionHandler: { success, error in
                continuation.resume(returning: (success, error?.localizedDescription))
            }
        }
    }
}
