import Foundation
import InputMethodKit
import os

extension DefaultHostBackend {
    func drainPendingInput() {}

    func activateEditingContext() {}

    func deactivateEditingContext() {}

    func advanceEditingContext() {}

    func clearOwnedRanges() {}

    func traceBeforeKeyInput(keyCode _: UInt16, client: IMKTextInput?) {
#if DEBUG
        ClientRangeTracer(logger: logger).logDefaultInconsistentMarkedRangeIfNeeded(
            client: client,
            markedText: markedText
        )
#endif
    }

    func updateComposition() {
        defer {
            pendingMarkedTextReplacementRange = nil
        }
        performHostCompositionUpdate()
    }

    func replacementRange() -> NSRange {
        let (replacementRange, reason) = DefaultMarkedTextRangePolicy.updateCompositionReplacementDecision(
            pendingMarkedTextReplacementRange: pendingMarkedTextReplacementRange
        )
#if DEBUG
        ClientRangeTracer(logger: logger).traceDefaultUpdateCompositionReplacementRange(
            replacementRange,
            reason: reason,
            client: textClient(from: nil),
            markedText: markedText
        )
#endif
        return replacementRange
    }
}
