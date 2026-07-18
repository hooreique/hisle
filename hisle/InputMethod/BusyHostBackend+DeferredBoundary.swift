import Foundation
import InputMethodKit
import os

extension BusyHostBackend {
    func insertCompositionBeforeDeferredBoundary(
        _ compositionText: String,
        boundaryText: String,
        continuationScalars: [Unicode.Scalar],
        client: IMKTextInput,
        replacementDecision suppliedReplacementDecision: MarkedTextReplacementDecision? = nil
    ) {
        let replacementDecision = suppliedReplacementDecision ?? replacementDecision(for: client)
        let replacementRange = replacementDecision.replacementRange
        let intent = DeferredBoundaryCommitIntent(
            compositionText: compositionText,
            boundaryText: boundaryText,
            continuationScalars: continuationScalars,
            client: client,
            contextGeneration: deferredBoundaryContext.generation,
            replacementRange: replacementRange,
            preCommitSelectedRange: replacementDecision.selectedRange
        )
        inFlightDeferredBoundaryCommit = intent
        insertCompositionForDeferredBoundary(intent, client: client)
    }

    func insertCompositionForDeferredBoundary(
        _ intent: DeferredBoundaryCommitIntent,
        client: IMKTextInput
    ) {
#if DEBUG
        let commitMessage = "before-commit committedLength=\(intent.compositionText.utf16.count) " +
            "replacement=\(NSStringFromRange(intent.replacementRange))"
        logger.debug("\(commitMessage, privacy: .public)")
#endif
        client.insertText(intent.compositionText, replacementRange: intent.replacementRange)
        guard inFlightDeferredBoundaryCommit === intent,
              intent.phase == .textInFlight else {
            return
        }
        if MarkedTextRangePolicy.shouldUsePostCommitSelectedRange(
            preCommitSelectedRange: intent.preCommitSelectedRange,
            replacementRange: intent.replacementRange
        ) {
            intent.phase = .selectionReady
            _ = finishInFlightDeferredBoundaryCommit(intent)
        } else {
            completeDeferredBoundaryCommit(
                intent,
                client: client,
                postCommitSelectedRange: nil,
                clearOwnershipIfPostSelectionMissing: false
            )
        }
    }

    @discardableResult
    private func finishInFlightDeferredBoundaryCommit(
        _ expectedIntent: DeferredBoundaryCommitIntent? = nil
    ) -> Bool {
        guard let intent = inFlightDeferredBoundaryCommit,
              expectedIntent == nil || intent === expectedIntent,
              intent.contextGeneration == deferredBoundaryContext.generation,
              let client = intent.client as? IMKTextInput else {
            return false
        }
        switch intent.phase {
        case .textInFlight, .selectionQueryInFlight:
            completeDeferredBoundaryCommit(
                intent,
                client: client,
                postCommitSelectedRange: nil,
                clearOwnershipIfPostSelectionMissing: true
            )
        case .selectionReady:
            intent.phase = .selectionQueryInFlight
            let selectedRange = client.selectedRange()
            guard inFlightDeferredBoundaryCommit === intent,
                  intent.contextGeneration == deferredBoundaryContext.generation,
                  intent.phase == .selectionQueryInFlight else {
                return true
            }
            completeDeferredBoundaryCommit(
                intent,
                client: client,
                postCommitSelectedRange: selectedRange,
                clearOwnershipIfPostSelectionMissing: false
            )
        }
        return true
    }

    private func completeDeferredBoundaryCommit(
        _ intent: DeferredBoundaryCommitIntent,
        client: IMKTextInput,
        postCommitSelectedRange: NSRange?,
        clearOwnershipIfPostSelectionMissing: Bool
    ) {
        inFlightDeferredBoundaryCommit = nil
        markedTextRangeTracker.recordCommittedText(
            replacementRange: intent.replacementRange,
            preCommitSelectedRange: intent.preCommitSelectedRange,
            committedLength: intent.compositionText.utf16.count,
            wasMarkedTextActive: true,
            postCommitSelectedRange: postCommitSelectedRange,
            clearOwnershipIfPostSelectionMissing: clearOwnershipIfPostSelectionMissing
        )
        markedText.clear()
        scheduleCommittedBoundaryText(
            intent.boundaryText,
            continuationScalars: intent.continuationScalars,
            client: client,
            contextGeneration: intent.contextGeneration
        )
    }

