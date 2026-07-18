import Cocoa
import HisleCore
import InputMethodKit
import os

protocol HostBackendImplementation: HostBackend {
    var compatibility: HostBackendCompatibility { get }
    var context: any HostBackendContext { get }
    var hangulEngine: ColeSebeolEngine { get set }
    var markedText: MarkedTextState { get set }
    var shiftTap: ShiftTapDetector { get set }
    var keyClassifier: InputKeyClassifier { get }
    var logger: Logger { get }
    var inputMode: HisleInputMode { get set }

    func textClient(from sender: Any?) -> IMKTextInput?
    func process(_ input: ColeSebeolInput, client sender: Any?) -> Bool
    func flushBeforeForwarding(to sender: Any?)
    func commitRomanText(_ text: String, client sender: Any?) -> Bool
    func handleHangulFallbackText(_ text: String, client sender: Any?) -> Bool

    func drainPendingInput()
    func activateEditingContext()
    func deactivateEditingContext()
    func advanceEditingContext()
    func clearOwnedRanges()
    func traceBeforeKeyInput(keyCode: UInt16, client: IMKTextInput?)
}

extension HostBackendImplementation {
    func activateServer(_ sender: Any?) {
        performLifecycleOperations(for: .activate, sender: sender)
        KeyboardLayoutOverride.installColemak(
            for: sender ?? context.hostClient(),
            logSuccess: true
        )
    }

    func deactivateServer(_ sender: Any?) {
        performLifecycleOperations(for: .deactivate, sender: sender)
    }

    func inputControllerWillClose() {
        performLifecycleOperations(for: .close, sender: context.hostClient())
    }

    func setValue(_ value: Any?, forTag tag: Int, client sender: Any?) {
        if compatibility.lifecycle.drainsDeferredInput {
            drainPendingInput()
        }
        KeyboardLayoutOverride.installColemak(for: sender, logSuccess: true)

        if tag == kTextServiceInputModePropertyTag {
            selectRomanModeForInputSourceSelection(client: sender)
        }
    }

    func mouseDown(client sender: Any) -> Bool {
        performLifecycleOperations(for: .mouseDown, sender: sender)
        return false
    }

    func handle(_ event: NSEvent, client sender: Any) -> Bool {
        if compatibility.lifecycle.drainsDeferredInput {
            drainPendingInput()
        }
        KeyboardLayoutOverride.installColemak(for: sender)

        if compatibility.lifecycle.handlesMouseEventsInEventCallback &&
            (event.type == .leftMouseDown || event.type == .rightMouseDown || event.type == .otherMouseDown) {
            performLifecycleOperations(for: .mouseDown, sender: sender, skipInitialDrain: true)
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
        if compatibility.lifecycle.drainsDeferredInput {
            drainPendingInput()
        }
        _ = applyEngineInput(.flush, client: sender)
        finishExternalCompositionBoundary()
    }

    func cancelComposition() {
        if compatibility.lifecycle.drainsDeferredInput {
            drainPendingInput()
        }
        _ = applyEngineInput(.clear, client: context.hostClient())
        finishExternalCompositionBoundary()
    }

    func handleKeyInput(
        text: String?,
        keyCode: UInt16,
        modifiers flags: NSEvent.ModifierFlags,
        client sender: Any?
    ) -> Bool {
        if compatibility.lifecycle.drainsDeferredInput {
            drainPendingInput()
        }
        if compatibility.lifecycle.ownsEditingContext {
            advanceEditingContext()
        }
        shiftTap.cancelForKeyInput()
#if DEBUG
        let client = textClient(from: sender)
        ClientRangeTracer(logger: logger).traceClientRanges(
            "before-key keyCode=\(keyCode)",
            client: client,
            markedText: markedText
        )
        traceBeforeKeyInput(keyCode: keyCode, client: client)
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
        if compatibility.lifecycle.drainsDeferredInput {
            drainPendingInput()
        }
        guard inputMode != mode else {
            HisleInputModeState.write(mode)
            return handled
        }

        if inputMode == .hangul {
            flushBeforeForwarding(to: sender)
        }

        if compatibility.lifecycle.ownsEditingContext {
            clearOwnedRanges()
            advanceEditingContext()
        }
        inputMode = mode
#if DEBUG
        logger.debug("input mode selected \(mode.description, privacy: .public)")
#endif
        return handled
    }

    func selectRomanModeForInputSourceSelection(client sender: Any?) {
        if compatibility.lifecycle.drainsDeferredInput {
            drainPendingInput()
        }
        shiftTap = ShiftTapDetector()
        if compatibility.lifecycle.ownsEditingContext {
            flushBeforeForwarding(to: sender)
        }
        _ = selectInputMode(.roman, client: sender)
        if compatibility.lifecycle.ownsEditingContext {
            clearOwnedRanges()
            advanceEditingContext()
        }
    }

    private func handleKeyAction(_ action: InputKeyAction, client sender: Any?) -> Bool {
        switch action {
        case let .selectInputMode(mode, handled):
            return selectInputMode(mode, client: sender, handled: handled)
        case .forwardToHost:
            flushBeforeForwarding(to: sender)
            finishForwardedHostAction()
            return false
        case let .whitespace(scalar):
            return handleWhitespace(scalar, client: sender)
        case .deleteBackward:
            guard inputMode == .hangul else {
                flushBeforeForwarding(to: sender)
                finishForwardedHostAction()
                return false
            }
            let handled = process(.backspace, client: sender)
            if !handled {
                finishForwardedHostAction()
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

        guard !output.isEmpty else {
            return false
        }
        return commitRomanText(output, client: sender)
    }

    private func applyEngineInput(_ input: ColeSebeolInput, client sender: Any?) -> Bool {
        process(input, client: sender)
    }

    private func finishExternalCompositionBoundary() {
        guard compatibility.lifecycle.ownsEditingContext else {
            return
        }
        clearOwnedRanges()
        advanceEditingContext()
    }

    private func finishForwardedHostAction() {
        guard compatibility.lifecycle.ownsEditingContext else {
            return
        }
        clearOwnedRanges()
        advanceEditingContext()
    }

    private func performLifecycleOperations(
        for event: HostBackendLifecycleEvent,
        sender: Any?,
        skipInitialDrain: Bool = false
    ) {
        for operation in compatibility.lifecycle.operations(for: event) {
            switch operation {
            case .drainDeferredInput:
                if !skipInitialDrain {
                    drainPendingInput()
                }
            case .activateEditingContext:
                activateEditingContext()
            case .flushComposition:
                flushBeforeForwarding(to: sender)
            case .clearOwnedRanges:
                clearOwnedRanges()
            case .deactivateEditingContext:
                deactivateEditingContext()
            case .advanceEditingContext:
                advanceEditingContext()
            case .resetShiftTap:
                shiftTap = ShiftTapDetector()
            }
        }
    }
}
