import Foundation
import Photos

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
        guard limit > 0, startIndex >= 0, startIndex < result.count else { return [] }
        let endIndex = min(startIndex + limit, result.count)
        var chunk: [PHAsset] = []
        chunk.reserveCapacity(endIndex - startIndex)
        for index in startIndex..<endIndex {
            chunk.append(result.object(at: index))
        }
        return chunk
    }

    func asset(withLocalIdentifier identifier: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
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
