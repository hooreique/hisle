import Cocoa
import HisleCore
import InputMethodKit
import os

@objc(HisleInputController)
final class InputController: IMKInputController {
    private let logger = Logger(subsystem: "hooreique.inputmethod.hisle", category: "InputController")
    private static var sharedInputMode = HisleInputMode.roman {
        didSet {
            HisleInputModeState.write(sharedInputMode)
        }
    }
#if DEBUG
    private static let replacementRangePolicyID = "current-selection-nsnotfound+marked-continuation"
#endif

    private var hangulEngine = InputController.makeEngine()
    private var hasMarkedText = false
    private var currentMarkedText = ""
    private var pendingMarkedTextReplacementRange: NSRange?
    private var shiftTap = ShiftTapDetector()

    private var inputMode: HisleInputMode {
        get { Self.sharedInputMode }
        set { Self.sharedInputMode = newValue }
    }

    private var currentSelectionReplacementRange: NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        HisleInputModeState.write(inputMode)
        logger.notice("controller initialized")
#if DEBUG
        logRuntimeIdentity(stage: "init")
        logger.debug("controller client=\(String(describing: inputClient), privacy: .public)")
#endif
    }

    override func activateServer(_ sender: Any!) {
        KeyboardLayoutOverride.installColemak(for: sender ?? client(), logSuccess: true)
#if DEBUG
        logRuntimeIdentity(stage: "activate")
#endif
        super.activateServer(sender)
    }

    override func deactivateServer(_ sender: Any!) {
        flushBeforeForwarding(to: sender)
        shiftTap = ShiftTapDetector()
        super.deactivateServer(sender)
    }

    override func setValue(_ value: Any!, forTag tag: Int, client sender: Any!) {
        KeyboardLayoutOverride.installColemak(for: sender, logSuccess: true)

        if tag == kTextServiceInputModePropertyTag {
            selectRomanModeForInputSourceSelection(client: sender)
        }

        super.setValue(value, forTag: tag, client: sender)
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask(arrayLiteral:
            .keyDown,
            .flagsChanged,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown
        ).rawValue)
    }

    override func mouseDown(
        onCharacterIndex _: Int,
        coordinate _: NSPoint,
        withModifier _: Int,
        continueTracking _: UnsafeMutablePointer<ObjCBool>!,
        client sender: Any
    ) -> Bool {
        flushBeforeForwarding(to: sender)
        return false
    }

    override func handle(_ event: NSEvent, client sender: Any) -> Bool {
        KeyboardLayoutOverride.installColemak(for: sender)

        if event.type == .flagsChanged {
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
#if DEBUG
            NSLog("hisle flagsChanged keyCode=\(event.keyCode) modifiers=\(modifiers.rawValue)")
            logger.debug("flagsChanged keyCode=\(event.keyCode, privacy: .public) modifiers=\(modifiers.rawValue, privacy: .public)")
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
        logger.debug("handle keyCode=\(event.keyCode, privacy: .public) modifiers=\(modifiers.rawValue, privacy: .public) textLength=\(textLength, privacy: .public)")
#endif

        return handleKeyInput(
            text: event.characters,
            keyCode: event.keyCode,
            modifiers: modifiers,
            client: sender
        )
    }

    @objc override func commitComposition(_ sender: Any!) {
        _ = apply(hangulEngine.process(.flush), to: sender)
    }

    override func cancelComposition() {
        _ = apply(hangulEngine.process(.clear), to: client())
    }

    @objc override func updateComposition() {
        defer {
            pendingMarkedTextReplacementRange = nil
        }
        super.updateComposition()
    }

    @objc override func replacementRange() -> NSRange {
        let replacementRange = pendingMarkedTextReplacementRange ?? currentSelectionReplacementRange
#if DEBUG
        traceUpdateCompositionReplacementRange(
            replacementRange,
            reason: pendingMarkedTextReplacementRange == nil ? "current-selection" : "marked-continuation"
        )
#endif
        return replacementRange
    }

    @objc override func composedString(_ sender: Any!) -> Any! {
        currentMarkedText
    }

    @objc override func originalString(_ sender: Any!) -> NSAttributedString! {
        NSAttributedString(string: currentMarkedText)
    }

    private static func makeEngine() -> ColeSebeolEngine {
        do {
            return try ColeSebeolEngine()
        } catch {
            fatalError("Failed to initialize ColeSebeolEngine: \(error)")
        }
    }

#if DEBUG
    private static func bundleInfoValue(for key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else {
            return "unknown"
        }
        return value
    }

    private func logRuntimeIdentity(stage: String) {
        logger.notice(
            "controller runtime stage=\(stage, privacy: .public) appVersion=\(Self.bundleInfoValue(for: "CFBundleShortVersionString"), privacy: .public) build=\(Self.bundleInfoValue(for: "CFBundleVersion"), privacy: .public) pid=\(ProcessInfo.processInfo.processIdentifier, privacy: .public) bundle=\(Bundle.main.bundleURL.path, privacy: .public) replacementPolicy=\(Self.replacementRangePolicyID, privacy: .public)"
        )
    }
#endif

    private func handleKeyInput(
        text: String?,
        keyCode: UInt16,
        modifiers flags: NSEvent.ModifierFlags,
        client sender: Any?
    ) -> Bool {
        shiftTap.cancelForKeyInput()
#if DEBUG
        traceClientRanges("before-key keyCode=\(keyCode)", sender: sender)
        logInconsistentMarkedRangeIfNeeded(client: sender)
#endif

        let modifiers = flags.subtracting(.capsLock)

        if keyCode == KeyCode.escape {
            return selectInputMode(.roman, client: sender, handled: false)
        }

        if modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.option) {
            flushBeforeForwarding(to: sender)
            return false
        }

        switch keyCode {
        case KeyCode.space:
            return handleWhitespace(" ", client: sender)
        case KeyCode.deleteBackward:
            guard inputMode == .hangul else {
                flushBeforeForwarding(to: sender)
                return false
            }
            return process(.backspace, client: sender)
        case KeyCode.deleteForward:
            flushBeforeForwarding(to: sender)
            return false
        case KeyCode.returnKey, KeyCode.tab:
            flushBeforeForwarding(to: sender)
            return false
        default:
            break
        }

        if KeyCode.forwardedNonPrintableKeys.contains(keyCode) {
            flushBeforeForwarding(to: sender)
            return false
        }

        if let representativeKey = RepresentativeKeyMap.scalar(
            forKeyCode: keyCode,
            shifted: modifiers.contains(.shift)
        ) {
            return handleRepresentativeKey(representativeKey, client: sender)
        }

        guard let text else {
            return false
        }
        return handleFallbackText(text, client: sender)
    }

    private func selectInputMode(
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

        inputMode = mode
#if DEBUG
        logger.debug("input mode selected \(mode.description, privacy: .public)")
#endif
        return handled
    }

    private func selectRomanModeForInputSourceSelection(client sender: Any?) {
        shiftTap = ShiftTapDetector()
        _ = selectInputMode(.roman, client: sender)
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

    private func process(_ input: ColeSebeolInput, client sender: Any?) -> Bool {
        let output = hangulEngine.process(input)
        guard apply(output, to: sender) else {
            return false
        }
        return output.forwardedActions.isEmpty
    }

    private func flushBeforeForwarding(to sender: Any?) {
        guard hasMarkedText else {
            return
        }
        _ = apply(hangulEngine.process(.flush), to: sender)
    }

    private func commitRomanText(_ text: String, client sender: Any?) -> Bool {
        flushBeforeForwarding(to: sender)
        return commitText(text, client: sender)
    }

    private func commitText(_ text: String, client sender: Any?) -> Bool {
        guard let client = textClient(from: sender) else {
            logger.error("missing IMKTextInput client")
            return false
        }

        let replacementRange = replacementRange(for: client)
#if DEBUG
        traceClientRanges(
            "before-insert committedLength=\(text.utf16.count) replacement=\(NSStringFromRange(replacementRange))",
            client: client
        )
#endif
        client.insertText(text, replacementRange: replacementRange)
        currentMarkedText = ""
        hasMarkedText = false
#if DEBUG
        traceClientRanges("after-insert committedLength=\(text.utf16.count)", client: client)
#endif
        return true
    }

    private func apply(_ output: ColeSebeolOutput, to sender: Any?) -> Bool {
        guard let client = textClient(from: sender) else {
            logger.error("missing IMKTextInput client")
            return false
        }

        if !output.committedText.isEmpty {
            let replacementRange = replacementRange(for: client)
#if DEBUG
            traceClientRanges(
                "before-commit committedLength=\(output.committedText.utf16.count) replacement=\(NSStringFromRange(replacementRange))",
                client: client
            )
#endif
            client.insertText(output.committedText, replacementRange: replacementRange)
            currentMarkedText = ""
            hasMarkedText = false
#if DEBUG
            traceClientRanges("after-commit committedLength=\(output.committedText.utf16.count)", client: client)
#endif
            if !output.markedText.isEmpty {
                pendingMarkedTextReplacementRange = markedTextContinuationRange(
                    afterReplacing: replacementRange,
                    withCommittedText: output.committedText,
                    client: client
                )
            }
        }

        if !output.markedText.isEmpty {
            currentMarkedText = output.markedText
            hasMarkedText = true
#if DEBUG
            traceClientRanges("before-update-composition markedLength=\(output.markedText.utf16.count)", client: client)
#endif
            updateComposition()
#if DEBUG
            traceClientRanges("after-update-composition markedLength=\(output.markedText.utf16.count)", client: client)
#endif
        } else if hasMarkedText {
            currentMarkedText = ""
            hasMarkedText = false
#if DEBUG
            traceClientRanges("before-clear-composition", client: client)
#endif
            updateComposition()
#if DEBUG
            traceClientRanges("after-clear-composition", client: client)
#endif
        }

        return true
    }

    private func textClient(from sender: Any?) -> IMKTextInput? {
        if let client = sender as? IMKTextInput {
            return client
        }
        return client()
    }

    private func markedTextContinuationRange(
        afterReplacing replacementRange: NSRange,
        withCommittedText committedText: String,
        client: IMKTextInput
    ) -> NSRange? {
        let committedLength = committedText.utf16.count

        if replacementRange.location != NSNotFound {
            let (location, overflow) = replacementRange.location.addingReportingOverflow(committedLength)
            if !overflow {
                return NSRange(location: location, length: 0)
            }
        }

        let selectedRange = client.selectedRange()
        guard selectedRange.location != NSNotFound, selectedRange.length == 0 else {
            return nil
        }
        return selectedRange
    }

#if DEBUG
    private func logInconsistentMarkedRangeIfNeeded(client sender: Any?) {
        guard isClientRangeTracingEnabled,
              hasMarkedText,
              let client = textClient(from: sender) else {
            return
        }

        let selectedRange = client.selectedRange()
        let markedRange = client.markedRange()
        guard selectedRange.location != NSNotFound else {
            return
        }

        if markedRange.location != NSNotFound,
           markedRange.length > 0,
           isSelectionRange(selectedRange, consistentWithMarkedRange: markedRange) {
            return
        }

        logger.debug(
            "inconsistent ranges selected=\(NSStringFromRange(selectedRange), privacy: .public) marked=\(NSStringFromRange(markedRange), privacy: .public)"
        )
    }

    private var isClientRangeTracingEnabled: Bool {
        Self.debugFlagIsEnabled(
            environmentKey: "HISLE_TRACE_CLIENT_RANGES",
            defaultsKey: "traceClientRanges"
        )
    }

    private static func debugFlagIsEnabled(environmentKey: String, defaultsKey: String) -> Bool {
        if let environmentValue = ProcessInfo.processInfo.environment[environmentKey] {
            let normalizedValue = environmentValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ["1", "true", "yes", "on"].contains(normalizedValue)
        }

        if UserDefaults.standard.bool(forKey: defaultsKey) {
            return true
        }

        return UserDefaults(suiteName: HisleInputModeState.suiteName)?.bool(forKey: defaultsKey) == true
    }

    private func traceClientRanges(_ stage: String, sender: Any?) {
        guard isClientRangeTracingEnabled else {
            return
        }

        guard let client = textClient(from: sender) else {
            logger.debug("client-range stage=\(stage, privacy: .public) missing-client")
            return
        }

        traceClientRanges(stage, client: client)
    }

    private func traceClientRanges(_ stage: String, client: IMKTextInput) {
        guard isClientRangeTracingEnabled else {
            return
        }

        let selectedRange = client.selectedRange()
        let markedRange = client.markedRange()
        logger.debug(
            "client-range stage=\(stage, privacy: .public) selected=\(NSStringFromRange(selectedRange), privacy: .public) marked=\(NSStringFromRange(markedRange), privacy: .public) hasMarkedText=\(self.hasMarkedText, privacy: .public) currentMarkedLength=\(self.currentMarkedText.utf16.count, privacy: .public)"
        )
    }

    private func traceReplacementRange(
        _ replacementRange: NSRange,
        selectedRange: NSRange,
        markedRange: NSRange,
        reason: String
    ) {
        guard isClientRangeTracingEnabled else {
            return
        }

        logger.debug(
            "client-range replacement=\(NSStringFromRange(replacementRange), privacy: .public) reason=\(reason, privacy: .public) selected=\(NSStringFromRange(selectedRange), privacy: .public) marked=\(NSStringFromRange(markedRange), privacy: .public) hasMarkedText=\(self.hasMarkedText, privacy: .public) currentMarkedLength=\(self.currentMarkedText.utf16.count, privacy: .public)"
        )
    }

    private func traceUpdateCompositionReplacementRange(_ replacementRange: NSRange, reason: String) {
        guard isClientRangeTracingEnabled else {
            return
        }

        guard let client = textClient(from: nil) else {
            logger.debug(
                "client-range update-composition replacement=\(NSStringFromRange(replacementRange), privacy: .public) reason=\(reason, privacy: .public) missing-client"
            )
            return
        }

        logger.debug(
            "client-range update-composition replacement=\(NSStringFromRange(replacementRange), privacy: .public) reason=\(reason, privacy: .public) selected=\(NSStringFromRange(client.selectedRange()), privacy: .public) marked=\(NSStringFromRange(client.markedRange()), privacy: .public) hasMarkedText=\(self.hasMarkedText, privacy: .public) currentMarkedLength=\(self.currentMarkedText.utf16.count, privacy: .public)"
        )
    }
#endif

    private func isSelectionRange(_ selectedRange: NSRange, consistentWithMarkedRange markedRange: NSRange) -> Bool {
        if selectedRange.location == markedRange.location {
            return true
        }

        guard let selectedEnd = upperBound(of: selectedRange),
              let markedEnd = upperBound(of: markedRange)
        else {
            return false
        }

        if selectedEnd == markedEnd {
            return true
        }

        let (terminalLocation, overflow) = markedEnd.addingReportingOverflow(1)
        return !overflow && selectedRange.location == terminalLocation
    }

    private func upperBound(of range: NSRange) -> Int? {
        guard range.location != NSNotFound else {
            return nil
        }

        let (upperBound, overflow) = range.location.addingReportingOverflow(range.length)
        return overflow ? nil : upperBound
    }

    private func replacementRange(for client: IMKTextInput) -> NSRange {
        let markedRange = client.markedRange()

        if hasMarkedText, markedRange.location != NSNotFound, markedRange.length > 0 {
#if DEBUG
            traceReplacementRange(
                markedRange,
                selectedRange: client.selectedRange(),
                markedRange: markedRange,
                reason: "marked"
            )
#endif
            return markedRange
        }

        let replacementRange = currentSelectionReplacementRange
#if DEBUG
        traceReplacementRange(
            replacementRange,
            selectedRange: client.selectedRange(),
            markedRange: markedRange,
            reason: "current-selection"
        )
#endif
        return replacementRange
    }
}

