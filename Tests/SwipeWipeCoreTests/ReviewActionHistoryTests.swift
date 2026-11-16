import Foundation
import XCTest
@testable import SwipeWipeCore

final class ReviewActionHistoryTests: XCTestCase {
    func testUndoUsesLastInFirstOutOrderAcrossKeepAndRemoveActions() {
        var state = ReviewActionState()
        var history = ReviewUndoHistory()

        let keepA = ReviewUndoAction(kind: .keep, assetIDs: ["A"], previousState: state)
        history.record(keepA)
        state.keptIDs.insert("A")
        state.visitedIDs.insert("A")

        let keepB = ReviewUndoAction(kind: .keep, assetIDs: ["B"], previousState: state)
        history.record(keepB)
        state.keptIDs.insert("B")
        state.visitedIDs.insert("B")

        let removeC = ReviewUndoAction(kind: .queueForDeletion, assetIDs: ["C"], previousState: state)
        history.record(removeC)
        state.pendingDeletionIDs.insert("C")
        state.visitedIDs.insert("C")

        let removeD = ReviewUndoAction(kind: .queueForDeletion, assetIDs: ["D"], previousState: state)
        history.record(removeD)
        state.pendingDeletionIDs.insert("D")
        state.visitedIDs.insert("D")

        XCTAssertEqual(history.count, 4)

        XCTAssertEqual(history.undoLast(in: &state)?.assetIDs, ["D"])
        XCTAssertEqual(state.pendingDeletionIDs, ["C"])
        XCTAssertEqual(state.keptIDs, ["A", "B"])

        XCTAssertEqual(history.undoLast(in: &state)?.assetIDs, ["C"])
        XCTAssertTrue(state.pendingDeletionIDs.isEmpty)
        XCTAssertEqual(state.visitedIDs, ["A", "B"])

        XCTAssertEqual(history.undoLast(in: &state)?.assetIDs, ["B"])
        XCTAssertEqual(state.keptIDs, ["A"])
        XCTAssertEqual(state.visitedIDs, ["A"])
        XCTAssertEqual(history.undoLast(in: &state)?.assetIDs, ["A"])
        XCTAssertTrue(state.keptIDs.isEmpty)
        XCTAssertTrue(state.visitedIDs.isEmpty)
        XCTAssertFalse(history.canUndo)
    }

    func testUndoRestoresPreviousKeptStateWhenAnAlreadyKeptItemIsQueued() {
        var state = ReviewActionState(
            keptIDs: ["photo-1"],
            visitedIDs: ["photo-1"]
        )
        var history = ReviewUndoHistory()

        history.record(
            ReviewUndoAction(
                kind: .queueForDeletion,
                assetIDs: ["photo-1"],
                previousState: state
            )
        )
        state.pendingDeletionIDs.insert("photo-1")

        XCTAssertNotNil(history.undoLast(in: &state))
        XCTAssertTrue(state.pendingDeletionIDs.isEmpty)
        XCTAssertEqual(state.keptIDs, ["photo-1"])
        XCTAssertEqual(state.visitedIDs, ["photo-1"])
    }

