import Cocoa
import InputMethodKit
import os

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

private final class FakeHostContext: HostBackendContext {
    let logger = Logger(subsystem: "hooreique.inputmethod.hisle.check", category: "HostBackend")
    var inputMode = HisleInputMode.roman
    private(set) var compositionUpdateCount = 0

    func hostClient() -> IMKTextInput? {
        nil
    }

    func performHostCompositionUpdate() {
        compositionUpdateCount += 1
    }
}

private final class RecordingBackend: HostBackend {
    let profile: HostProfile
    let replacementPolicyID: String
    var markedText = MarkedTextState()
    private(set) var callbacks: [String] = []

    init(profile: HostProfile) {
        self.profile = profile
        replacementPolicyID = "recording-\(profile.rawValue)"
        markedText.replace(with: "recording-marked")
    }

    func activateServer(_ sender: Any?) {
        callbacks.append("activate:\(sender != nil)")
    }

    func deactivateServer(_ sender: Any?) {
        callbacks.append("deactivate:\(sender != nil)")
    }

    func inputControllerWillClose() {
        callbacks.append("close")
    }

    func setValue(_ value: Any?, forTag tag: Int, client sender: Any?) {
        callbacks.append("set-value:\(value != nil):\(tag):\(sender != nil)")
    }

    func mouseDown(client _: Any) -> Bool {
        callbacks.append("mouse-down")
        return false
    }

    func handle(_ event: NSEvent, client _: Any) -> Bool {
        callbacks.append("handle:\(event.keyCode)")
        return true
    }

    func commitComposition(_ sender: Any?) {
        callbacks.append("commit:\(sender != nil)")
    }

    func cancelComposition() {
        callbacks.append("cancel")
    }

    func updateComposition() {
        callbacks.append("update")
    }

    func replacementRange() -> NSRange {
        callbacks.append("replacement-range")
        return NSRange(location: 7, length: 3)
    }
}

@main
private enum HostBackendContractCheck {
    static func main() throws {
        var checkCount = 0
        try checkCompatibilityComposition()
        checkCount += 1
        try checkLifecycleOrder()
        checkCount += 1
        try checkFactorySelectionAndInjection()
        checkCount += 1
        try checkCallbackDelegation()
        checkCount += 1
        print("host backend contract check passed: \(checkCount) groups")
    }

    private static func checkCompatibilityComposition() throws {
        let defaultCompatibility = HostBackendCompatibility.configuration(for: .defaultProfile)
        let busyCompatibility = HostBackendCompatibility.configuration(for: .busy)

        try require(defaultCompatibility.markedTextRanges == .hostReported, "default range policy changed")
        try require(defaultCompatibility.boundaryDelivery == .synchronous, "default boundary policy changed")
        try require(defaultCompatibility.fallback == .scalar, "default fallback policy changed")
        try require(
            !defaultCompatibility.lifecycle.handlesMouseEventsInEventCallback,
            "default event-callback mouse policy changed"
        )
        try require(busyCompatibility.markedTextRanges == .owned, "busy range policy changed")
        try require(busyCompatibility.boundaryDelivery == .deferred, "busy boundary policy changed")
        try require(busyCompatibility.fallback == .aggregate, "busy fallback policy changed")
        try require(
            busyCompatibility.lifecycle.handlesMouseEventsInEventCallback,
            "busy event-callback mouse policy changed"
        )

        let independentlyComposed = HostBackendCompatibility(
            profile: .defaultProfile,
            markedTextRanges: .owned,
            boundaryDelivery: .synchronous,
            fallback: .aggregate,
            lifecycle: defaultCompatibility.lifecycle
        )
        try require(
            independentlyComposed.markedTextRanges == .owned &&
                independentlyComposed.boundaryDelivery == .synchronous &&
                independentlyComposed.fallback == .aggregate,
            "compatibility axes can no longer be composed independently"
        )
    }

