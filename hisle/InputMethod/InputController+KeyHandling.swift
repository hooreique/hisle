import Cocoa
import HisleCore
import os

extension InputController {
    func handleKeyInput(
        text: String?,
        keyCode: UInt16,
        modifiers flags: NSEvent.ModifierFlags,
        client sender: Any?
    ) -> Bool {
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
        guard inputMode != mode else {
            HisleInputModeState.write(mode)
            return handled
        }

        if inputMode == .hangul {
            flushBeforeForwarding(to: sender)
        }

        markedTextRangeTracker.clear()
        inputMode = mode
#if DEBUG
        logger.debug("input mode selected \(mode.description, privacy: .public)")
#endif
        return handled
    }

    func selectRomanModeForInputSourceSelection(client sender: Any?) {
        shiftTap = ShiftTapDetector()
        markedTextRangeTracker.clear()
        _ = selectInputMode(.roman, client: sender)
    }

    private func handleKeyAction(_ action: InputKeyAction, client sender: Any?) -> Bool {
        switch action {
        case let .selectInputMode(mode, handled):
            return selectInputMode(mode, client: sender, handled: handled)
        case .forwardToHost:
            flushBeforeForwarding(to: sender)
            markedTextRangeTracker.clear()
            return false
        case let .whitespace(scalar):
            return handleWhitespace(scalar, client: sender)
        case .deleteBackward:
            guard inputMode == .hangul else {
                flushBeforeForwarding(to: sender)
                markedTextRangeTracker.clear()
                return false
            }
            let handled = process(.backspace, client: sender)
            if !handled {
                markedTextRangeTracker.clear()
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
        var handled = false

        for scalar in text.unicodeScalars {
            if scalar == " " {
                handled = handleWhitespace(scalar, client: sender) || handled
            } else if scalar.properties.isWhitespace && !CharacterSet.controlCharacters.contains(scalar) {
                handled = handleWhitespace(scalar, client: sender) || handled
            } else if ColeSebeolLayout.printableRepresentativeScalars.contains(scalar.value) {
                handled = handleRepresentativeKey(scalar, client: sender) || handled
            }
        }

        return handled
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
