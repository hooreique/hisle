import Foundation

struct DeferredBoundaryFallbackStep {
    let handled: Bool
    let committedText: String
    let markedText: String
    let hasForwardedActions: Bool
    let boundaryText: String?
}

struct DeferredBoundaryFallbackBatch {
    let didProcessInput: Bool
    let handled: Bool
    let committedText: String
    let markedText: String
    let boundaryText: String?
    let continuationScalars: [Unicode.Scalar]
}

enum DeferredBoundaryFallbackProcessor {
    static func process(
        _ scalars: [Unicode.Scalar],
        deferFirstBoundary: Bool,
        scalarHandler: (Unicode.Scalar) -> DeferredBoundaryFallbackStep?
    ) -> DeferredBoundaryFallbackBatch {
        var didProcessInput = false
        var handled = false
        var committedText = ""
        var markedText = ""
        var hasForwardedActions = false

        for (index, scalar) in scalars.enumerated() {
            guard let step = scalarHandler(scalar) else {
                continue
            }
            didProcessInput = true
            handled = step.handled || handled
            committedText.append(step.committedText)
            markedText = step.markedText
            hasForwardedActions = step.hasForwardedActions || hasForwardedActions

            if deferFirstBoundary,
               !hasForwardedActions,
               let boundaryText = step.boundaryText,
               !committedText.isEmpty,
               markedText.isEmpty,
               committedText.hasSuffix(boundaryText) {
                return DeferredBoundaryFallbackBatch(
                    didProcessInput: true,
                    handled: handled,
                    committedText: committedText,
                    markedText: markedText,
                    boundaryText: boundaryText,
                    continuationScalars: Array(scalars.dropFirst(index + 1))
                )
            }
        }

        return DeferredBoundaryFallbackBatch(
            didProcessInput: didProcessInput,
            handled: handled,
            committedText: committedText,
            markedText: markedText,
            boundaryText: nil,
            continuationScalars: []
        )
    }
}

struct DeferredBoundaryTicket: Equatable {
    fileprivate let value: UInt64
}

struct DeferredBoundaryContinuation {
    let scalars: [Unicode.Scalar]
    let client: AnyObject
    let contextGeneration: UInt64
}

enum DeferredBoundaryAggregateApplyPhase {
    case ready
    case committedTextInFlight
    case committedSelectionReady
    case committedSelectionQueryInFlight
    case markedTextInFlight
    case markedRangeReady
    case markedRangeQueryInFlight
}

enum DeferredBoundaryCommitPhase {
    case textInFlight
    case selectionReady
    case selectionQueryInFlight
}

final class DeferredBoundaryAggregateApplyIntent {
    let committedText: String
    let markedText: String
    let client: AnyObject
    let contextGeneration: UInt64
    let commitReplacementRange: NSRange
    let preCommitSelectedRange: NSRange
    let wasMarkedTextActive: Bool
    var markedReplacementRange: NSRange?
    var phase = DeferredBoundaryAggregateApplyPhase.ready

    init(
        committedText: String,
        markedText: String,
        client: AnyObject,
        contextGeneration: UInt64,
        commitReplacementRange: NSRange,
        preCommitSelectedRange: NSRange,
        preserveOwnedInsertionRange: Bool,
        wasMarkedTextActive: Bool? = nil
    ) {
        self.committedText = committedText
        self.markedText = markedText
        self.client = client
        self.contextGeneration = contextGeneration
        self.commitReplacementRange = commitReplacementRange
        self.preCommitSelectedRange = preCommitSelectedRange
        self.wasMarkedTextActive = wasMarkedTextActive ?? preserveOwnedInsertionRange
    }
}

final class DeferredBoundaryCommitIntent {
    let compositionText: String
    let boundaryText: String
    let continuationScalars: [Unicode.Scalar]
    let client: AnyObject
    let contextGeneration: UInt64
    let replacementRange: NSRange
    let preCommitSelectedRange: NSRange
    var phase = DeferredBoundaryCommitPhase.textInFlight

