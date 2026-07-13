import Cocoa
import HisleCore
import InputMethodKit
import os

@objc(HisleInputController)
final class InputController: IMKInputController {
    let logger = Logger(subsystem: "hooreique.inputmethod.hisle", category: "InputController")
    private static var sharedInputMode = HisleInputMode.roman {
        didSet {
            HisleInputModeState.write(sharedInputMode)
        }
    }
#if DEBUG
    static let buildProfile = "debug"
#else
    static let buildProfile = "release"
#endif
    var hangulEngine = InputController.makeEngine()
    var markedText = MarkedTextState()
    var markedTextRangeTracker = MarkedTextRangeTracker()
    var deferredBoundaryQueue = DeferredBoundaryQueue()
    var deferredBoundaryContext = DeferredBoundaryContext()
    var inFlightDeferredBoundaryCommit: DeferredBoundaryCommitIntent?
    var inFlightDeferredBoundaryAggregateApply: DeferredBoundaryAggregateApplyIntent?
    var inFlightDeferredBoundaryContinuation: DeferredBoundaryContinuation?
    var pendingMarkedTextReplacement: PendingMarkedTextReplacement?
    var lastUpdateCompositionReplacementRange: NSRange?
    var shiftTap = ShiftTapDetector()
    let keyClassifier = InputKeyClassifier()

    var inputMode: HisleInputMode {
        get { Self.sharedInputMode }
        set { Self.sharedInputMode = newValue }
    }

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        HisleInputModeState.write(inputMode)
        logRuntimeIdentity(stage: "initialized")
#if DEBUG
        logger.debug("controller client=\(String(describing: inputClient), privacy: .public)")
#endif
    }

    override func activateServer(_ sender: Any!) {
        drainDeferredBoundaryText()
        deferredBoundaryContext.activate()
        KeyboardLayoutOverride.installColemak(for: sender ?? client(), logSuccess: true)
        logRuntimeIdentity(stage: "activated")
        super.activateServer(sender)
    }

    override func deactivateServer(_ sender: Any!) {
        drainDeferredBoundaryText()
        flushBeforeForwarding(to: sender)
        markedTextRangeTracker.clear()
        deferredBoundaryContext.deactivate()
        shiftTap = ShiftTapDetector()
        super.deactivateServer(sender)
    }

    override func inputControllerWillClose() {
        drainDeferredBoundaryText()
        flushBeforeForwarding(to: client())
        markedTextRangeTracker.clear()
        deferredBoundaryContext.deactivate()
        super.inputControllerWillClose()
    }

    override func setValue(_ value: Any!, forTag tag: Int, client sender: Any!) {
        drainDeferredBoundaryText()
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
        drainDeferredBoundaryText()
        flushBeforeForwarding(to: sender)
        markedTextRangeTracker.clear()
        deferredBoundaryContext.advanceEditingContext()
        return false
    }

    override func handle(_ event: NSEvent, client sender: Any) -> Bool {
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

    @objc override func commitComposition(_ sender: Any!) {
        drainDeferredBoundaryText()
        _ = apply(hangulEngine.process(.flush), to: sender)
        markedTextRangeTracker.clear()
        deferredBoundaryContext.advanceEditingContext()
    }

    override func cancelComposition() {
        drainDeferredBoundaryText()
        _ = apply(hangulEngine.process(.clear), to: client())
        markedTextRangeTracker.clear()
        deferredBoundaryContext.advanceEditingContext()
    }

    @objc override func updateComposition() {
        lastUpdateCompositionReplacementRange = nil
        defer {
            pendingMarkedTextReplacement = nil
        }
        super.updateComposition()
    }

    @objc override func replacementRange() -> NSRange {
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

    @objc override func composedString(_ sender: Any!) -> Any! {
        markedText.string
    }

    @objc override func originalString(_ sender: Any!) -> NSAttributedString! {
        NSAttributedString(string: markedText.string)
    }
}
