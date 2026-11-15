import Combine
import CryptoKit
import Foundation
import Photos

struct PendingDeletion: Codable, Identifiable {
    let assetID: String
    let dueAt: Date
    // Optional keeps queues saved by earlier app versions decodable.
    var requiresManualConfirmation: Bool? = false
    var id: String { assetID }
    var isManualBatchItem: Bool { requiresManualConfirmation == true }
}

struct DuplicateGroup: Identifiable {
    let fingerprint: String
    let assetIDs: [String]
    var id: String { fingerprint }
}

enum ReviewOrder: String, CaseIterable, Identifiable {
    case oldestFirst
    case newestFirst

    var id: String { rawValue }
    var title: String {
        switch self {
        case .oldestFirst: return "Oldest to newest"
        case .newestFirst: return "Newest to oldest"
        }
    }
    var isOldestFirst: Bool { self == .oldestFirst }
}

/// Accumulates PhotoKit resource chunks from its callback queue.
private final class DataAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var hasher = SHA256()

    func append(_ data: Data) {
        lock.lock()
        hasher.update(data: data)
        lock.unlock()
    }

    func finalHexDigest() -> String {
        lock.lock()
        let digest = hasher.finalize()
        lock.unlock()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class SwipeWipeModel: ObservableObject {
    /// Only the current rolling window is kept as PHAsset objects (maximum 30).
    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var assetCount = 0
    @Published private(set) var reviewCursor = 0
    @Published private(set) var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @Published private(set) var hasCheckedAuthorization = false
    @Published private(set) var isDeletingManualBatch = false
    @Published private(set) var now = Date()
    @Published private(set) var statusMessage: String?

    @Published var pendingDeletes: [PendingDeletion] {
        didSet { persistPendingDeletes() }
    }
    @Published var keptIDs: Set<String> {
        didSet { UserDefaults.standard.set(Array(keptIDs), forKey: Keys.keptIDs) }
    }
    @Published var graceMinutes: Int {
        didSet { UserDefaults.standard.set(graceMinutes, forKey: Keys.graceMinutes) }
    }
    @Published var showKeptAgain: Bool {
        didSet {
            UserDefaults.standard.set(showKeptAgain, forKey: Keys.showKeptAgain)
            visitedThisRound.removeAll()
            persistVisitedIDs()
            scheduleReviewReload()
        }
    }
    @Published var startDate: Date {
        didSet {
            UserDefaults.standard.set(startDate, forKey: Keys.startDate)
            visitedThisRound.removeAll()
            persistVisitedIDs()
            scheduleReviewReload()
        }
    }
    @Published var reviewOrder: ReviewOrder {
        didSet {
            UserDefaults.standard.set(reviewOrder.rawValue, forKey: Keys.reviewOrder)
            scheduleReviewReload()
        }
    }

    @Published private(set) var duplicateGroups: [DuplicateGroup] = []
    @Published var duplicateSelection: Set<String> = []
    @Published private(set) var isScanningDuplicates = false
    @Published private(set) var duplicateScanProgress = 0.0
    @Published private(set) var duplicateScanSkippedCount = 0
    @Published private(set) var duplicateScanScanned = 0
    @Published private(set) var duplicateScanTotal = 0
    private var isDuplicateScanCancelled = false

    private enum Keys {
        static let pendingDeletes = "swipewipe.pendingDeletes.v1"
        static let keptIDs = "swipewipe.keptIDs.v1"
        static let graceMinutes = "swipewipe.graceMinutes.v1"
        static let showKeptAgain = "swipewipe.showKeptAgain.v1"
        static let startDate = "swipewipe.startDate.v1"
        static let visitedIDs = "swipewipe.visitedIDs.v1"
        static let reviewOrder = "swipewipe.reviewOrder.v1"
    }

    private let photoLibrary = PhotoLibraryService()
    private let chunkSize = 30
    private var fetchResult: PHFetchResult<PHAsset>?
    private var nextFetchIndex = 0
    private var visitedThisRound: Set<String> = []
    private var ticker: Timer?
    private var isProcessingExpirations = false
    private var lastExpirationAttemptAt: Date?

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Keys.pendingDeletes),
           let decoded = try? JSONDecoder().decode([PendingDeletion].self, from: data) {
            pendingDeletes = decoded
        } else {
            pendingDeletes = []
        }
        keptIDs = Set(defaults.stringArray(forKey: Keys.keptIDs) ?? [])
        graceMinutes = min(max(defaults.object(forKey: Keys.graceMinutes) as? Int ?? 5, 0), 30)
        showKeptAgain = defaults.bool(forKey: Keys.showKeptAgain)
        startDate = defaults.object(forKey: Keys.startDate) as? Date ?? Date(timeIntervalSince1970: 0)
        reviewOrder = ReviewOrder(rawValue: defaults.string(forKey: Keys.reviewOrder) ?? "oldestFirst") ?? .oldestFirst
        visitedThisRound = Set(defaults.stringArray(forKey: Keys.visitedIDs) ?? [])

        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.now = Date()
                await self.processExpiredDeletes()
            }
        }
    }

    deinit {
        ticker?.invalidate()
    }

    // This app intentionally requires the entire library, not iOS Limited Access.
    var hasFullPhotoAccess: Bool { authorizationStatus == .authorized }
    var hasPhotoAccess: Bool { hasFullPhotoAccess }

    var manualBatchCount: Int {
        pendingDeletes.filter(\.isManualBatchItem).count
    }

    var currentAsset: PHAsset? {
        eligibleAssetsInWindow().first
    }

    /// The three assets immediately after the current item, used by the review deck preview.
    var previewAssets: [PHAsset] {
        Array(eligibleAssetsInWindow().dropFirst().prefix(3))
    }

    var remainingCount: Int {
        let excluded = excludedReviewIDs
        return max(0, assetCount - excluded.count)
    }

    var reviewableCount: Int {
        let excluded = Set(pendingDeletes.map(\.assetID)).union(showKeptAgain ? [] : keptIDs)
        return max(0, assetCount - excluded.count)
    }

    private var excludedReviewIDs: Set<String> {
        var excluded = visitedThisRound.union(pendingDeletes.map(\.assetID))
        if !showKeptAgain { excluded.formUnion(keptIDs) }
        return excluded
    }

    private func isEligible(_ asset: PHAsset) -> Bool {
        let identifier = asset.localIdentifier
        if visitedThisRound.contains(identifier) { return false }
        if pendingDeletes.contains(where: { $0.assetID == identifier }) { return false }
        return showKeptAgain || !keptIDs.contains(identifier)
    }

    private func eligibleAssetsInWindow() -> [PHAsset] {
        guard reviewCursor < assets.count else { return [] }
        return assets.dropFirst(reviewCursor).filter(isEligible)
    }

    func asset(with identifier: String) -> PHAsset? {
        assets.first { $0.localIdentifier == identifier } ?? photoLibrary.asset(withLocalIdentifier: identifier)
    }

    func loadPhotos() async {
        authorizationStatus = await photoLibrary.requestReadWriteAccess()
        hasCheckedAuthorization = true
        guard hasFullPhotoAccess else {
            assets = []
            assetCount = 0
            return
        }
        await reloadReviewLibrary(resetVisited: false)
        await processExpiredDeletes()
    }

    func refreshAndProcess() async {
        authorizationStatus = photoLibrary.currentAuthorizationStatus()
        hasCheckedAuthorization = true
        guard hasFullPhotoAccess else {
            assets = []
            assetCount = 0
            return
        }
        await reloadReviewLibrary(resetVisited: false)
        await processExpiredDeletes()
    }

    private func scheduleReviewReload() {
        guard hasFullPhotoAccess else { return }
        Task { await reloadReviewLibrary(resetVisited: false) }
    }

    /// Rebuilds the PhotoKit query and loads only the first 30-item window.
    private func reloadReviewLibrary(resetVisited: Bool) async {
        guard hasFullPhotoAccess else {
            assets = []
            assetCount = 0
            fetchResult = nil
            return
        }
        if resetVisited {
            visitedThisRound.removeAll()
            persistVisitedIDs()
        }

        fetchResult = photoLibrary.makeFetchResult(
            startDate: startDate,
            oldestFirst: reviewOrder.isOldestFirst
        )
        assetCount = fetchResult?.count ?? 0
        nextFetchIndex = 0
        reviewCursor = 0
        assets = []
        await extendWindowForPreview()
    }

    /// Keeps no more than 30 PHAsset objects in memory while ensuring the current
    /// item plus the next three eligible items can be previewed when available.
    private func extendWindowForPreview() async {
        guard let fetchResult else { return }

        if assets.isEmpty, nextFetchIndex < fetchResult.count {
            let firstChunk = photoLibrary.fetchChunk(
                from: fetchResult,
                startIndex: nextFetchIndex,
                limit: chunkSize
            )
            nextFetchIndex += firstChunk.count
            assets = firstChunk
            reviewCursor = 0
        }

        normalizeReviewCursor()
        while eligibleAssetsInWindow().count < 4 && nextFetchIndex < fetchResult.count {
            let remainingWindow = Array(assets.dropFirst(min(reviewCursor, assets.count)))
            let capacity = max(0, chunkSize - remainingWindow.count)
            guard capacity > 0 else { break }

            let nextChunk = photoLibrary.fetchChunk(
                from: fetchResult,
                startIndex: nextFetchIndex,
                limit: capacity
            )
            guard !nextChunk.isEmpty else { break }
            nextFetchIndex += nextChunk.count
            assets = remainingWindow + nextChunk
            reviewCursor = 0
            normalizeReviewCursor()
            await Task.yield()
        }

        normalizeReviewCursor()
        if currentAsset == nil && nextFetchIndex >= fetchResult.count {
            assets = []
            reviewCursor = 0
        }
    }

    private func normalizeReviewCursor() {
        while reviewCursor < assets.count && !isEligible(assets[reviewCursor]) {
            reviewCursor += 1
        }
    }

    private func advancePast(_ asset: PHAsset) {
        guard let index = assets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) else { return }
        reviewCursor = max(reviewCursor, index + 1)
    }

    func keep(_ asset: PHAsset) async {
        keptIDs.insert(asset.localIdentifier)
        visitedThisRound.insert(asset.localIdentifier)
        persistVisitedIDs()
        advancePast(asset)
        await extendWindowForPreview()
        statusMessage = "Kept. This item won't appear again unless you enable a new round."
    }

    func queueForDeletion(_ asset: PHAsset) async {
        visitedThisRound.insert(asset.localIdentifier)
        persistVisitedIDs()
        advancePast(asset)
        await queueForDeletion(assetIDs: [asset.localIdentifier])
        await extendWindowForPreview()
    }

    func queueForDeletion(assetIDs: [String]) async {
        let alreadyQueued = Set(pendingDeletes.map(\.assetID))
        let freshIDs = assetIDs.filter { !alreadyQueued.contains($0) }
        guard !freshIDs.isEmpty else { return }

        if graceMinutes == 0 {
            // Direct removal is collected into a manual batch so one Photos confirmation
            // can cover all media the user marked before tapping Delete Now.
            let dueAt = Date()
            pendingDeletes.append(contentsOf: freshIDs.map {
                PendingDeletion(assetID: $0, dueAt: dueAt, requiresManualConfirmation: true)
            })
            freshIDs.forEach { visitedThisRound.insert($0) }
            persistVisitedIDs()
            statusMessage = freshIDs.count == 1
                ? "Ready to delete. Tap Delete Now to remove it with one confirmation."
                : "Added \(freshIDs.count) items to the ready-to-delete batch. Tap Delete Now to remove them together."
        } else {
            let dueAt = Date().addingTimeInterval(TimeInterval(graceMinutes * 60))
            pendingDeletes.append(contentsOf: freshIDs.map { PendingDeletion(assetID: $0, dueAt: dueAt) })
            freshIDs.forEach { visitedThisRound.insert($0) }
            persistVisitedIDs()
            statusMessage = freshIDs.count == 1
                ? "Added to the deletion queue. You can undo it before the timer ends."
                : "Added \(freshIDs.count) items to the deletion queue. You can undo them before the timer ends."
        }
        await extendWindowForPreview()
    }

    func undoDeletion(for identifier: String) {
        pendingDeletes.removeAll { $0.assetID == identifier }
        visitedThisRound.remove(identifier)
        persistVisitedIDs()
        statusMessage = "Deletion cancelled. The item is back in your review queue."
        scheduleReviewReload()
    }

    func undoAllDeletions() {
        let identifiers = pendingDeletes.map(\.assetID)
        pendingDeletes.removeAll()
        identifiers.forEach { visitedThisRound.remove($0) }
        persistVisitedIDs()
        statusMessage = "All queued deletions were cancelled."
        scheduleReviewReload()
    }

    func startNewRound() {
        visitedThisRound.removeAll()
        persistVisitedIDs()
        statusMessage = "A new review round has started."
        scheduleReviewReload()
    }

    func processExpiredDeletes() async {
        guard !isProcessingExpirations && !isDeletingManualBatch else { return }
        let currentTime = Date()
        if let lastExpirationAttemptAt,
           currentTime.timeIntervalSince(lastExpirationAttemptAt) < 30 {
            return
        }
        let expired = pendingDeletes.filter { !$0.isManualBatchItem && $0.dueAt <= currentTime }
        guard !expired.isEmpty else { return }

        let earliestDueAt = expired.map(\.dueAt).min() ?? currentTime
        guard currentTime.timeIntervalSince(earliestDueAt) >= 15 else { return }

        isProcessingExpirations = true
        defer { isProcessingExpirations = false }
        let identifiers = expired.map(\.assetID)
        let result = await photoLibrary.deleteAssets(withLocalIdentifiers: identifiers)
        if result.success {
            lastExpirationAttemptAt = nil
            removeDeletedState(for: identifiers)
            await reloadReviewLibrary(resetVisited: false)
            statusMessage = identifiers.count == 1 ? "A queued item was removed." : "\(identifiers.count) queued items were removed."
        } else {
            lastExpirationAttemptAt = Date()
            statusMessage = result.message ?? "A queued deletion couldn't complete. It will be retried while the app is open."
        }
    }

    func retryExpiredDeletes() async {
        lastExpirationAttemptAt = nil
        await processExpiredDeletes()
    }

    /// Removes every item in the immediate-removal batch with a single PhotoKit request.
    func deleteManualBatchNow() async {
        guard hasFullPhotoAccess, !isDeletingManualBatch, !isProcessingExpirations else { return }
        let identifiers = pendingDeletes.filter(\.isManualBatchItem).map(\.assetID)
        guard !identifiers.isEmpty else { return }

        isDeletingManualBatch = true
        isProcessingExpirations = true
        defer {
            isDeletingManualBatch = false
            isProcessingExpirations = false
        }
        let result = await photoLibrary.deleteAssets(withLocalIdentifiers: identifiers)
        if result.success {
            removeDeletedState(for: identifiers)
            await reloadReviewLibrary(resetVisited: false)
            statusMessage = identifiers.count == 1
                ? "Item removed from your library."
                : "\(identifiers.count) items removed from your library."
        } else {
            statusMessage = result.message ?? "Couldn't remove the selected items. Your batch is still available to retry."
        }
    }

    func setDuplicateSelected(_ identifier: String, selected: Bool) {
        if selected {
            duplicateSelection.insert(identifier)
        } else {
            duplicateSelection.remove(identifier)
        }
    }

    func scanExactDuplicates() async {
        guard !isScanningDuplicates else { return }
        isScanningDuplicates = true
        isDuplicateScanCancelled = false
        duplicateScanProgress = 0
        duplicateScanSkippedCount = 0
        duplicateScanScanned = 0
        duplicateScanTotal = 0
        duplicateGroups = []
        duplicateSelection = []
        defer { isScanningDuplicates = false }

        let scanResult = photoLibrary.makeFetchResult(
            startDate: startDate,
            oldestFirst: reviewOrder.isOldestFirst
        )
        let queuedIDs = Set(pendingDeletes.map(\.assetID))
        let total = scanResult.count
        duplicateScanTotal = total
        var buckets: [String: [String]] = [:]
        var scanned = 0

        // Scan in 30-asset batches. This avoids retaining the entire library in memory.
        while scanned < total {
            if isDuplicateScanCancelled {
                duplicateGroups = []
                duplicateSelection = []
                statusMessage = "Scan cancelled."
                return
            }
            let chunk = photoLibrary.fetchChunk(from: scanResult, startIndex: scanned, limit: chunkSize)
            guard !chunk.isEmpty else { break }
            scanned += chunk.count

            for asset in chunk where !queuedIDs.contains(asset.localIdentifier) {
                if let hash = await exactResourceHash(for: asset) {
                    buckets[hash, default: []].append(asset.localIdentifier)
                } else {
                    duplicateScanSkippedCount += 1
                }
            }
            duplicateScanScanned = scanned
            duplicateScanProgress = Double(scanned) / Double(max(total, 1))
            await Task.yield()
        }

        let groups = buckets
            .filter { $0.value.count > 1 }
            .map { DuplicateGroup(fingerprint: $0.key, assetIDs: $0.value) }
            .sorted { $0.assetIDs.count > $1.assetIDs.count }
        duplicateGroups = groups
        duplicateSelection = Set(groups.flatMap { Array($0.assetIDs.dropFirst()) })
        statusMessage = groups.isEmpty
            ? "No exact duplicate media files were found in the selected date range."
            : "Found \(groups.count) groups of exact duplicate media files. Review the preselected copies before queuing removal."
    }

    /// Request cancellation of the running duplicate scan; partial results are discarded.
    func cancelDuplicateScan() {
        isDuplicateScanCancelled = true
    }

    func queueSelectedDuplicates() async {
        guard !duplicateSelection.isEmpty else { return }
        let selected = duplicateSelection
        let wouldRemoveEveryCopy = duplicateGroups.contains { group in
            group.assetIDs.allSatisfy { selected.contains($0) }
        }
        guard !wouldRemoveEveryCopy else {
            statusMessage = "Keep at least one copy in every duplicate group."
            return
        }
        await queueForDeletion(assetIDs: Array(selected))
        duplicateSelection.removeAll()
        duplicateGroups = []
    }

    private func removeDeletedState(for identifiers: [String]) {
        let removed = Set(identifiers)
        pendingDeletes.removeAll { removed.contains($0.assetID) }
        keptIDs.subtract(removed)
        visitedThisRound.subtract(removed)
        persistVisitedIDs()
    }

    private func persistVisitedIDs() {
        UserDefaults.standard.set(Array(visitedThisRound), forKey: Keys.visitedIDs)
    }

    private func persistPendingDeletes() {
        guard let data = try? JSONEncoder().encode(pendingDeletes) else { return }
        UserDefaults.standard.set(data, forKey: Keys.pendingDeletes)
    }

    private func exactResourceHash(for asset: PHAsset) async -> String? {
        let resources = PHAssetResource.assetResources(for: asset)
        let preferredTypes: [PHAssetResourceType]
        switch asset.mediaType {
        case .video: preferredTypes = [.video, .fullSizeVideo]
        case .audio: preferredTypes = [.audio]
        default: preferredTypes = [.photo, .fullSizePhoto]
        }
        guard let resource = resources.first(where: { preferredTypes.contains($0.type) }) ?? resources.first else {
            return nil
        }

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = false
        let accumulator = DataAccumulator()

        return await withCheckedContinuation { continuation in
            PHAssetResourceManager.default().requestData(
                for: resource,
                options: options,
                dataReceivedHandler: { chunk in accumulator.append(chunk) },
                completionHandler: { error in
                    guard error == nil else {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: accumulator.finalHexDigest())
                }
            )
        }
    }
}
