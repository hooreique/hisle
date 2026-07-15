import Cocoa
import HisleCore
import InputMethodKit
import os

protocol HostBackend: AnyObject {
    var profile: HostProfile { get }
    var replacementPolicyID: String { get }
    var markedText: MarkedTextState { get }

    func activateServer(_ sender: Any?)
    func deactivateServer(_ sender: Any?)
    func inputControllerWillClose()
    func setValue(_ value: Any?, forTag tag: Int, client sender: Any?)
    func mouseDown(client sender: Any) -> Bool
    func handle(_ event: NSEvent, client sender: Any) -> Bool
    func commitComposition(_ sender: Any?)
    func cancelComposition()
    func updateComposition()
    func replacementRange() -> NSRange
}

class HostBackendState {
    unowned let inputController: InputController
    var hangulEngine = InputController.makeEngine()
    var markedText = MarkedTextState()
    var shiftTap = ShiftTapDetector()
    let keyClassifier = InputKeyClassifier()

    init(inputController: InputController) {
        self.inputController = inputController
    }

    var logger: Logger {
        inputController.logger
    }

    var inputMode: HisleInputMode {
        get { inputController.inputMode }
        set { inputController.inputMode = newValue }
    }

    func textClient(from sender: Any?) -> IMKTextInput? {
        if let client = sender as? IMKTextInput {
            return client
        }
        return inputController.hostClient()
    }

    func performHostCompositionUpdate() {
        inputController.performHostCompositionUpdate()
    }
}

final class DefaultHostBackend: HostBackendState, HostBackend {
    let profile = HostProfile.defaultProfile
    let replacementPolicyID = DefaultMarkedTextRangePolicy.policyID
    var pendingMarkedTextReplacementRange: NSRange?
}

final class BusyHostBackend: HostBackendState, HostBackend {
    let profile = HostProfile.busy
    let replacementPolicyID = MarkedTextRangePolicy.policyID
    var markedTextRangeTracker = MarkedTextRangeTracker()
    var deferredBoundaryQueue = DeferredBoundaryQueue()
    var deferredBoundaryContext = DeferredBoundaryContext()
    var inFlightDeferredBoundaryCommit: DeferredBoundaryCommitIntent?
    var inFlightDeferredBoundaryAggregateApply: DeferredBoundaryAggregateApplyIntent?
    var inFlightDeferredBoundaryContinuation: DeferredBoundaryContinuation?
    var pendingMarkedTextReplacement: PendingMarkedTextReplacement?
    var lastUpdateCompositionReplacementRange: NSRange?
}
