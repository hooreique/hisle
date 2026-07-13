import Foundation

struct DeferredBoundaryAggregateMarkedUpdate {
    let replacementRange: NSRange?
    let markedLength: Int
    let clientMarkedRange: NSRange?
    let clearOwnershipIfClientRangeMissing: Bool
}

enum DeferredAggregateMarkedCompletion {
    static func apply(
        tracker: inout MarkedTextRangeTracker,
        pendingReplacement: inout PendingMarkedTextReplacement?,
        update: DeferredBoundaryAggregateMarkedUpdate
    ) {
        if let replacementRange = update.replacementRange {
            tracker.recordMarkedTextUpdate(
                replacementRange: replacementRange,
                markedLength: update.markedLength,
                clientMarkedRange: update.clientMarkedRange,
                clearOwnershipIfClientRangeMissing: update.clearOwnershipIfClientRangeMissing
            )
        }
        pendingReplacement = nil
    }
}
