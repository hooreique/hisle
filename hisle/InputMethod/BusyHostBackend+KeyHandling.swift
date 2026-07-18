import Cocoa
import HisleCore
import InputMethodKit
import os

private struct HangulFallbackContextSnapshot {
    let generation: UInt64
    let markedText: String
    let markedRange: NSRange?
    let insertionRange: NSRange?
    let replacementDecision: MarkedTextReplacementDecision
}

private struct HangulFallbackBatchPreparation {
    let engine: ColeSebeolEngine
    let batch: DeferredBoundaryFallbackBatch
}

extension BusyHostBackend {
    func handleHangulFallbackText(_ text: String, client sender: Any?) -> Bool {
        processHangulFallbackScalars(Array(text.unicodeScalars), client: sender)
    }

    func processHangulFallbackScalars(
        _ scalars: [Unicode.Scalar],
        client sender: Any?,
        preserveOwnedInsertionRange: Bool = false
    ) -> Bool {
        if !preserveOwnedInsertionRange {
            drainDeferredBoundaryText()
        }
        guard let client = textClient(from: sender) else {
            logger.error("missing IMKTextInput client for fallback batch")
            return false
        }
        guard let snapshot = fallbackContextSnapshot(client: client),
              let preparation = prepareHangulFallbackBatch(scalars, snapshot: snapshot),
              fallbackContextIsCurrent(snapshot) else {
            return false
        }

        if preparation.batch.boundaryText != nil {
            beginDeferredFallbackBoundary(preparation, snapshot: snapshot, client: client)
        } else {
            beginFallbackAggregate(
                preparation,
                snapshot: snapshot,
                client: client,
                preserveOwnedInsertionRange: preserveOwnedInsertionRange
            )
        }
        return preparation.batch.handled
    }

    private func fallbackContextSnapshot(client: IMKTextInput) -> HangulFallbackContextSnapshot? {
        let generation = deferredBoundaryContext.generation
        let initialMarkedText = markedText.string
        let initialMarkedRange = markedTextRangeTracker.markedRange
        let initialInsertionRange = markedTextRangeTracker.insertionRange
        let decision = replacementDecision(for: client)
        let snapshot = HangulFallbackContextSnapshot(
            generation: generation,
            markedText: initialMarkedText,
            markedRange: initialMarkedRange,
            insertionRange: initialInsertionRange,
            replacementDecision: decision
        )
        return fallbackContextIsCurrent(snapshot) ? snapshot : nil
    }

    private func fallbackContextIsCurrent(_ snapshot: HangulFallbackContextSnapshot) -> Bool {
        snapshot.generation == deferredBoundaryContext.generation &&
            snapshot.markedText == markedText.string &&
            snapshot.markedRange == markedTextRangeTracker.markedRange &&
            snapshot.insertionRange == markedTextRangeTracker.insertionRange
    }

    private func prepareHangulFallbackBatch(
        _ scalars: [Unicode.Scalar],
        snapshot: HangulFallbackContextSnapshot
    ) -> HangulFallbackBatchPreparation? {
        var nextEngine = hangulEngine
        var hasForwardedActions = false
        let batch = DeferredBoundaryFallbackProcessor.process(
            scalars,
            deferFirstBoundary: !snapshot.markedText.isEmpty
        ) { scalar in
            guard let (input, boundaryText) = hangulFallbackInput(for: scalar) else {
                return nil
            }
            let output = nextEngine.process(input)
            hasForwardedActions = !output.forwardedActions.isEmpty || hasForwardedActions
            return DeferredBoundaryFallbackStep(
                handled: output.forwardedActions.isEmpty,
                committedText: output.committedText,
                markedText: output.markedText,
                hasForwardedActions: !output.forwardedActions.isEmpty,
                boundaryText: boundaryText
            )
        }
        guard batch.didProcessInput, !hasForwardedActions else {
            return nil
        }
        return HangulFallbackBatchPreparation(engine: nextEngine, batch: batch)
    }

    private func hangulFallbackInput(
        for scalar: Unicode.Scalar
    ) -> (ColeSebeolInput, boundaryText: String?)? {
        if scalar == " " ||
            (scalar.properties.isWhitespace && !CharacterSet.controlCharacters.contains(scalar)) {
            return (.whitespace(scalar), String(scalar))
        }
        if ColeSebeolLayout.printableRepresentativeScalars.contains(scalar.value) {
            return (.representativeKey(scalar), nil)
        }
        return nil
    }

    private func beginDeferredFallbackBoundary(
        _ preparation: HangulFallbackBatchPreparation,
        snapshot: HangulFallbackContextSnapshot,
        client: IMKTextInput
    ) {
        guard let boundaryText = preparation.batch.boundaryText else {
            return
        }
        let compositionText = String(preparation.batch.committedText.dropLast(boundaryText.count))
        guard !compositionText.isEmpty else {
            return
        }
        let intent = DeferredBoundaryCommitIntent(
            compositionText: compositionText,
            boundaryText: boundaryText,
            continuationScalars: preparation.batch.continuationScalars,
            client: client,
            contextGeneration: snapshot.generation,
            replacementRange: snapshot.replacementDecision.replacementRange,
            preCommitSelectedRange: snapshot.replacementDecision.selectedRange
        )
        inFlightDeferredBoundaryCommit = intent
        hangulEngine = preparation.engine
        insertCompositionForDeferredBoundary(intent, client: client)
    }

    private func beginFallbackAggregate(
        _ preparation: HangulFallbackBatchPreparation,
        snapshot: HangulFallbackContextSnapshot,
        client: IMKTextInput,
        preserveOwnedInsertionRange: Bool
    ) {
        let intent = DeferredBoundaryAggregateApplyIntent(
            committedText: preparation.batch.committedText,
            markedText: preparation.batch.markedText,
            client: client,
            contextGeneration: snapshot.generation,
            commitReplacementRange: snapshot.replacementDecision.replacementRange,
            preCommitSelectedRange: snapshot.replacementDecision.selectedRange,
            preserveOwnedInsertionRange: preserveOwnedInsertionRange,
            wasMarkedTextActive: !snapshot.markedText.isEmpty || preserveOwnedInsertionRange
        )
        inFlightDeferredBoundaryAggregateApply = intent
        hangulEngine = preparation.engine
        _ = finishDeferredBoundaryFallbackAggregate(intent)
    }

}
