import Foundation

public enum ReviewActionKind: String, Codable, Equatable {
    case keep
    case queueForDeletion

    public var undoTitle: String {
        switch self {
        case .keep: return "Keep"
        case .queueForDeletion: return "Remove"
        }
    }
}

/// Small, serializable snapshot of the state that an action changed.
public struct ReviewActionState: Equatable {
    public var keptIDs: Set<String>
    public var visitedIDs: Set<String>
    public var pendingDeletionIDs: Set<String>

    public init(
        keptIDs: Set<String> = [],
        visitedIDs: Set<String> = [],
        pendingDeletionIDs: Set<String> = []
    ) {
        self.keptIDs = keptIDs
        self.visitedIDs = visitedIDs
        self.pendingDeletionIDs = pendingDeletionIDs
    }
}

public struct ReviewUndoAction: Codable, Equatable, Identifiable {
    public let id: UUID
    public let kind: ReviewActionKind
    public let assetIDs: [String]
    public let previouslyKeptIDs: [String]
    public let previouslyVisitedIDs: [String]
    public let previouslyPendingIDs: [String]

    public init(
        id: UUID = UUID(),
        kind: ReviewActionKind,
        assetIDs: [String],
        previousState: ReviewActionState
    ) {
        self.id = id
        self.kind = kind
        self.assetIDs = assetIDs
        self.previouslyKeptIDs = assetIDs.filter(previousState.keptIDs.contains)
        self.previouslyVisitedIDs = assetIDs.filter(previousState.visitedIDs.contains)
        self.previouslyPendingIDs = assetIDs.filter(previousState.pendingDeletionIDs.contains)
    }

    public func applyingUndo(to state: ReviewActionState) -> ReviewActionState {
        var restored = state
        let affected = Set(assetIDs)

        restored.keptIDs.subtract(affected)
        restored.visitedIDs.subtract(affected)
        restored.pendingDeletionIDs.subtract(affected)

        restored.keptIDs.formUnion(previouslyKeptIDs)
        restored.visitedIDs.formUnion(previouslyVisitedIDs)
        restored.pendingDeletionIDs.formUnion(previouslyPendingIDs)
        return restored
    }
}

/// LIFO history for the main review gestures. The app persists this value so an
/// accidental Keep or Remove can still be rolled back after navigating/relaunching.
public struct ReviewUndoHistory: Codable, Equatable {
    public private(set) var actions: [ReviewUndoAction]
    public let maximumDepth: Int

    public init(actions: [ReviewUndoAction] = [], maximumDepth: Int = 200) {
        self.actions = Array(actions.suffix(max(1, maximumDepth)))
        self.maximumDepth = max(1, maximumDepth)
    }

    public var canUndo: Bool { !actions.isEmpty }
    public var count: Int { actions.count }
    public var nextUndo: ReviewUndoAction? { actions.last }

    public mutating func record(_ action: ReviewUndoAction) {
        actions.append(action)
        if actions.count > maximumDepth {
            actions.removeFirst(actions.count - maximumDepth)
        }
    }

    @discardableResult
    public mutating func undoLast(in state: inout ReviewActionState) -> ReviewUndoAction? {
        guard let action = actions.popLast() else { return nil }
        state = action.applyingUndo(to: state)
        return action
    }

    /// Remove history referring to assets which have been physically deleted, or
    /// which were manually undone from the Delete Queue.
    public mutating func discardActions(containing identifiers: Set<String>) {
        guard !identifiers.isEmpty else { return }
        actions = actions.compactMap { action in
            let remainingIDs = action.assetIDs.filter { !identifiers.contains($0) }
            guard !remainingIDs.isEmpty else { return nil }

            let remaining = Set(remainingIDs)
            return ReviewUndoAction(
                id: action.id,
                kind: action.kind,
                assetIDs: remainingIDs,
                previousState: ReviewActionState(
                    keptIDs: Set(action.previouslyKeptIDs).intersection(remaining),
                    visitedIDs: Set(action.previouslyVisitedIDs).intersection(remaining),
                    pendingDeletionIDs: Set(action.previouslyPendingIDs).intersection(remaining)
                )
            )
        }
    }
}

/// Vision distances are not percentages. Shorter feature-print distances mean
/// greater similarity; this policy also requires close capture times to reduce
/// false positives between unrelated pictures.
public struct SimilarityMatchPolicy: Equatable {
    public var maximumCaptureGap: TimeInterval
    public var maximumFeatureDistance: Float

    public init(maximumCaptureGap: TimeInterval = 60, maximumFeatureDistance: Float = 0.35) {
        self.maximumCaptureGap = max(0, maximumCaptureGap)
        self.maximumFeatureDistance = max(0, maximumFeatureDistance)
    }

    public func matches(
        firstDate: Date,
        secondDate: Date,
        featureDistance: Float
    ) -> Bool {
        abs(secondDate.timeIntervalSince(firstDate)) <= maximumCaptureGap
            && featureDistance >= 0
            && featureDistance <= maximumFeatureDistance
    }
}

/// Geometry contract for the Delete Queue collage.
public enum QueueCollageLayout {
    public static let maximumVisibleTiles = 4

    public static func visibleTileCount(for totalItems: Int) -> Int {
        min(max(0, totalItems), maximumVisibleTiles)
    }

    public static func overflowCount(for totalItems: Int) -> Int {
        max(0, totalItems - maximumVisibleTiles)
    }
}


public enum ReviewOrder: String, CaseIterable, Identifiable {
    case oldestFirst
    case newestFirst

    public static let defaultValue: ReviewOrder = .oldestFirst
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .oldestFirst: return "Oldest to newest"
        case .newestFirst: return "Newest to oldest"
        }
    }
    public var isOldestFirst: Bool { self == .oldestFirst }
}

/// Shared review-window rules used by PhotoKit paging and the review deck.
public enum ReviewWindowPolicy {
    public static let chunkSize = 30
    public static let previewLimit = 3

    public static func chunkRange(startIndex: Int, totalCount: Int) -> Range<Int>? {
        guard totalCount > 0, startIndex >= 0, startIndex < totalCount else { return nil }
        return startIndex..<min(startIndex + chunkSize, totalCount)
    }

    public static func previewCount(for eligibleItems: Int) -> Int {
        min(max(0, eligibleItems - 1), previewLimit)
    }

    public static func isEligible(
        identifier: String,
        visitedIDs: Set<String>,
        pendingDeletionIDs: Set<String>,
        keptIDs: Set<String>,
        showKeptAgain: Bool
    ) -> Bool {
        guard !visitedIDs.contains(identifier),
              !pendingDeletionIDs.contains(identifier) else {
            return false
        }
        return showKeptAgain || !keptIDs.contains(identifier)
    }
}

/// Normalizes capture timestamps to the calendar day used for Delete Queue sections.
public enum QueueDayGrouping {
    public static func dayKey(for date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }
}