    private static func checkLifecycleOrder() throws {
        let defaultLifecycle = HostBackendCompatibility.configuration(for: .defaultProfile).lifecycle
        let busyLifecycle = HostBackendCompatibility.configuration(for: .busy).lifecycle

        try require(defaultLifecycle.operations(for: .activate) == [], "default activation order changed")
        try require(
            defaultLifecycle.operations(for: .deactivate) == [.flushComposition, .resetShiftTap],
            "default deactivation order changed"
        )
        try require(defaultLifecycle.operations(for: .close) == [], "default close policy changed")
        try require(
            defaultLifecycle.operations(for: .mouseDown) == [.flushComposition],
            "default mouse boundary order changed"
        )

        try require(
            busyLifecycle.operations(for: .activate) == [.drainDeferredInput, .activateEditingContext],
            "busy activation order changed"
        )
        try require(
            busyLifecycle.operations(for: .deactivate) == [
                .drainDeferredInput,
                .flushComposition,
                .clearOwnedRanges,
                .deactivateEditingContext,
                .resetShiftTap
            ],
            "busy deactivation order changed"
        )
        try require(
            busyLifecycle.operations(for: .close) == [
                .drainDeferredInput,
                .flushComposition,
                .clearOwnedRanges,
                .deactivateEditingContext
            ],
            "busy close order changed"
        )
        try require(
            busyLifecycle.operations(for: .mouseDown) == [
                .drainDeferredInput,
                .flushComposition,
                .clearOwnedRanges,
                .advanceEditingContext
            ],
            "busy mouse boundary order changed"
        )
    }

    private static func checkFactorySelectionAndInjection() throws {
        let snapshot = BusyAppsSnapshot(
            configurationFileURL: URL(fileURLWithPath: "/tmp/hisle-contract-busy-apps.txt"),
            bundleIdentifiers: ["com.example.Busy"],
            loadErrorDescription: nil
        )
        let context = FakeHostContext()
        var builtCompatibilities: [HostBackendCompatibility] = []
        var builtBackends: [RecordingBackend] = []
        let factory = HostBackendFactory(busyAppsSnapshot: snapshot) { compatibility, _ in
            builtCompatibilities.append(compatibility)
            let backend = RecordingBackend(profile: compatibility.profile)
            builtBackends.append(backend)
            return backend
        }

        let busy = factory.makeBackend(for: "com.example.Busy", context: context)
        let differentCase = factory.makeBackend(for: "com.example.busy", context: context)
        let unidentified = factory.makeBackend(for: nil, context: context)

        try require(busy.profile == .busy, "factory did not select busy for an exact snapshot member")
        try require(differentCase.profile == .defaultProfile, "factory selection stopped being case-sensitive")
        try require(unidentified.profile == .defaultProfile, "factory did not default an unidentified client")
        try require(
            builtCompatibilities.map(\.profile) == [.busy, .defaultProfile, .defaultProfile],
            "factory did not pass the selected compatibility to its injected builder"
        )
        try require(builtBackends.count == 3, "factory did not create exactly one backend per request")
    }

    private static func checkCallbackDelegation() throws {
        let backend = RecordingBackend(profile: .busy)
        let dispatcher = HostBackendDispatcher(backend: backend)
        let sender = NSObject()
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        ) else {
            throw CheckFailure(description: "could not construct callback delegation event")
        }

        dispatcher.activateServer(sender)
        dispatcher.deactivateServer(sender)
        dispatcher.inputControllerWillClose()
        dispatcher.setValue("value", forTag: 42, client: sender)
        try require(!dispatcher.mouseDown(client: sender), "dispatcher changed mouseDown result")
        try require(dispatcher.handle(event, client: sender), "dispatcher changed handle result")
        dispatcher.commitComposition(sender)
        dispatcher.cancelComposition()
        dispatcher.updateComposition()
        let replacementRange = dispatcher.replacementRange()

        try require(dispatcher.profile == .busy, "dispatcher changed the backend profile")
        try require(
            dispatcher.replacementPolicyID == "recording-busy",
            "dispatcher changed the replacement policy identifier"
        )
        try require(dispatcher.markedText.string == "recording-marked", "dispatcher changed marked text")
        try require(replacementRange == NSRange(location: 7, length: 3), "dispatcher changed replacement range")
        try require(
            backend.callbacks == [
                "activate:true",
                "deactivate:true",
                "close",
                "set-value:true:42:true",
                "mouse-down",
                "handle:0",
                "commit:true",
                "cancel",
                "update",
                "replacement-range"
            ],
            "dispatcher callback order or argument forwarding changed: \(backend.callbacks)"
        )
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw CheckFailure(description: message)
        }
    }
}
