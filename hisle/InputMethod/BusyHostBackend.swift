import Cocoa
import HisleCore
import InputMethodKit
import os

extension BusyHostBackend {
    func activateServer(_ sender: Any?) {
        drainDeferredBoundaryText()
        deferredBoundaryContext.activate()
        KeyboardLayoutOverride.installColemak(
            for: sender ?? inputController.hostClient(),
            logSuccess: true
        )
    }

    func deactivateServer(_ sender: Any?) {
        drainDeferredBoundaryText()
        flushBeforeForwarding(to: sender)
        markedTextRangeTracker.clear()
        deferredBoundaryContext.deactivate()
        shiftTap = ShiftTapDetector()
    }

    func inputControllerWillClose() {
        drainDeferredBoundaryText()
        flushBeforeForwarding(to: inputController.hostClient())
        markedTextRangeTracker.clear()
        deferredBoundaryContext.deactivate()
    }

    func setValue(_ value: Any?, forTag tag: Int, client sender: Any?) {
        drainDeferredBoundaryText()
        KeyboardLayoutOverride.installColemak(for: sender, logSuccess: true)

        if tag == kTextServiceInputModePropertyTag {
            selectRomanModeForInputSourceSelection(client: sender)
        }
    }

    func mouseDown(client sender: Any) -> Bool {
        drainDeferredBoundaryText()
        flushBeforeForwarding(to: sender)
        markedTextRangeTracker.clear()
        deferredBoundaryContext.advanceEditingContext()
        return false
    }

    func handle(_ event: NSEvent, client sender: Any) -> Bool {
        drainDeferredBoundaryText()
        KeyboardLayoutOverride.installColemak(for: sender)

        if event.type == .leftMouseDown || event.type == .rightMouseDown || event.type == .otherMouseDown {
            flushBeforeForwarding(to: sender)
            markedTextRangeTracker.clear()
            deferredBoundaryContext.advanceEditingContext()
            return false
        }

        if event.type == .flagsChanged {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
#if DEBUG
            NSLog("hisle flagsChanged keyCode=\(event.keyCode) modifiers=\(modifiers.rawValue)")
            let flagsChangedMessage = "flagsChanged keyCode=\(event.keyCode) modifiers=\(modifiers.rawValue)"
            logger.debug("\(flagsChangedMessage, privacy: .public)")
#endif

            guard let selectedMode = shiftTap.handleFlagsChanged(
                keyCode: event.keyCode,
                modifiers: modifiers
            ) else {
                return false
            }
            return selectInputMode(selectedMode, client: sender)
        }

        guard event.type == .keyDown else {
            return false
        }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
#if DEBUG
        let textLength = event.characters?.utf16.count ?? 0
        NSLog("hisle handle keyCode=\(event.keyCode) modifiers=\(modifiers.rawValue) textLength=\(textLength)")
        let handleMessage = "handle keyCode=\(event.keyCode) modifiers=\(modifiers.rawValue) " +
            "textLength=\(textLength)"
        logger.debug("\(handleMessage, privacy: .public)")
#endif

        return handleKeyInput(
            text: event.characters,
            keyCode: event.keyCode,
            modifiers: modifiers,
            client: sender
        )
    }

    func commitComposition(_ sender: Any?) {
        drainDeferredBoundaryText()
        _ = apply(hangulEngine.process(.flush), to: sender)
        markedTextRangeTracker.clear()
        deferredBoundaryContext.advanceEditingContext()
    }

    func cancelComposition() {
        drainDeferredBoundaryText()
        _ = apply(hangulEngine.process(.clear), to: inputController.hostClient())
        markedTextRangeTracker.clear()
        deferredBoundaryContext.advanceEditingContext()
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
