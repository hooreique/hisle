import Cocoa
import InputMethodKit
import os

@objc(HisleInputController)
final class InputController: IMKInputController, HostBackendContext {
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
    private lazy var hostBackend = InputMethodRuntime.shared.hostBackendFactory.makeDispatcher(
        for: clientBundleIdentifier,
        context: self
    )
    private(set) var clientBundleIdentifier: String?

    var inputMode: HisleInputMode {
        get { Self.sharedInputMode }
        set { Self.sharedInputMode = newValue }
    }

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        let bundleIdentifier = (inputClient as? IMKTextInput)?.bundleIdentifier()
        super.init(server: server, delegate: delegate, client: inputClient)

        clientBundleIdentifier = bundleIdentifier
        _ = hostBackend

        HisleInputModeState.write(inputMode)
        logRuntimeIdentity(stage: "initialized")
#if DEBUG
        logger.debug("controller client=\(String(describing: inputClient), privacy: .public)")
#endif
    }

    override func activateServer(_ sender: Any!) {
        hostBackend.activateServer(sender)
        logRuntimeIdentity(stage: "activated")
        super.activateServer(sender)
    }

    override func deactivateServer(_ sender: Any!) {
        hostBackend.deactivateServer(sender)
        super.deactivateServer(sender)
    }

    override func inputControllerWillClose() {
        hostBackend.inputControllerWillClose()
        super.inputControllerWillClose()
    }

    override func setValue(_ value: Any!, forTag tag: Int, client sender: Any!) {
        hostBackend.setValue(value, forTag: tag, client: sender)
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
        hostBackend.mouseDown(client: sender)
    }

    override func handle(_ event: NSEvent, client sender: Any) -> Bool {
        hostBackend.handle(event, client: sender)
    }

    @objc override func commitComposition(_ sender: Any!) {
        hostBackend.commitComposition(sender)
    }

    override func cancelComposition() {
        hostBackend.cancelComposition()
    }

    @objc override func updateComposition() {
        hostBackend.updateComposition()
    }

    @objc override func replacementRange() -> NSRange {
        hostBackend.replacementRange()
    }

    @objc override func composedString(_ sender: Any!) -> Any! {
        hostBackend.markedText.string
    }

    @objc override func originalString(_ sender: Any!) -> NSAttributedString! {
        NSAttributedString(string: hostBackend.markedText.string)
    }

    func hostClient() -> IMKTextInput? {
        client()
    }

    func performHostCompositionUpdate() {
        super.updateComposition()
    }

    var hostProfile: HostProfile {
        hostBackend.profile
    }

    var replacementPolicyID: String {
        hostBackend.replacementPolicyID
    }
}
