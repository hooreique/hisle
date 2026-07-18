import Cocoa
import HisleCore
import InputMethodKit
import os

class HostBackendState {
    unowned let context: any HostBackendContext
    var hangulEngine = HostBackendState.makeEngine()
    var markedText = MarkedTextState()
    var shiftTap = ShiftTapDetector()
    let keyClassifier = InputKeyClassifier()

    init(context: any HostBackendContext) {
        self.context = context
    }

    var logger: Logger {
        context.logger
    }

    var inputMode: HisleInputMode {
        get { context.inputMode }
        set { context.inputMode = newValue }
    }

    func textClient(from sender: Any?) -> IMKTextInput? {
        if let client = sender as? IMKTextInput {
            return client
        }
        return context.hostClient()
    }

    func performHostCompositionUpdate() {
        context.performHostCompositionUpdate()
    }

    private static func makeEngine() -> ColeSebeolEngine {
        do {
            return try ColeSebeolEngine()
        } catch {
            fatalError("Failed to initialize ColeSebeolEngine: \(error)")
        }
    }
}

final class DefaultHostBackend: HostBackendState, HostBackendImplementation {
    let compatibility: HostBackendCompatibility
    let replacementPolicyID = DefaultMarkedTextRangePolicy.policyID
    var pendingMarkedTextReplacementRange: NSRange?

    init(compatibility: HostBackendCompatibility, context: any HostBackendContext) {
        self.compatibility = compatibility
        super.init(context: context)
    }

    var profile: HostProfile {
        compatibility.profile
    }
}

final class BusyHostBackend: HostBackendState, HostBackendImplementation {
    let compatibility: HostBackendCompatibility
    let replacementPolicyID = MarkedTextRangePolicy.policyID
    var markedTextRangeTracker = MarkedTextRangeTracker()
    var deferredBoundaryQueue = DeferredBoundaryQueue()
    var deferredBoundaryContext = DeferredBoundaryContext()
    var inFlightDeferredBoundaryCommit: DeferredBoundaryCommitIntent?
    var inFlightDeferredBoundaryAggregateApply: DeferredBoundaryAggregateApplyIntent?
    var inFlightDeferredBoundaryContinuation: DeferredBoundaryContinuation?
    var pendingMarkedTextReplacement: PendingMarkedTextReplacement?
    var lastUpdateCompositionReplacementRange: NSRange?

    init(compatibility: HostBackendCompatibility, context: any HostBackendContext) {
        self.compatibility = compatibility
        super.init(context: context)
    }

    var profile: HostProfile {
        compatibility.profile
    }
}

extension HostBackendFactory {
    init(busyAppsSnapshot: BusyAppsSnapshot) {
        self.init(busyAppsSnapshot: busyAppsSnapshot) { compatibility, context in
            switch (
                compatibility.markedTextRanges,
                compatibility.boundaryDelivery,
                compatibility.fallback
            ) {
            case (.hostReported, .synchronous, .scalar):
                return DefaultHostBackend(compatibility: compatibility, context: context)
            case (.owned, .deferred, .aggregate):
                return BusyHostBackend(compatibility: compatibility, context: context)
            default:
                fatalError("Unsupported host compatibility composition")
            }
        }
    }
}