private enum HisleInputMode: CustomStringConvertible {
    case hangul
    case roman

    var description: String {
        switch self {
        case .hangul:
            return "hangul"
        case .roman:
            return "roman"
        }
    }
}

private enum HisleInputModeState {
    static let suiteName = "hooreique.inputmethod.hisle"
    static let key = "inputMode"

    static func write(_ mode: HisleInputMode) {
        let domain = suiteName as CFString
        CFPreferencesSetAppValue(key as CFString, mode.description as CFString, domain)
        CFPreferencesAppSynchronize(domain)
    }
}

private enum KeyCode {
    static let returnKey: UInt16 = 36
    static let tab: UInt16 = 48
    static let space: UInt16 = 49
    static let deleteBackward: UInt16 = 51
    static let escape: UInt16 = 53
    static let leftShift: UInt16 = 56
    static let rightShift: UInt16 = 60
    static let deleteForward: UInt16 = 117

    static let f1: UInt16 = 122
    static let f2: UInt16 = 120
    static let f3: UInt16 = 99
    static let f4: UInt16 = 118
    static let f5: UInt16 = 96
    static let f6: UInt16 = 97
    static let f7: UInt16 = 98
    static let f8: UInt16 = 100
    static let f9: UInt16 = 101
    static let f10: UInt16 = 109
    static let f11: UInt16 = 103
    static let f12: UInt16 = 111
    static let home: UInt16 = 115
    static let end: UInt16 = 119
    static let pageUp: UInt16 = 116
    static let pageDown: UInt16 = 121
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126

