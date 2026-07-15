import Cocoa
import HisleCore
import InputMethodKit
import os

extension DefaultHostBackend {
    func activateServer(_ sender: Any?) {
        KeyboardLayoutOverride.installColemak(
            for: sender ?? inputController.hostClient(),
            logSuccess: true
        )
    }

    func deactivateServer(_ sender: Any?) {
        flushBeforeForwarding(to: sender)
        shiftTap = ShiftTapDetector()
    }

    func inputControllerWillClose() {}

    func setValue(_ value: Any?, forTag tag: Int, client sender: Any?) {
        KeyboardLayoutOverride.installColemak(for: sender, logSuccess: true)

        if tag == kTextServiceInputModePropertyTag {
            selectRomanModeForInputSourceSelection(client: sender)
        }
    }

    func mouseDown(client sender: Any) -> Bool {
        flushBeforeForwarding(to: sender)
        return false
    }

    func handle(_ event: NSEvent, client sender: Any) -> Bool {
        KeyboardLayoutOverride.installColemak(for: sender)

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
        _ = apply(hangulEngine.process(.flush), to: sender)
    }

    func cancelComposition() {
        _ = apply(hangulEngine.process(.clear), to: inputController.hostClient())
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