    init(
        compositionText: String,
        boundaryText: String,
        continuationScalars: [Unicode.Scalar],
        client: AnyObject,
        contextGeneration: UInt64,
        replacementRange: NSRange,
        preCommitSelectedRange: NSRange
    ) {
        self.compositionText = compositionText
        self.boundaryText = boundaryText
        self.continuationScalars = continuationScalars
        self.client = client
        self.contextGeneration = contextGeneration
        self.replacementRange = replacementRange
        self.preCommitSelectedRange = preCommitSelectedRange
    }
}

struct DeferredBoundaryContext {
    private(set) var generation: UInt64 = 0
    private(set) var isActive = false

    mutating func activate() {
        advanceGeneration()
        isActive = true
    }

    mutating func deactivate() {
        advanceGeneration()
        isActive = false
    }

    mutating func advanceEditingContext() {
        advanceGeneration()
    }

    private mutating func advanceGeneration() {
        generation &+= 1
        if generation == 0 {
            generation = 1
        }
    }
}

struct DeferredBoundaryWork {
    let text: String
    let client: AnyObject
    let contextGeneration: UInt64
    let expectedInsertionRange: NSRange?
    let continuationScalars: [Unicode.Scalar]
}

enum DeferredBoundaryDeliveryPolicy {
    static func canDeliver(
        _ work: DeferredBoundaryWork,
        context: DeferredBoundaryContext,
        hasMarkedText: Bool,
        ownedMarkedRange: NSRange?,
        ownedInsertionRange: NSRange?
    ) -> Bool {
        context.isActive &&
            work.contextGeneration == context.generation &&
            !hasMarkedText &&
            ownedMarkedRange == nil &&
            ownedInsertionRange == work.expectedInsertionRange
    }
}

final class DeferredBoundaryQueue {
    typealias Scheduler = (@escaping () -> Void) -> Void

    private struct PendingBoundary {
        let ticket: DeferredBoundaryTicket
        let text: String
        let client: AnyObject
        let contextGeneration: UInt64
        let expectedInsertionRange: NSRange?
        var continuationScalars: [Unicode.Scalar]
    }

    private let scheduler: Scheduler
    private var nextTicketValue: UInt64 = 0
    private var pendingBoundaries: [PendingBoundary] = []

    init(scheduler: @escaping Scheduler = { operation in
        DispatchQueue.main.async(execute: operation)
    }) {
        self.scheduler = scheduler
    }

    var hasPendingBoundary: Bool {
        !pendingBoundaries.isEmpty
    }

    @discardableResult
    func schedule(
        text: String,
        client: AnyObject,
        contextGeneration: UInt64,
        expectedInsertionRange: NSRange?,
        continuationScalars: [Unicode.Scalar] = [],
        resolver: @escaping (DeferredBoundaryTicket) -> Void
    ) -> DeferredBoundaryTicket {
        nextTicketValue &+= 1
        if nextTicketValue == 0 {
            nextTicketValue = 1
        }
        let ticket = DeferredBoundaryTicket(value: nextTicketValue)
        pendingBoundaries.append(PendingBoundary(
            ticket: ticket,
            text: text,
            client: client,
            contextGeneration: contextGeneration,
            expectedInsertionRange: expectedInsertionRange,
            continuationScalars: continuationScalars
        ))
        scheduler {
            resolver(ticket)
        }
        return ticket
    }

    func takeScheduled(
        ticket: DeferredBoundaryTicket,
        contextGeneration: UInt64
    ) -> DeferredBoundaryWork? {
        guard pendingBoundaries.first?.ticket == ticket,
              pendingBoundaries.first?.contextGeneration == contextGeneration else {
            return nil
        }
        return takePendingBoundary()
    }

    func takePending() -> DeferredBoundaryWork? {
        return takePendingBoundary()
    }

    private func takePendingBoundary() -> DeferredBoundaryWork? {
        guard !pendingBoundaries.isEmpty else {
            return nil
        }
        let pendingBoundary = pendingBoundaries.removeFirst()
        return DeferredBoundaryWork(
            text: pendingBoundary.text,
            client: pendingBoundary.client,
            contextGeneration: pendingBoundary.contextGeneration,
            expectedInsertionRange: pendingBoundary.expectedInsertionRange,
            continuationScalars: pendingBoundary.continuationScalars
        )
    }
}