    static let forwardedNonPrintableKeys: Set<UInt16> = [
        f1, f2, f3, f4, f5, f6, f7, f8, f9, f10, f11, f12,
        home, end, pageUp, pageDown,
        leftArrow, rightArrow, downArrow, upArrow,
    ]
}

private struct ShiftTapDetector {
    private var pendingShift: PhysicalShift?
    private var pressedShifts = Set<PhysicalShift>()
    private var isCanceled = false

    mutating func handleFlagsChanged(
        keyCode: UInt16,
        modifiers flags: NSEvent.ModifierFlags
    ) -> HisleInputMode? {
        let meaningfulModifiers = flags.subtracting(.capsLock)
        let shift = PhysicalShift(keyCode: keyCode)

        guard let shift else {
            cancelIfGestureIsActive(resetWhenModifiersAreReleased: meaningfulModifiers.isEmpty)
            return nil
        }

        if isShiftKeyDown(shift, modifiers: meaningfulModifiers) {
            handleShiftDown(shift)
            return nil
        }

        return handleShiftUp(shift, remainingModifiers: meaningfulModifiers)
    }

    mutating func cancelForKeyInput() {
        guard pendingShift != nil else {
            return
        }
        isCanceled = true
    }

    private mutating func isShiftKeyDown(
        _ shift: PhysicalShift,
        modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        if pressedShifts.contains(shift) {
            pressedShifts.remove(shift)
            return false
        }

        guard modifiers.contains(.shift) else {
            return false
        }

        pressedShifts.insert(shift)
        return true
    }

