import Foundation
import InputMethodKit
import os

extension BusyHostBackend {
    func drainPendingInput() {
        drainDeferredBoundaryText()
    }

    func activateEditingContext() {
        deferredBoundaryContext.activate()
    }

    func deactivateEditingContext() {
        deferredBoundaryContext.deactivate()
    }

    func advanceEditingContext() {
        deferredBoundaryContext.advanceEditingContext()
    }

    func clearOwnedRanges() {
        markedTextRangeTracker.clear()
    }

    func traceBeforeKeyInput(keyCode _: UInt16, client: IMKTextInput?) {
#if DEBUG
        ClientRangeTracer(logger: logger).logInconsistentMarkedRangeIfNeeded(
            client: client,
            markedText: markedText
        )
#endif
    }

    func updateComposition() {
        lastUpdateCompositionReplacementRange = nil
        defer {
            pendingMarkedTextReplacement = nil
        }
        performHostCompositionUpdate()
    }

    func replacementRange() -> NSRange {
        let (replacementRange, reason) = MarkedTextRangePolicy.updateCompositionReplacementDecision(
            pendingMarkedTextReplacement: pendingMarkedTextReplacement
        )
        lastUpdateCompositionReplacementRange = replacementRange
#if DEBUG
        if inFlightDeferredBoundaryAggregateApply == nil {
            ClientRangeTracer(logger: logger).traceUpdateCompositionReplacementRange(
                replacementRange,
                reason: reason,
                client: textClient(from: nil),
                markedText: markedText
            )
        } else {
            let replacementMessage = "client-range update-composition " +
                "replacement=\(NSStringFromRange(replacementRange)) reason=\(reason.rawValue) " +
                "deferred-aggregate-in-flight"
            logger.debug("\(replacementMessage, privacy: .public)")
        }
#endif
        return replacementRange
    }
}
