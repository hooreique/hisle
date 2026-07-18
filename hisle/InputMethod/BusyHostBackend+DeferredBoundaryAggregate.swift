import Foundation
import InputMethodKit
import os

extension BusyHostBackend {
    @discardableResult
    func finishDeferredBoundaryFallbackAggregate(
        _ expectedIntent: DeferredBoundaryAggregateApplyIntent? = nil
    ) -> Bool {
        guard let intent = inFlightDeferredBoundaryAggregateApply,
              expectedIntent == nil || intent === expectedIntent,
              intent.contextGeneration == deferredBoundaryContext.generation,
              let client = intent.client as? IMKTextInput else {
            return false
        }

        switch intent.phase {
        case .ready:
            beginAggregateCommit(intent, client: client)
        case .committedTextInFlight:
            completeAggregateCommit(intent, client: client, postSelection: nil, clearIfMissing: true)
        case .committedSelectionReady:
            queryAggregateCommitSelection(intent, client: client)
        case .committedSelectionQueryInFlight:
            completeAggregateCommit(intent, client: client, postSelection: nil, clearIfMissing: true)
        case .markedTextInFlight:
            completeAggregateMarkedText(intent, clientMarkedRange: nil, clearIfMissing: true)
        case .markedRangeReady:
            queryAggregateMarkedRange(intent, client: client)
        case .markedRangeQueryInFlight:
            completeAggregateMarkedText(intent, clientMarkedRange: nil, clearIfMissing: true)
        }
        return true
    }

    private func beginAggregateCommit(
        _ intent: DeferredBoundaryAggregateApplyIntent,
        client: IMKTextInput
    ) {
        guard !intent.committedText.isEmpty else {
            prepareAggregateMarkedText(intent, client: client)
            return
        }
        intent.phase = .committedTextInFlight
#if DEBUG
        let message = "before-fallback-batch-commit committedLength=\(intent.committedText.utf16.count) " +
            "replacement=\(NSStringFromRange(intent.commitReplacementRange))"
        logger.debug("\(message, privacy: .public)")
#endif
        client.insertText(intent.committedText, replacementRange: intent.commitReplacementRange)
        guard inFlightDeferredBoundaryAggregateApply === intent,
              intent.phase == .committedTextInFlight else {
            return
        }
        if intent.wasMarkedTextActive,
           MarkedTextRangePolicy.shouldUsePostCommitSelectedRange(
               preCommitSelectedRange: intent.preCommitSelectedRange,
               replacementRange: intent.commitReplacementRange
           ) {
            intent.phase = .committedSelectionReady
            _ = finishDeferredBoundaryFallbackAggregate(intent)
        } else {
            completeAggregateCommit(intent, client: client, postSelection: nil, clearIfMissing: false)
        }
    }

    private func completeAggregateCommit(
        _ intent: DeferredBoundaryAggregateApplyIntent,
        client: IMKTextInput,
        postSelection: NSRange?,
        clearIfMissing: Bool
    ) {
        markedTextRangeTracker.recordCommittedText(
            replacementRange: intent.commitReplacementRange,
            preCommitSelectedRange: intent.preCommitSelectedRange,
            committedLength: intent.committedText.utf16.count,
            wasMarkedTextActive: intent.wasMarkedTextActive,
            postCommitSelectedRange: postSelection,
            clearOwnershipIfPostSelectionMissing: clearIfMissing
        )
        markedText.clear()
        intent.phase = .ready
        prepareAggregateMarkedText(intent, client: client)
    }

    private func queryAggregateCommitSelection(
        _ intent: DeferredBoundaryAggregateApplyIntent,
        client: IMKTextInput
    ) {
        intent.phase = .committedSelectionQueryInFlight
        let selectedRange = client.selectedRange()
        guard inFlightDeferredBoundaryAggregateApply === intent,
              intent.contextGeneration == deferredBoundaryContext.generation,
              intent.phase == .committedSelectionQueryInFlight else {
            return
        }
        completeAggregateCommit(intent, client: client, postSelection: selectedRange, clearIfMissing: false)
    }

    private func completeAggregateMarkedText(
        _ intent: DeferredBoundaryAggregateApplyIntent,
        clientMarkedRange: NSRange?,
        clearIfMissing: Bool
    ) {
        DeferredAggregateMarkedCompletion.apply(
            tracker: &markedTextRangeTracker,
            pendingReplacement: &pendingMarkedTextReplacement,
            update: DeferredBoundaryAggregateMarkedUpdate(
                replacementRange: intent.markedReplacementRange,
                markedLength: intent.markedText.utf16.count,
                clientMarkedRange: clientMarkedRange,
                clearOwnershipIfClientRangeMissing: clearIfMissing
            )
        )
        inFlightDeferredBoundaryAggregateApply = nil
    }

    private func queryAggregateMarkedRange(
        _ intent: DeferredBoundaryAggregateApplyIntent,
        client: IMKTextInput
    ) {
        intent.phase = .markedRangeQueryInFlight
        let clientMarkedRange = client.markedRange()
        guard inFlightDeferredBoundaryAggregateApply === intent,
              intent.contextGeneration == deferredBoundaryContext.generation,
              intent.phase == .markedRangeQueryInFlight else {
            return
        }
        completeAggregateMarkedText(intent, clientMarkedRange: clientMarkedRange, clearIfMissing: false)
    }

    private func prepareAggregateMarkedText(
        _ intent: DeferredBoundaryAggregateApplyIntent,
        client: IMKTextInput
    ) {
        guard inFlightDeferredBoundaryAggregateApply === intent else {
            return
        }
        guard !intent.markedText.isEmpty else {
            inFlightDeferredBoundaryAggregateApply = nil
            return
        }

        pendingMarkedTextReplacement = markedTextRangeTracker.replacementForMarkedTextUpdate(
            wasMarkedTextActive: markedText.isActive
        )
        let (replacementRange, _) = MarkedTextRangePolicy.updateCompositionReplacementDecision(
            pendingMarkedTextReplacement: pendingMarkedTextReplacement
        )
        intent.markedReplacementRange = replacementRange
        markedText.replace(with: intent.markedText)
        intent.phase = .markedTextInFlight
#if DEBUG
        logger.debug("before-fallback-batch-marked markedLength=\(intent.markedText.utf16.count)")
#endif
        updateComposition()
        guard inFlightDeferredBoundaryAggregateApply === intent,
              intent.phase == .markedTextInFlight else {
            return
        }
        intent.phase = .markedRangeReady
        _ = finishDeferredBoundaryFallbackAggregate(intent)
    }
}