    private mutating func handleShiftDown(_ shift: PhysicalShift) {
        guard let current = pendingShift else {
            pendingShift = shift
            isCanceled = false
            return
        }

        if current != shift {
            isCanceled = true
        }
    }

    private mutating func handleShiftUp(
        _ shift: PhysicalShift,
        remainingModifiers: NSEvent.ModifierFlags
    ) -> HisleInputMode? {
        defer {
            if !remainingModifiers.contains(.shift) {
                reset()
            }
        }

        guard pendingShift == shift, !isCanceled, remainingModifiers.isEmpty else {
            return nil
        }

        return shift.selectedInputMode
    }

    private mutating func cancelIfGestureIsActive(resetWhenModifiersAreReleased shouldReset: Bool) {
        guard pendingShift != nil else {
            return
        }

        isCanceled = true

        if shouldReset {
            reset()
        }
    }

    private mutating func reset() {
        pendingShift = nil
        pressedShifts.removeAll()
        isCanceled = false
    }
}

private enum PhysicalShift: Hashable {
    case left
    case right

    init?(keyCode: UInt16) {
        switch keyCode {
        case KeyCode.leftShift:
            self = .left
        case KeyCode.rightShift:
            self = .right
        default:
            return nil
        }
    }

    var selectedInputMode: HisleInputMode {
        switch self {
        case .left:
            return .roman
        case .right:
            return .hangul
        }
    }
}

private enum RepresentativeKeyMap {
    private static let unshifted: [UInt16: Unicode.Scalar] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
        8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
        16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 37: "l",
        38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "n", 46: "m", 47: ".", 50: "`",
    ]

    private static let shifted: [UInt16: Unicode.Scalar] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "!", 19: "@", 20: "#", 21: "$", 22: "^",
        23: "%", 24: "+", 25: "(", 26: "&", 27: "_", 28: "*", 29: ")",
        30: "}", 31: "O", 32: "U", 33: "{", 34: "I", 35: "P", 37: "L",
        38: "J", 39: "\"", 40: "K", 41: ":", 42: "|", 43: "<", 44: "?",
        45: "N", 46: "M", 47: ">", 50: "~",
    ]

    static func scalar(forKeyCode keyCode: UInt16, shifted isShifted: Bool) -> Unicode.Scalar? {
        if isShifted {
            return shifted[keyCode]
        }
        return unshifted[keyCode]
    }
}