    private func scheduleCommittedBoundaryText(
        _ text: String,
        continuationScalars: [Unicode.Scalar],
        client: IMKTextInput,
        contextGeneration: UInt64
    ) {
        deferredBoundaryQueue.schedule(
            text: text,
            client: client,
            contextGeneration: contextGeneration,
            expectedInsertionRange: markedTextRangeTracker.insertionRange,
            continuationScalars: continuationScalars
        ) { [self, context] ticket in
            // Preserve the production host context while the selected backend
            // owns a deferred callback without coupling it to InputController.
            withExtendedLifetime(context) {
                resolveScheduledBoundaryText(ticket)
            }
        }
    }

    @discardableResult
    func drainDeferredBoundaryText() -> Bool {
        var didDrain = false
        while true {
            if finishInFlightDeferredBoundaryCommit() {
                didDrain = true
                continue
            }
            if finishDeferredBoundaryFallbackAggregate() {
                didDrain = true
                continue
            }
            if drainInFlightDeferredBoundaryContinuation() {
                didDrain = true
                continue
            }
            if let work = deferredBoundaryQueue.takePending() {
                insertCommittedBoundaryText(work)
                didDrain = true
                continue
            }
            break
        }
        return didDrain
    }

    private func resolveScheduledBoundaryText(_ ticket: DeferredBoundaryTicket) {
        guard deferredBoundaryContext.isActive else {
            return
        }
        guard let work = deferredBoundaryQueue.takeScheduled(
            ticket: ticket,
            contextGeneration: deferredBoundaryContext.generation
        ) else {
            return
        }
        insertCommittedBoundaryText(work)
    }

    private func insertCommittedBoundaryText(_ work: DeferredBoundaryWork) {
        guard let client = work.client as? IMKTextInput else {
            logger.error("deferred boundary owner no longer conforms to IMKTextInput")
            return
        }
        guard DeferredBoundaryDeliveryPolicy.canDeliver(
            work,
            context: deferredBoundaryContext,
            hasMarkedText: markedText.isActive,
            ownedMarkedRange: markedTextRangeTracker.markedRange,
            ownedInsertionRange: markedTextRangeTracker.insertionRange
        ) else {
            logger.error("deferred boundary editing context changed before insertion")
            return
        }
        let replacementRange = MarkedTextRangePolicy.currentSelectionReplacementRange
#if DEBUG
        let boundaryMessage = "before-boundary committedLength=\(work.text.utf16.count) " +
            "replacement=\(NSStringFromRange(replacementRange))"
        logger.debug("\(boundaryMessage, privacy: .public)")
#endif
        markedTextRangeTracker.recordBoundaryTextAfterActiveComposition(
            committedLength: work.text.utf16.count
        )
        if !work.continuationScalars.isEmpty {
            inFlightDeferredBoundaryContinuation = DeferredBoundaryContinuation(
                scalars: work.continuationScalars,
                client: client,
                contextGeneration: work.contextGeneration
            )
        }
        client.insertText(work.text, replacementRange: replacementRange)
        guard deferredBoundaryContext.isActive,
              work.contextGeneration == deferredBoundaryContext.generation else {
            return
        }
        if !work.continuationScalars.isEmpty {
            _ = drainInFlightDeferredBoundaryContinuation()
        }
    }

    private func drainInFlightDeferredBoundaryContinuation() -> Bool {
        guard let continuation = inFlightDeferredBoundaryContinuation else {
            return false
        }
        guard deferredBoundaryContext.isActive,
              continuation.contextGeneration == deferredBoundaryContext.generation,
              let client = continuation.client as? IMKTextInput else {
            logger.error("deferred boundary continuation editing context changed")
            return false
        }

        inFlightDeferredBoundaryContinuation = nil
        _ = processHangulFallbackScalars(
            continuation.scalars,
            client: client,
            preserveOwnedInsertionRange: true
        )
        return true
    }
}
