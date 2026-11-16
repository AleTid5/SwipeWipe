import Combine
import CryptoKit
import Foundation
import Photos
import Vision

struct PendingDeletion: Codable, Identifiable {
    let assetID: String
    let dueAt: Date
    // Optional keeps queues saved by earlier app versions decodable.
    var requiresManualConfirmation: Bool? = false
    var id: String { assetID }
    var isManualBatchItem: Bool { requiresManualConfirmation == true }
}

enum DuplicateGroupKind: String, Equatable {
    case exact
    case visuallySimilar
}

struct DuplicateGroup: Identifiable {
    let fingerprint: String
    let assetIDs: [String]
    var kind: DuplicateGroupKind = .exact
    var similarityDistance: Float? = nil
    var id: String { fingerprint }
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

private struct RecentVisionCandidate {
    let asset: PHAsset
    let date: Date
    var featurePrint: VNFeaturePrintObservation?
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
    @Published private(set) var undoHistory: ReviewUndoHistory { didSet { persistUndoHistory() } }

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
        static let undoHistory = "swipewipe.undoHistory.v1"
    }

    private let photoLibrary = PhotoLibraryService()
    private let chunkSize = ReviewWindowPolicy.chunkSize
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
        if let data = defaults.data(forKey: Keys.undoHistory),
           let decoded = try? JSONDecoder().decode(ReviewUndoHistory.self, from: data) {
            undoHistory = decoded
        } else {
            undoHistory = ReviewUndoHistory()
        }
        keptIDs = Set(defaults.stringArray(forKey: Keys.keptIDs) ?? [])
        graceMinutes = min(max(defaults.object(forKey: Keys.graceMinutes) as? Int ?? 5, 0), 30)
        showKeptAgain = defaults.bool(forKey: Keys.showKeptAgain)
        startDate = defaults.object(forKey: Keys.startDate) as? Date ?? Date(timeIntervalSince1970: 0)
        reviewOrder = ReviewOrder(rawValue: defaults.string(forKey: Keys.reviewOrder) ?? ReviewOrder.defaultValue.rawValue) ?? .defaultValue
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

    var canUndoReviewAction: Bool { undoHistory.canUndo }
    var undoReviewActionCount: Int { undoHistory.count }
    var nextUndoDescription: String {
        switch undoHistory.nextUndo?.kind {
        case .keep: return "Undo last keep"
        case .queueForDeletion: return "Undo last removal"
        case .none: return "Nothing to undo"
        }
    }

    var currentAsset: PHAsset? {
        eligibleAssetsInWindow().first
    }

