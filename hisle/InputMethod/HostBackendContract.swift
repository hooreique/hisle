import Cocoa
import InputMethodKit
import os

protocol HostBackendContext: AnyObject {
    var logger: Logger { get }
    var inputMode: HisleInputMode { get set }

    func hostClient() -> IMKTextInput?
    func performHostCompositionUpdate()
}

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

final class HostBackendDispatcher {
    private let backend: any HostBackend

    init(backend: any HostBackend) {
        self.backend = backend
    }

    var profile: HostProfile {
        backend.profile
    }

    var replacementPolicyID: String {
        backend.replacementPolicyID
    }

    var markedText: MarkedTextState {
        backend.markedText
    }

    func activateServer(_ sender: Any?) {
        backend.activateServer(sender)
    }

    func deactivateServer(_ sender: Any?) {
        backend.deactivateServer(sender)
    }

    func inputControllerWillClose() {
        backend.inputControllerWillClose()
    }

    func setValue(_ value: Any?, forTag tag: Int, client sender: Any?) {
        backend.setValue(value, forTag: tag, client: sender)
    }

    func mouseDown(client sender: Any) -> Bool {
        backend.mouseDown(client: sender)
    }

    func handle(_ event: NSEvent, client sender: Any) -> Bool {
        backend.handle(event, client: sender)
    }

    func commitComposition(_ sender: Any?) {
        backend.commitComposition(sender)
    }

    func cancelComposition() {
        backend.cancelComposition()
    }

    func updateComposition() {
        backend.updateComposition()
    }

    func replacementRange() -> NSRange {
        backend.replacementRange()
    }
}

enum HostMarkedTextRangeCompatibility: Equatable {
    case hostReported
    case owned
}

enum HostBoundaryDeliveryCompatibility: Equatable {
    case synchronous
    case deferred
}

enum HostFallbackCompatibility: Equatable {
    case scalar
    case aggregate
}

enum HostBackendLifecycleEvent {
    case activate
    case deactivate
    case close
    case mouseDown
}

enum HostBackendLifecycleOperation: Equatable {
    case drainDeferredInput
    case activateEditingContext
    case flushComposition
    case clearOwnedRanges
    case deactivateEditingContext
    case advanceEditingContext
    case resetShiftTap
}

struct HostBackendLifecycleCompatibility: Equatable {
    let drainsDeferredInput: Bool
    let ownsEditingContext: Bool
    let flushesOnClose: Bool
    let handlesMouseEventsInEventCallback: Bool

    func operations(for event: HostBackendLifecycleEvent) -> [HostBackendLifecycleOperation] {
        switch event {
        case .activate:
            return compact([
                drainsDeferredInput ? .drainDeferredInput : nil,
                ownsEditingContext ? .activateEditingContext : nil
            ])
        case .deactivate:
            return compact([
                drainsDeferredInput ? .drainDeferredInput : nil,
                .flushComposition,
                ownsEditingContext ? .clearOwnedRanges : nil,
                ownsEditingContext ? .deactivateEditingContext : nil,
                .resetShiftTap
            ])
        case .close:
            guard flushesOnClose else {
                return []
            }
            return compact([
                drainsDeferredInput ? .drainDeferredInput : nil,
                .flushComposition,
                ownsEditingContext ? .clearOwnedRanges : nil,
                ownsEditingContext ? .deactivateEditingContext : nil
            ])
        case .mouseDown:
            return compact([
                drainsDeferredInput ? .drainDeferredInput : nil,
                .flushComposition,
                ownsEditingContext ? .clearOwnedRanges : nil,
                ownsEditingContext ? .advanceEditingContext : nil
            ])
        }
    }

    private func compact(
        _ operations: [HostBackendLifecycleOperation?]
    ) -> [HostBackendLifecycleOperation] {
        operations.compactMap { $0 }
    }
}

struct HostBackendCompatibility: Equatable {
    let profile: HostProfile
    let markedTextRanges: HostMarkedTextRangeCompatibility
    let boundaryDelivery: HostBoundaryDeliveryCompatibility
    let fallback: HostFallbackCompatibility
    let lifecycle: HostBackendLifecycleCompatibility

    static func configuration(for profile: HostProfile) -> HostBackendCompatibility {
        switch profile {
        case .defaultProfile:
            return HostBackendCompatibility(
                profile: .defaultProfile,
                markedTextRanges: .hostReported,
                boundaryDelivery: .synchronous,
                fallback: .scalar,
                lifecycle: HostBackendLifecycleCompatibility(
                    drainsDeferredInput: false,
                    ownsEditingContext: false,
                    flushesOnClose: false,
                    handlesMouseEventsInEventCallback: false
                )
            )
        case .busy:
            return HostBackendCompatibility(
                profile: .busy,
                markedTextRanges: .owned,
                boundaryDelivery: .deferred,
                fallback: .aggregate,
                lifecycle: HostBackendLifecycleCompatibility(
                    drainsDeferredInput: true,
                    ownsEditingContext: true,
                    flushesOnClose: true,
                    handlesMouseEventsInEventCallback: true
                )
            )
        }
    }
}

struct HostBackendFactory {
    typealias Builder = (HostBackendCompatibility, any HostBackendContext) -> any HostBackend

    private let busyAppsSnapshot: BusyAppsSnapshot
    private let builder: Builder

    init(busyAppsSnapshot: BusyAppsSnapshot, builder: @escaping Builder) {
        self.busyAppsSnapshot = busyAppsSnapshot
        self.builder = builder
    }

    func makeBackend(
        for bundleIdentifier: String?,
        context: any HostBackendContext
    ) -> any HostBackend {
        let profile = busyAppsSnapshot.profile(for: bundleIdentifier)
        return builder(.configuration(for: profile), context)
    }

    func makeDispatcher(
        for bundleIdentifier: String?,
        context: any HostBackendContext
    ) -> HostBackendDispatcher {
        HostBackendDispatcher(backend: makeBackend(for: bundleIdentifier, context: context))
    }
}
