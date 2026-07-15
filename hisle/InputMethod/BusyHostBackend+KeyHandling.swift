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
    func handleKeyInput(
        text: String?,
        keyCode: UInt16,
        modifiers flags: NSEvent.ModifierFlags,
        client sender: Any?
    ) -> Bool {
        drainDeferredBoundaryText()
        deferredBoundaryContext.advanceEditingContext()
        shiftTap.cancelForKeyInput()
#if DEBUG
        let tracer = ClientRangeTracer(logger: logger)
        let client = textClient(from: sender)
        tracer.traceClientRanges(
            "before-key keyCode=\(keyCode)",
            client: client,
            markedText: markedText
        )
        tracer.logInconsistentMarkedRangeIfNeeded(client: client, markedText: markedText)
#endif

        let action = keyClassifier.classify(
            text: text,
            keyCode: keyCode,
            modifiers: flags
        )
        return handleKeyAction(action, client: sender)
    }

    func selectInputMode(
        _ mode: HisleInputMode,
        client sender: Any?,
        handled: Bool = true
    ) -> Bool {
        drainDeferredBoundaryText()
        guard inputMode != mode else {
            HisleInputModeState.write(mode)
            return handled
        }

        if inputMode == .hangul {
            flushBeforeForwarding(to: sender)
        }

        markedTextRangeTracker.clear()
        deferredBoundaryContext.advanceEditingContext()
        inputMode = mode
#if DEBUG
        logger.debug("input mode selected \(mode.description, privacy: .public)")
#endif
        return handled
    }

    func selectRomanModeForInputSourceSelection(client sender: Any?) {
        drainDeferredBoundaryText()
        shiftTap = ShiftTapDetector()
        flushBeforeForwarding(to: sender)
        _ = selectInputMode(.roman, client: sender)
        markedTextRangeTracker.clear()
        deferredBoundaryContext.advanceEditingContext()
    }

    private func handleKeyAction(_ action: InputKeyAction, client sender: Any?) -> Bool {
        switch action {
        case let .selectInputMode(mode, handled):
            return selectInputMode(mode, client: sender, handled: handled)
        case .forwardToHost:
            flushBeforeForwarding(to: sender)
            markedTextRangeTracker.clear()
            deferredBoundaryContext.advanceEditingContext()
            return false
        case let .whitespace(scalar):
            return handleWhitespace(scalar, client: sender)
        case .deleteBackward:
            guard inputMode == .hangul else {
                flushBeforeForwarding(to: sender)
                markedTextRangeTracker.clear()
                deferredBoundaryContext.advanceEditingContext()
                return false
            }
            let handled = process(.backspace, client: sender)
            if !handled {
                markedTextRangeTracker.clear()
                deferredBoundaryContext.advanceEditingContext()
            }
            return handled
        case let .representativeKey(representativeKey):
            return handleRepresentativeKey(representativeKey, client: sender)
        case let .fallbackText(text):
            return handleFallbackText(text, client: sender)
        case .ignored:
            return false
        }
    }

    private func handleWhitespace(_ scalar: Unicode.Scalar, client sender: Any?) -> Bool {
        switch inputMode {
        case .hangul:
            return process(.whitespace(scalar), client: sender)
        case .roman:
            return commitRomanText(String(scalar), client: sender)
        }
    }

    private func handleRepresentativeKey(_ representativeKey: Unicode.Scalar, client sender: Any?) -> Bool {
        switch inputMode {
        case .hangul:
            return process(.representativeKey(representativeKey), client: sender)
        case .roman:
            let romanKey = hangulEngine.layout.underlyingRomanKey(forRepresentativeKey: representativeKey)
                ?? representativeKey
            return commitRomanText(String(romanKey), client: sender)
        }
    }

    private func handleFallbackText(_ text: String, client sender: Any?) -> Bool {
        switch inputMode {
        case .hangul:
            return handleHangulFallbackText(text, client: sender)
        case .roman:
            return handleRomanFallbackText(text, client: sender)
        }
    }

    private func handleHangulFallbackText(_ text: String, client sender: Any?) -> Bool {
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

    private func handleRomanFallbackText(_ text: String, client sender: Any?) -> Bool {
        var output = ""

        for scalar in text.unicodeScalars {
            if scalar == " " {
                output.append(String(scalar))
            } else if scalar.properties.isWhitespace && !CharacterSet.controlCharacters.contains(scalar) {
                output.append(String(scalar))
            } else if ColeSebeolLayout.printableRepresentativeScalars.contains(scalar.value) {
                let romanKey = hangulEngine.layout.underlyingRomanKey(forRepresentativeKey: scalar)
                    ?? scalar
                output.append(String(romanKey))
            }
        }

        guard output.isEmpty == false else {
            return false
        }
        return commitRomanText(output, client: sender)
    }
}