    func testHistoryIsCappedAtMaximumDepth() {
        var history = ReviewUndoHistory(maximumDepth: 2)
        let empty = ReviewActionState()

        history.record(ReviewUndoAction(kind: .keep, assetIDs: ["A"], previousState: empty))
        history.record(ReviewUndoAction(kind: .keep, assetIDs: ["B"], previousState: empty))
        history.record(ReviewUndoAction(kind: .keep, assetIDs: ["C"], previousState: empty))

        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.nextUndo?.assetIDs, ["C"])
    }

    func testDiscardingPhysicallyDeletedAssetsKeepsOtherUndoEntries() {
        var history = ReviewUndoHistory()
        let empty = ReviewActionState()
        history.record(ReviewUndoAction(kind: .keep, assetIDs: ["A"], previousState: empty))
        history.record(ReviewUndoAction(kind: .queueForDeletion, assetIDs: ["B", "C"], previousState: empty))

        history.discardActions(containing: ["B"])

        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history.nextUndo?.assetIDs, ["C"])
        history.discardActions(containing: ["A", "C"])
        XCTAssertEqual(history.count, 0)
    }

    func testUndoHistoryCanBePersistedAndDecoded() throws {
        var history = ReviewUndoHistory()
        history.record(
            ReviewUndoAction(
                kind: .keep,
                assetIDs: ["asset-id"],
                previousState: ReviewActionState()
            )
        )

        let encoded = try JSONEncoder().encode(history)
        let decoded = try JSONDecoder().decode(ReviewUndoHistory.self, from: encoded)
        XCTAssertEqual(decoded, history)
    }

    func testSimilarityPolicyRequiresBothVisualAndTimeSimilarity() {
        let policy = SimilarityMatchPolicy(maximumCaptureGap: 60, maximumFeatureDistance: 0.35)
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertTrue(policy.matches(
            firstDate: date,
            secondDate: date.addingTimeInterval(12),
            featureDistance: 0.12
        ))
        XCTAssertFalse(policy.matches(
            firstDate: date,
            secondDate: date.addingTimeInterval(75),
            featureDistance: 0.12
        ))
        XCTAssertFalse(policy.matches(
            firstDate: date,
            secondDate: date.addingTimeInterval(12),
            featureDistance: 0.8
        ))
        XCTAssertFalse(policy.matches(
            firstDate: date,
            secondDate: date,
            featureDistance: -0.1
        ))
    }

    func testQueueCollageShowsAtMostFourTilesAndCalculatesOverflow() {
        XCTAssertEqual(QueueCollageLayout.visibleTileCount(for: 0), 0)
        XCTAssertEqual(QueueCollageLayout.visibleTileCount(for: 3), 3)
        XCTAssertEqual(QueueCollageLayout.visibleTileCount(for: 4), 4)
        XCTAssertEqual(QueueCollageLayout.visibleTileCount(for: 7), 4)

        XCTAssertEqual(QueueCollageLayout.overflowCount(for: 4), 0)
        XCTAssertEqual(QueueCollageLayout.overflowCount(for: 5), 1)
        XCTAssertEqual(QueueCollageLayout.overflowCount(for: 9), 5)
    }

    func testOldestFirstIsTheDefaultAndNewestFirstCanBeSelected() {
        XCTAssertEqual(ReviewOrder.defaultValue, .oldestFirst)
        XCTAssertTrue(ReviewOrder.oldestFirst.isOldestFirst)
        XCTAssertFalse(ReviewOrder.newestFirst.isOldestFirst)
    }

    func testChunkWindowIsLimitedToThirtyAndHandlesFinalPartialChunk() {
        XCTAssertEqual(ReviewWindowPolicy.chunkSize, 30)
        XCTAssertEqual(ReviewWindowPolicy.chunkRange(startIndex: 0, totalCount: 14_000), 0..<30)
        XCTAssertEqual(ReviewWindowPolicy.chunkRange(startIndex: 30, totalCount: 14_000), 30..<60)
        XCTAssertEqual(ReviewWindowPolicy.chunkRange(startIndex: 60, totalCount: 65), 60..<65)
        XCTAssertNil(ReviewWindowPolicy.chunkRange(startIndex: 65, totalCount: 65))
        XCTAssertNil(ReviewWindowPolicy.chunkRange(startIndex: -1, totalCount: 65))
    }

    func testDeckPreviewsAtMostThreeItemsAfterTheCurrentItem() {
        XCTAssertEqual(ReviewWindowPolicy.previewCount(for: 0), 0)
        XCTAssertEqual(ReviewWindowPolicy.previewCount(for: 1), 0)
        XCTAssertEqual(ReviewWindowPolicy.previewCount(for: 2), 1)
        XCTAssertEqual(ReviewWindowPolicy.previewCount(for: 4), 3)
        XCTAssertEqual(ReviewWindowPolicy.previewCount(for: 20), 3)
    }

    func testKeptItemsAreSkippedUnlessShowKeptAgainIsEnabled() {
        let kept: Set<String> = ["kept"]
        let noVisited: Set<String> = []
        let noPending: Set<String> = []

        XCTAssertFalse(ReviewWindowPolicy.isEligible(
            identifier: "kept",
            visitedIDs: noVisited,
            pendingDeletionIDs: noPending,
            keptIDs: kept,
            showKeptAgain: false
        ))
        XCTAssertTrue(ReviewWindowPolicy.isEligible(
            identifier: "kept",
            visitedIDs: noVisited,
            pendingDeletionIDs: noPending,
            keptIDs: kept,
            showKeptAgain: true
        ))
    }

    func testVisitedAndPendingItemsAreAlwaysSkipped() {
        XCTAssertFalse(ReviewWindowPolicy.isEligible(
            identifier: "visited",
            visitedIDs: ["visited"],
            pendingDeletionIDs: [],
            keptIDs: [],
            showKeptAgain: true
        ))
        XCTAssertFalse(ReviewWindowPolicy.isEligible(
            identifier: "pending",
            visitedIDs: [],
            pendingDeletionIDs: ["pending"],
            keptIDs: [],
            showKeptAgain: true
        ))
    }

    func testQueueItemsUseCalendarDayAsTheirGroupingKey() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let first = ISO8601DateFormatter().date(from: "2026-11-15T02:15:00Z")!
        let second = ISO8601DateFormatter().date(from: "2026-11-15T21:40:00Z")!
        let nextDay = ISO8601DateFormatter().date(from: "2026-11-16T00:01:00Z")!

        XCTAssertEqual(
            QueueDayGrouping.dayKey(for: first, calendar: calendar),
            QueueDayGrouping.dayKey(for: second, calendar: calendar)
        )
        XCTAssertNotEqual(
            QueueDayGrouping.dayKey(for: first, calendar: calendar),
            QueueDayGrouping.dayKey(for: nextDay, calendar: calendar)
        )
    }
}