    /// The three assets immediately after the current item, used by the review deck preview.
    var previewAssets: [PHAsset] {
        Array(
            eligibleAssetsInWindow()
                .dropFirst()
                .prefix(ReviewWindowPolicy.previewCount(for: eligibleAssetsInWindow().count))
        )
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

    private func eligibleAssetsInWindow() -> [PHAsset] {
        guard reviewCursor < assets.count else { return [] }
        let pendingIDs = Set(pendingDeletes.map(\.assetID))
        return assets.dropFirst(reviewCursor).filter { asset in
            ReviewWindowPolicy.isEligible(
                identifier: asset.localIdentifier,
                visitedIDs: visitedThisRound,
                pendingDeletionIDs: pendingIDs,
                keptIDs: keptIDs,
                showKeptAgain: showKeptAgain
            )
        }
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
        let pendingIDs = Set(pendingDeletes.map(\.assetID))
        while reviewCursor < assets.count {
            let asset = assets[reviewCursor]
            let eligible = ReviewWindowPolicy.isEligible(
                identifier: asset.localIdentifier,
                visitedIDs: visitedThisRound,
                pendingDeletionIDs: pendingIDs,
                keptIDs: keptIDs,
                showKeptAgain: showKeptAgain
            )
            if eligible { break }
            reviewCursor += 1
        }
    }

    private func advancePast(_ asset: PHAsset) {
        guard let index = assets.firstIndex(where: { $0.localIdentifier == asset.localIdentifier }) else { return }
        reviewCursor = max(reviewCursor, index + 1)
    }

    func keep(_ asset: PHAsset) async {
        let identifier = asset.localIdentifier
        recordUndoAction(kind: .keep, assetIDs: [identifier])

        keptIDs.insert(identifier)
        visitedThisRound.insert(identifier)
        persistVisitedIDs()
        advancePast(asset)
        await extendWindowForPreview()
        statusMessage = "Kept. This item won't appear again unless you enable a new round."
    }

    func queueForDeletion(_ asset: PHAsset) async {
        await queueForDeletion(assetIDs: [asset.localIdentifier])
    }

    func queueForDeletion(assetIDs: [String]) async {
        let alreadyQueued = Set(pendingDeletes.map(\.assetID))
        let freshIDs = assetIDs.filter { !alreadyQueued.contains($0) }
        guard !freshIDs.isEmpty else { return }

        recordUndoAction(kind: .queueForDeletion, assetIDs: freshIDs)

        if graceMinutes == 0 {
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

    /// Undo one review gesture at a time, in reverse chronological order.
    /// The review window is rebuilt so the restored item becomes eligible again.
    func undoLastReviewAction() async {
        var state = ReviewActionState(
            keptIDs: keptIDs,
            visitedIDs: visitedThisRound,
            pendingDeletionIDs: Set(pendingDeletes.map(\.assetID))
        )
        guard let action = undoHistory.undoLast(in: &state) else { return }

        keptIDs = state.keptIDs
        visitedThisRound = state.visitedIDs
        pendingDeletes.removeAll { action.assetIDs.contains($0.assetID) && !state.pendingDeletionIDs.contains($0.assetID) }
        persistVisitedIDs()
        statusMessage = "Undid \(action.kind.undoTitle.lowercased()) for \(action.assetIDs.count) item(s)."
        await reloadReviewLibrary(resetVisited: false)
    }

    private func recordUndoAction(kind: ReviewActionKind, assetIDs: [String]) {
        let state = ReviewActionState(
            keptIDs: keptIDs,
            visitedIDs: visitedThisRound,
            pendingDeletionIDs: Set(pendingDeletes.map(\.assetID))
        )
        undoHistory.record(
            ReviewUndoAction(kind: kind, assetIDs: assetIDs, previousState: state)
        )
    }

    private func persistUndoHistory() {
        guard let data = try? JSONEncoder().encode(undoHistory) else { return }
        UserDefaults.standard.set(data, forKey: Keys.undoHistory)
    }

    func undoDeletion(for identifier: String) {
        pendingDeletes.removeAll { $0.assetID == identifier }
        undoHistory.discardActions(containing: Set([identifier]))
        visitedThisRound.remove(identifier)
        persistVisitedIDs()
        statusMessage = "Deletion cancelled. The item is back in your review queue."
        scheduleReviewReload()
    }

    func undoAllDeletions() {
        let identifiers = pendingDeletes.map(\.assetID)
        pendingDeletes.removeAll()
        undoHistory.discardActions(containing: Set(identifiers))
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

    func scanDuplicates() async {
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

        // Similarity matching needs chronological neighbors irrespective of the
        // user's review direction.
        let scanResult = photoLibrary.makeFetchResult(
            startDate: startDate,
            oldestFirst: true
        )
        let queuedIDs = Set(pendingDeletes.map(\.assetID))
        let total = scanResult.count
        duplicateScanTotal = max(total * 2, 1)
        var buckets: [String: [String]] = [:]
        var scanned = 0

        // First pass: exact hashes for all media (photo, video, audio).
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
            duplicateScanProgress = Double(scanned) / Double(max(total * 2, 1)) * 0.5
            await Task.yield()
        }

        let exactGroups = buckets
            .filter { $0.value.count > 1 }
            .map { DuplicateGroup(fingerprint: $0.key, assetIDs: $0.value, kind: .exact) }
            .sorted { $0.assetIDs.count > $1.assetIDs.count }
        let exactIDs = Set(exactGroups.flatMap(\.assetIDs))

        // Second pass: use Vision feature prints only for photos with another
        // photo captured within 60 seconds. This avoids feature-printing isolated
        // photos in a large library and leaves exact duplicates in their own groups.
        let similarGroups = await findVisuallySimilarGroups(
            in: scanResult,
            excluding: queuedIDs.union(exactIDs),
            baseProgress: 0.5,
            progressWeight: 0.5
        )
        guard !isDuplicateScanCancelled else {
            duplicateGroups = []
            duplicateSelection = []
            statusMessage = "Scan cancelled."
            return
        }

        duplicateGroups = (exactGroups + similarGroups)
            .sorted { lhs, rhs in
                if lhs.kind != rhs.kind { return lhs.kind == .exact }
                return lhs.assetIDs.count > rhs.assetIDs.count
            }
        duplicateSelection = Set(duplicateGroups.flatMap { Array($0.assetIDs.dropFirst()) })
        let exactCount = exactGroups.count
        let similarCount = similarGroups.count
        statusMessage = exactCount == 0 && similarCount == 0
            ? "No exact or visually similar media found in the selected date range."
            : "Found \(exactCount) exact groups and \(similarCount) visually similar groups. Review the suggested copies before queuing removal."
        duplicateScanProgress = 1
        duplicateScanScanned = duplicateScanTotal
    }

    private func findVisuallySimilarGroups(
        in result: PHFetchResult<PHAsset>,
        excluding excludedIDs: Set<String>,
        baseProgress: Double,
        progressWeight: Double
    ) async -> [DuplicateGroup] {
        let total = result.count
        var scanned = 0
        let policy = SimilarityMatchPolicy(maximumCaptureGap: 60, maximumFeatureDistance: 0.35)
        var recent: [RecentVisionCandidate] = []
        var parentByAssetID: [String: String] = [:]
        var captureDates: [String: Date] = [:]

        func findRoot(_ identifier: String) -> String {
            let parent = parentByAssetID[identifier] ?? identifier
            if parent == identifier { return identifier }
            let root = findRoot(parent)
            parentByAssetID[identifier] = root
            return root
        }

        func connect(_ first: String, _ second: String) {
            if parentByAssetID[first] == nil { parentByAssetID[first] = first }
            if parentByAssetID[second] == nil { parentByAssetID[second] = second }
            let firstRoot = findRoot(first)
            let secondRoot = findRoot(second)
            if firstRoot != secondRoot {
                parentByAssetID[secondRoot] = firstRoot
            }
        }

        while scanned < total {
            if isDuplicateScanCancelled { return [] }
            let chunk = photoLibrary.fetchChunk(from: result, startIndex: scanned, limit: chunkSize)
            guard !chunk.isEmpty else { break }
            scanned += chunk.count

            for asset in chunk where asset.mediaType == .image && !excludedIDs.contains(asset.localIdentifier) {
                guard let date = asset.creationDate else { continue }
                captureDates[asset.localIdentifier] = date

                recent.removeAll { date.timeIntervalSince($0.date) > policy.maximumCaptureGap }
                if recent.isEmpty {
                    recent.append(RecentVisionCandidate(asset: asset, date: date, featurePrint: nil))
                    continue
                }

                guard let currentPrint = await photoLibrary.featurePrint(for: asset) else {
                    duplicateScanSkippedCount += 1
                    continue
                }

                for index in recent.indices.reversed() {
                    let candidate = recent[index]
                    let timeGap = date.timeIntervalSince(candidate.date)
                    if timeGap > policy.maximumCaptureGap { break }

                    let priorPrint: VNFeaturePrintObservation
                    if let cached = candidate.featurePrint {
                        priorPrint = cached
                    } else {
                        guard let generated = await photoLibrary.featurePrint(for: candidate.asset) else {
                            duplicateScanSkippedCount += 1
                            continue
                        }
                        recent[index].featurePrint = generated
                        priorPrint = generated
                    }

                    var distance: Float = 0
                    do {
                        try currentPrint.computeDistance(&distance, to: priorPrint)
                        if policy.matches(
                            firstDate: candidate.date,
                            secondDate: date,
                            featureDistance: distance
                        ) {
                            connect(candidate.asset.localIdentifier, asset.localIdentifier)
                        }
                    } catch {
                        // A failed Vision comparison is skipped; it must never be
                        // treated as a duplicate match.
                    }
                }

                recent.append(RecentVisionCandidate(asset: asset, date: date, featurePrint: currentPrint))
                // Keep memory and pairwise work bounded in large burst captures.
                if recent.count > 30 {
                    recent.removeFirst(recent.count - 30)
                }
            }

            duplicateScanScanned = total + scanned
            duplicateScanProgress = baseProgress + progressWeight * Double(scanned) / Double(max(total, 1))
            await Task.yield()
        }

        guard !parentByAssetID.isEmpty else { return [] }

        // Connected components form groups for photos whose Vision feature prints
        // are close and whose capture times are within the configured window.
        var components: [String: [String]] = [:]
        for identifier in parentByAssetID.keys {
            components[findRoot(identifier), default: []].append(identifier)
        }

        let groups = components.values.compactMap { identifiers -> DuplicateGroup? in
            guard identifiers.count > 1 else { return nil }
            let orderedIDs = identifiers.sorted { lhs, rhs in
                let leftDate = captureDates[lhs] ?? .distantPast
                let rightDate = captureDates[rhs] ?? .distantPast
                if leftDate == rightDate { return lhs < rhs }
                return leftDate < rightDate
            }
            return DuplicateGroup(
                fingerprint: "vision-\(UUID().uuidString)",
                assetIDs: orderedIDs,
                kind: .visuallySimilar
            )
        }
        return groups.sorted { $0.assetIDs.count > $1.assetIDs.count }
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
        undoHistory.discardActions(containing: removed)
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
