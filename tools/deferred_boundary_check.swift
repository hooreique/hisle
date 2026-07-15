// swiftlint:disable:next blanket_disable_command
// swiftlint:disable file_length type_body_length

import Foundation

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

private final class ManualScheduler {
    private var operations: [() -> Void] = []

    var count: Int {
        operations.count
    }

    func enqueue(_ operation: @escaping () -> Void) {
        operations.append(operation)
    }

    func runNext() throws {
        guard !operations.isEmpty else {
            throw CheckFailure(description: "manual scheduler has no pending operation")
        }
        operations.removeFirst()()
    }

    func runAll() {
        while !operations.isEmpty {
            operations.removeFirst()()
        }
    }
}

private enum HostPhase: String, CaseIterable {
    case compositionInsert
    case boundaryInsert
    case aggregateCommitInsert
    case aggregateMarkedUpdate
}

private enum RangeQueryPhase: String, CaseIterable {
    case compositionSelection
    case aggregateSelection
    case aggregateMarkedRange
}

private final class FakeClient {
    let name: String
    private(set) var text: String
    private(set) var selectedRange: NSRange
    private(set) var markedRange = NSRange(location: NSNotFound, length: 0)
    private(set) var phaseCounts: [HostPhase: Int] = [:]
    private(set) var rangeQueryCounts: [RangeQueryPhase: Int] = [:]
    var phaseObserver: ((HostPhase) -> Void)?
    var rangeQueryObserver: ((RangeQueryPhase) -> Void)?

    init(name: String, text: String = "", selection: NSRange = NSRange(location: 0, length: 0)) {
        self.name = name
        self.text = text
        selectedRange = selection
    }

    var caret: Int {
        selectedRange.location
    }

    func insert(_ insertedText: String, replacementRange requestedRange: NSRange, phase: HostPhase) {
        replace(insertedText, replacementRange: requestedRange)
        record(phase)
    }

    func insertForTransition(_ insertedText: String, replacementRange requestedRange: NSRange) {
        replace(insertedText, replacementRange: requestedRange)
    }

    private func replace(_ insertedText: String, replacementRange requestedRange: NSRange) {
        let replacementRange = resolvedRange(requestedRange)
        let mutableText = NSMutableString(string: text)
        mutableText.replaceCharacters(in: replacementRange, with: insertedText)
        text = mutableText as String
        selectedRange = NSRange(
            location: replacementRange.location + insertedText.utf16.count,
            length: 0
        )
        markedRange = NSRange(location: NSNotFound, length: 0)
    }

    func updateMarkedText(_ markedText: String, replacementRange requestedRange: NSRange) {
        let replacementRange = resolvedRange(requestedRange)
        markedRange = NSRange(location: replacementRange.location, length: markedText.utf16.count)
        record(.aggregateMarkedUpdate)
    }

    func deleteBackward() {
        guard selectedRange.location > 0 else {
            return
        }
        let mutableText = NSMutableString(string: text)
        mutableText.deleteCharacters(in: NSRange(location: selectedRange.location - 1, length: 1))
        text = mutableText as String
        selectedRange = NSRange(location: selectedRange.location - 1, length: 0)
    }

    func count(_ phase: HostPhase) -> Int {
        phaseCounts[phase, default: 0]
    }

    func querySelectedRange(_ phase: RangeQueryPhase) -> NSRange {
        recordRangeQuery(phase)
        return selectedRange
    }

    func queryMarkedRange() -> NSRange {
        recordRangeQuery(.aggregateMarkedRange)
        return markedRange
    }

    func count(_ phase: RangeQueryPhase) -> Int {
        rangeQueryCounts[phase, default: 0]
    }

    private func resolvedRange(_ requestedRange: NSRange) -> NSRange {
        requestedRange.location == NSNotFound ? selectedRange : requestedRange
    }

    private func record(_ phase: HostPhase) {
        phaseCounts[phase, default: 0] += 1
        phaseObserver?(phase)
    }

    private func recordRangeQuery(_ phase: RangeQueryPhase) {
        rangeQueryCounts[phase, default: 0] += 1
        rangeQueryObserver?(phase)
    }
}

private struct FakeEngine {
    var markedText = ""

    mutating func process(_ scalar: Unicode.Scalar) -> DeferredBoundaryFallbackStep? {
        if scalar.properties.isWhitespace && !CharacterSet.controlCharacters.contains(scalar) {
            let boundaryText = String(scalar)
            let committedText = markedText + boundaryText
            markedText = ""
            return DeferredBoundaryFallbackStep(
                handled: true,
                committedText: committedText,
                markedText: "",
                hasForwardedActions: false,
                boundaryText: boundaryText
            )
        }

        guard (Unicode.Scalar("a").value ... Unicode.Scalar("z").value).contains(scalar.value) else {
            return nil
        }
        markedText.append(String(scalar))
        return DeferredBoundaryFallbackStep(
            handled: true,
            committedText: "",
            markedText: markedText,
            hasForwardedActions: false,
            boundaryText: nil
        )
    }
}

private final class DeferredBoundaryHarness {
    let scheduler = ManualScheduler()
    let client: FakeClient
    private(set) var markedText = ""
    private(set) var rejectedBoundaryCount = 0

    private var engine = FakeEngine()
    private var tracker = MarkedTextRangeTracker()
    private var context = DeferredBoundaryContext()
    private var inFlightCommit: DeferredBoundaryCommitIntent?
    private var inFlightAggregate: DeferredBoundaryAggregateApplyIntent?
    private var inFlightContinuation: DeferredBoundaryContinuation?
    private var pendingMarkedReplacement: PendingMarkedTextReplacement?

    private lazy var queue = DeferredBoundaryQueue { [scheduler] operation in
        scheduler.enqueue(operation)
    }

    init(name: String = "A", text: String = "", caret: Int = 0) {
        client = FakeClient(
            name: name,
            text: text,
            selection: NSRange(location: caret, length: 0)
        )
        context.activate()
    }

    var hasPendingBoundary: Bool {
        queue.hasPendingBoundary
    }

    var isAtFixedPoint: Bool {
        !queue.hasPendingBoundary &&
            inFlightCommit == nil &&
            inFlightAggregate == nil &&
            inFlightContinuation == nil &&
            pendingMarkedReplacement == nil
    }

    var ownedMarkedRange: NSRange? {
        tracker.markedRange
    }

    var ownedInsertionRange: NSRange? {
        tracker.insertionRange
    }

    var hasPendingMarkedReplacement: Bool {
        pendingMarkedReplacement != nil
    }

    func setMarkedText(_ text: String, ownedRange: NSRange? = nil) {
        markedText = text
        engine.markedText = text
        if let ownedRange {
            tracker.recordMarkedTextUpdate(
                replacementRange: ownedRange,
                markedLength: ownedRange.length,
                clientMarkedRange: ownedRange
            )
        }
    }

    @discardableResult
    func fallbackEvent(_ text: String) -> Bool {
        drain()
        context.advanceEditingContext()
        return processFallbackScalars(Array(text.unicodeScalars), preserveOwnedInsertionRange: false)
    }

    func backspaceEvent() {
        drain()
        client.deleteBackward()
        context.advanceEditingContext()
    }

    func navigationEvent() {
        drain()
        context.advanceEditingContext()
    }

    func modeEvent() {
        drain()
        commitMarkedTextForTransition()
        context.advanceEditingContext()
    }

    func focusEvent() {
        drain()
        commitMarkedTextForTransition()
        context.advanceEditingContext()
    }

    func deactivate() {
        drain()
        commitMarkedTextForTransition()
        context.deactivate()
    }

    func startOwnedAggregate(
        committedText: String,
        finalMarkedText: String,
        replacementRange: NSRange
    ) {
        let intent = DeferredBoundaryAggregateApplyIntent(
            committedText: committedText,
            markedText: finalMarkedText,
            client: client,
            contextGeneration: context.generation,
            commitReplacementRange: replacementRange,
            preCommitSelectedRange: client.selectedRange,
            preserveOwnedInsertionRange: false,
            wasMarkedTextActive: true
        )
        inFlightAggregate = intent
        engine.markedText = finalMarkedText
        _ = finishAggregate(intent)
    }

    func drain() {
        while true {
            if finishCommit() {
                continue
            }
            if finishAggregate() {
                continue
            }
            if drainContinuation() {
                continue
            }
            if let work = queue.takePending() {
                deliver(work)
                continue
            }
            return
        }
    }

    private func processFallbackScalars(
        _ scalars: [Unicode.Scalar],
        preserveOwnedInsertionRange: Bool
    ) -> Bool {
        if !preserveOwnedInsertionRange {
            drain()
        }
        let generation = context.generation
        let initialMarkedText = markedText
        let replacementRange = initialMarkedText.isEmpty
            ? NSRange(location: NSNotFound, length: 0)
            : tracker.markedRange ?? NSRange(location: client.caret, length: 0)
        let preCommitSelection = client.selectedRange
        var nextEngine = engine
        let batch = DeferredBoundaryFallbackProcessor.process(
            scalars,
            deferFirstBoundary: !initialMarkedText.isEmpty
        ) { scalar in
            nextEngine.process(scalar)
        }
        guard batch.didProcessInput,
              generation == context.generation,
              initialMarkedText == markedText else {
            return false
        }

        engine = nextEngine
        if let boundaryText = batch.boundaryText {
            beginBoundary(
                batch,
                boundaryText: boundaryText,
                generation: generation,
                replacementRange: replacementRange,
                preCommitSelection: preCommitSelection
            )
        } else {
            beginAggregate(
                batch,
                generation: generation,
                replacementRange: replacementRange,
                preCommitSelection: preCommitSelection,
                preserveOwnedInsertionRange: preserveOwnedInsertionRange
            )
        }
        return batch.handled
    }

    private func beginBoundary(
        _ batch: DeferredBoundaryFallbackBatch,
        boundaryText: String,
        generation: UInt64,
        replacementRange: NSRange,
        preCommitSelection: NSRange
    ) {
        let compositionText = String(batch.committedText.dropLast(boundaryText.count))
        let intent = DeferredBoundaryCommitIntent(
            compositionText: compositionText,
            boundaryText: boundaryText,
            continuationScalars: batch.continuationScalars,
            client: client,
            contextGeneration: generation,
            replacementRange: replacementRange,
            preCommitSelectedRange: preCommitSelection
        )
        inFlightCommit = intent
        client.insert(compositionText, replacementRange: replacementRange, phase: .compositionInsert)
        if inFlightCommit === intent, intent.phase == .textInFlight {
            if MarkedTextRangePolicy.shouldUsePostCommitSelectedRange(
                preCommitSelectedRange: intent.preCommitSelectedRange,
                replacementRange: intent.replacementRange
            ) {
                intent.phase = .selectionReady
                _ = finishCommit(intent)
            } else {
                completeCommit(intent, owner: client, postSelection: nil, clearIfMissing: false)
            }
        }
    }

    private func beginAggregate(
        _ batch: DeferredBoundaryFallbackBatch,
        generation: UInt64,
        replacementRange: NSRange,
        preCommitSelection: NSRange,
        preserveOwnedInsertionRange: Bool
    ) {
        let intent = DeferredBoundaryAggregateApplyIntent(
            committedText: batch.committedText,
            markedText: batch.markedText,
            client: client,
            contextGeneration: generation,
            commitReplacementRange: replacementRange,
            preCommitSelectedRange: preCommitSelection,
            preserveOwnedInsertionRange: preserveOwnedInsertionRange
        )
        inFlightAggregate = intent
        _ = finishAggregate(intent)
    }

    @discardableResult
    private func finishCommit(_ expected: DeferredBoundaryCommitIntent? = nil) -> Bool {
        guard let intent = inFlightCommit,
              expected == nil || intent === expected,
              intent.contextGeneration == context.generation,
              let owner = intent.client as? FakeClient else {
            return false
        }

        switch intent.phase {
        case .textInFlight, .selectionQueryInFlight:
            completeCommit(intent, owner: owner, postSelection: nil, clearIfMissing: true)
        case .selectionReady:
            intent.phase = .selectionQueryInFlight
            let postSelection = owner.querySelectedRange(.compositionSelection)
            guard inFlightCommit === intent,
                  intent.phase == .selectionQueryInFlight else {
                return true
            }
            completeCommit(intent, owner: owner, postSelection: postSelection, clearIfMissing: false)
        }
        return true
    }

    private func completeCommit(
        _ intent: DeferredBoundaryCommitIntent,
        owner: FakeClient,
        postSelection: NSRange?,
        clearIfMissing: Bool
    ) {
        inFlightCommit = nil
        tracker.recordCommittedText(
            replacementRange: intent.replacementRange,
            preCommitSelectedRange: intent.preCommitSelectedRange,
            committedLength: intent.compositionText.utf16.count,
            wasMarkedTextActive: true,
            postCommitSelectedRange: postSelection,
            clearOwnershipIfPostSelectionMissing: clearIfMissing
        )
        markedText = ""
        queue.schedule(
            text: intent.boundaryText,
            client: owner,
            contextGeneration: intent.contextGeneration,
            expectedInsertionRange: tracker.insertionRange,
            continuationScalars: intent.continuationScalars
        ) { [self] ticket in
            resolve(ticket)
        }
    }

    @discardableResult
    private func finishAggregate(_ expected: DeferredBoundaryAggregateApplyIntent? = nil) -> Bool {
        guard let intent = inFlightAggregate,
              expected == nil || intent === expected,
              intent.contextGeneration == context.generation,
              let owner = intent.client as? FakeClient else {
            return false
        }

        switch intent.phase {
        case .ready:
            beginAggregateCommit(intent, owner: owner)
        case .committedTextInFlight, .committedSelectionQueryInFlight:
            completeAggregateCommit(intent, owner: owner, postSelection: nil, clearIfMissing: true)
        case .committedSelectionReady:
            intent.phase = .committedSelectionQueryInFlight
            let postSelection = owner.querySelectedRange(.aggregateSelection)
            guard inFlightAggregate === intent,
                  intent.phase == .committedSelectionQueryInFlight else {
                return true
            }
            completeAggregateCommit(intent, owner: owner, postSelection: postSelection, clearIfMissing: false)
        case .markedTextInFlight, .markedRangeQueryInFlight:
            completeAggregateMarked(intent, clientMarkedRange: nil, clearIfMissing: true)
        case .markedRangeReady:
            intent.phase = .markedRangeQueryInFlight
            let clientMarkedRange = owner.queryMarkedRange()
            guard inFlightAggregate === intent,
                  intent.phase == .markedRangeQueryInFlight else {
                return true
            }
            completeAggregateMarked(intent, clientMarkedRange: clientMarkedRange, clearIfMissing: false)
        }
        return true
    }

    private func beginAggregateCommit(
        _ intent: DeferredBoundaryAggregateApplyIntent,
        owner: FakeClient
    ) {
        guard !intent.committedText.isEmpty else {
            prepareAggregateMarked(intent, owner: owner)
            return
        }
        intent.phase = .committedTextInFlight
        owner.insert(
            intent.committedText,
            replacementRange: intent.commitReplacementRange,
            phase: .aggregateCommitInsert
        )
        guard inFlightAggregate === intent,
              intent.phase == .committedTextInFlight else {
            return
        }
        if intent.wasMarkedTextActive,
           MarkedTextRangePolicy.shouldUsePostCommitSelectedRange(
               preCommitSelectedRange: intent.preCommitSelectedRange,
               replacementRange: intent.commitReplacementRange
           ) {
            intent.phase = .committedSelectionReady
            _ = finishAggregate(intent)
        } else {
            completeAggregateCommit(intent, owner: owner, postSelection: nil, clearIfMissing: false)
        }
    }

    private func completeAggregateCommit(
        _ intent: DeferredBoundaryAggregateApplyIntent,
        owner: FakeClient,
        postSelection: NSRange?,
        clearIfMissing: Bool
    ) {
        tracker.recordCommittedText(
            replacementRange: intent.commitReplacementRange,
            preCommitSelectedRange: intent.preCommitSelectedRange,
            committedLength: intent.committedText.utf16.count,
            wasMarkedTextActive: intent.wasMarkedTextActive,
            postCommitSelectedRange: postSelection,
            clearOwnershipIfPostSelectionMissing: clearIfMissing
        )
        markedText = ""
        intent.phase = .ready
        prepareAggregateMarked(intent, owner: owner)
    }

    private func prepareAggregateMarked(
        _ intent: DeferredBoundaryAggregateApplyIntent,
        owner: FakeClient
    ) {
        guard inFlightAggregate === intent else {
            return
        }
        guard !intent.markedText.isEmpty else {
            inFlightAggregate = nil
            return
        }
        pendingMarkedReplacement = tracker.replacementForMarkedTextUpdate(
            wasMarkedTextActive: !markedText.isEmpty
        )
        let (replacementRange, _) = MarkedTextRangePolicy.updateCompositionReplacementDecision(
            pendingMarkedTextReplacement: pendingMarkedReplacement
        )
        intent.markedReplacementRange = replacementRange
        markedText = intent.markedText
        intent.phase = .markedTextInFlight
        owner.updateMarkedText(intent.markedText, replacementRange: replacementRange)
        guard inFlightAggregate === intent,
              intent.phase == .markedTextInFlight else {
            return
        }
        intent.phase = .markedRangeReady
        _ = finishAggregate(intent)
    }

    private func completeAggregateMarked(
        _ intent: DeferredBoundaryAggregateApplyIntent,
        clientMarkedRange: NSRange?,
        clearIfMissing: Bool
    ) {
        DeferredAggregateMarkedCompletion.apply(
            tracker: &tracker,
            pendingReplacement: &pendingMarkedReplacement,
            update: DeferredBoundaryAggregateMarkedUpdate(
                replacementRange: intent.markedReplacementRange,
                markedLength: intent.markedText.utf16.count,
                clientMarkedRange: clientMarkedRange,
                clearOwnershipIfClientRangeMissing: clearIfMissing
            )
        )
        inFlightAggregate = nil
    }

    private func resolve(_ ticket: DeferredBoundaryTicket) {
        guard context.isActive,
              let work = queue.takeScheduled(
                  ticket: ticket,
                  contextGeneration: context.generation
              ) else {
            return
        }
        deliver(work)
    }

    private func deliver(_ work: DeferredBoundaryWork) {
        guard let owner = work.client as? FakeClient,
              DeferredBoundaryDeliveryPolicy.canDeliver(
                  work,
                  context: context,
                  hasMarkedText: !markedText.isEmpty,
                  ownedMarkedRange: tracker.markedRange,
                  ownedInsertionRange: tracker.insertionRange
              ) else {
            rejectedBoundaryCount += 1
            return
        }
        tracker.recordBoundaryTextAfterActiveComposition(committedLength: work.text.utf16.count)
        if !work.continuationScalars.isEmpty {
            inFlightContinuation = DeferredBoundaryContinuation(
                scalars: work.continuationScalars,
                client: owner,
                contextGeneration: work.contextGeneration
            )
        }
        owner.insert(
            work.text,
            replacementRange: NSRange(location: NSNotFound, length: 0),
            phase: .boundaryInsert
        )
        guard context.isActive,
              context.generation == work.contextGeneration else {
            return
        }
        if !work.continuationScalars.isEmpty {
            _ = drainContinuation()
        }
    }

    private func drainContinuation() -> Bool {
        guard let continuation = inFlightContinuation,
              context.isActive,
              continuation.contextGeneration == context.generation,
              continuation.client === client else {
            return false
        }
        inFlightContinuation = nil
        _ = processFallbackScalars(
            continuation.scalars,
            preserveOwnedInsertionRange: true
        )
        return true
    }

    private func commitMarkedTextForTransition() {
        guard !markedText.isEmpty else {
            return
        }
        let replacementRange = client.markedRange.location == NSNotFound
            ? NSRange(location: NSNotFound, length: 0)
            : NSRange(location: client.markedRange.location, length: 0)
        client.insertForTransition(markedText, replacementRange: replacementRange)
        markedText = ""
        engine.markedText = ""
        tracker.clear()
        pendingMarkedReplacement = nil
    }
}

@main
private enum DeferredBoundaryCheck {
    static func main() throws {
        try checkDefaultProfileSynchronousPolicy()
        try checkFallbackReducer()
        try checkMiddleBackspace()
        try checkZeroDelayNavigationAndLifecycleTransitions()
        try checkStaleTicketKeepsExactClient()
        try checkHostPhaseReentryIsExactlyOnce()
        try checkRangeQueryReentryAndOwnership()

        print(
            "Deferred boundary check passed default synchronous/scalar policy and busy " +
                "batch, ordering, lifecycle, ticket, and reentry scenarios."
        )
    }

    // swiftlint:disable:next function_body_length
    private static func checkDefaultProfileSynchronousPolicy() throws {
        let idlePlan = DefaultHostApplyPlan.make(
            committedText: "",
            markedText: "",
            wasMarkedTextActive: false
        )
        try expectEqual(idlePlan.committedText, nil, "default idle commit")
        try expectEqual(idlePlan.markedTextAction, DefaultMarkedTextAction.none, "default idle mark")

        let clearPlan = DefaultHostApplyPlan.make(
            committedText: "",
            markedText: "",
            wasMarkedTextActive: true
        )
        try expectEqual(clearPlan.committedText, nil, "default clear commit")
        try expectEqual(clearPlan.markedTextAction, DefaultMarkedTextAction.clear, "default clear mark")

        let boundaryPlan = DefaultHostApplyPlan.make(
            committedText: "가 ",
            markedText: "",
            wasMarkedTextActive: true
        )
        try expectEqual(boundaryPlan.committedText, "가 ", "default synchronous boundary text")
        try expectEqual(
            boundaryPlan.needsMarkedTextContinuation,
            false,
            "default boundary continuation"
        )
        try expectEqual(
            boundaryPlan.markedTextAction,
            DefaultMarkedTextAction.none,
            "default boundary marked action"
        )

        let markedOnlyPlan = DefaultHostApplyPlan.make(
            committedText: "",
            markedText: "가",
            wasMarkedTextActive: false
        )
        try expectEqual(markedOnlyPlan.committedText, nil, "default marked-only commit")
        try expectEqual(
            markedOnlyPlan.markedTextAction,
            DefaultMarkedTextAction.update("가"),
            "default marked-only update"
        )

        let continuationPlan = DefaultHostApplyPlan.make(
            committedText: "가",
            markedText: "나",
            wasMarkedTextActive: true
        )
        try expectEqual(continuationPlan.committedText, "가", "default continuation commit")
        try expectEqual(
            continuationPlan.needsMarkedTextContinuation,
            true,
            "default pending continuation"
        )
        try expectEqual(
            continuationPlan.markedTextAction,
            DefaultMarkedTextAction.update("나"),
            "default continuation marked update"
        )

        var visitedScalars: [String] = []
        let handled = DefaultHostFallbackProcessor.process(Array("a 😀b".unicodeScalars)) { scalar in
            visitedScalars.append(String(scalar))
            return scalar == "😀" ? nil : scalar == "b"
        }
        try expectEqual(visitedScalars, ["a", " ", "😀", "b"], "default scalar fallback order")
        try expectEqual(handled, true, "default scalar fallback handled aggregate")
    }

    private static func checkFallbackReducer() throws {
        var activeEngine = FakeEngine(markedText: "가")
        let activeBatch = DeferredBoundaryFallbackProcessor.process(
            Array(" a b".unicodeScalars),
            deferFirstBoundary: true
        ) { scalar in
            activeEngine.process(scalar)
        }
        try expectEqual(activeBatch.committedText, "가 ", "active first-boundary commit")
        try expectEqual(activeBatch.markedText, "", "active first-boundary mark")
        try expectEqual(activeBatch.boundaryText, " ", "active first-boundary split")
        try expectEqual(
            String(String.UnicodeScalarView(activeBatch.continuationScalars)),
            "a b",
            "active first-boundary continuation"
        )

        var inactiveEngine = FakeEngine()
        let inactiveBatch = DeferredBoundaryFallbackProcessor.process(
            Array("a b".unicodeScalars),
            deferFirstBoundary: false
        ) { scalar in
            inactiveEngine.process(scalar)
        }
        try expectEqual(inactiveBatch.committedText, "a ", "inactive full-fold commit")
        try expectEqual(inactiveBatch.markedText, "b", "inactive full-fold final mark")
        try expectEqual(inactiveBatch.boundaryText, nil, "inactive full fold must not defer")
        try expectEqual(inactiveBatch.continuationScalars.isEmpty, true, "inactive full-fold continuation")

        var repeatedEngine = FakeEngine()
        let repeatedBatch = DeferredBoundaryFallbackProcessor.process(
            Array("a \u{2003}b".unicodeScalars),
            deferFirstBoundary: false
        ) { scalar in
            repeatedEngine.process(scalar)
        }
        try expectEqual(repeatedBatch.committedText, "a \u{2003}", "repeated whitespace order")
        try expectEqual(repeatedBatch.markedText, "b", "repeated whitespace suffix")
        try expectEqual(repeatedBatch.boundaryText, nil, "inactive repeated whitespace ticket count")

        var unsupportedEngine = FakeEngine()
        let unsupportedBatch = DeferredBoundaryFallbackProcessor.process(
            Array("\u{0008}😀".unicodeScalars),
            deferFirstBoundary: true
        ) { scalar in
            unsupportedEngine.process(scalar)
        }
        try expectEqual(unsupportedBatch.didProcessInput, false, "unsupported/control input")
        try expectEqual(unsupportedBatch.handled, false, "unsupported/control handled aggregate")
        try expectEqual(unsupportedBatch.committedText, "", "unsupported/control commit")
        try expectEqual(unsupportedBatch.markedText, "", "unsupported/control mark")
    }

    private static func checkMiddleBackspace() throws {
        let harness = DeferredBoundaryHarness(text: "foo bar", caret: 3)
        harness.setMarkedText("안녕")
        try expectEqual(harness.fallbackEvent(" "), true, "middle whitespace handled")
        harness.backspaceEvent()

        try expectEqual(harness.client.text, "foo안녕 bar", "middle Backspace exact text")
        try expectEqual(harness.client.count(.compositionInsert), 1, "middle composition exact once")
        try expectEqual(harness.client.count(.boundaryInsert), 1, "middle boundary exact once")
        harness.scheduler.runAll()
        try expectEqual(harness.client.text, "foo안녕 bar", "middle stale callback no-op")
    }

    private static func checkZeroDelayNavigationAndLifecycleTransitions() throws {
        let zeroDelay = DeferredBoundaryHarness()
        zeroDelay.setMarkedText("가")
        zeroDelay.fallbackEvent(" ")
        zeroDelay.fallbackEvent("x")
        try expectEqual(zeroDelay.client.text, "가 ", "zero-delay boundary before next input")
        try expectEqual(zeroDelay.markedText, "x", "zero-delay newer mark")
        zeroDelay.scheduler.runAll()
        try expectEqual(zeroDelay.markedText, "x", "stale callback preserves newer mark")

        let navigation = DeferredBoundaryHarness()
        navigation.setMarkedText("가")
        navigation.fallbackEvent(" ")
        navigation.navigationEvent()
        try expectEqual(navigation.client.text, "가 ", "navigation drains boundary first")
        try expectEqual(navigation.client.count(.boundaryInsert), 1, "navigation boundary exact once")

        let mode = DeferredBoundaryHarness()
        mode.setMarkedText("가")
        mode.fallbackEvent(" x")
        mode.modeEvent()
        try expectEqual(mode.client.text, "가 x", "mode transition preserves continuation")

        let focus = DeferredBoundaryHarness()
        focus.setMarkedText("가")
        focus.fallbackEvent(" x")
        focus.focusEvent()
        try expectEqual(focus.client.text, "가 x", "focus transition preserves continuation")

        let deactivation = DeferredBoundaryHarness()
        deactivation.setMarkedText("가")
        deactivation.fallbackEvent(" x")
        deactivation.deactivate()
        try expectEqual(deactivation.client.text, "가 x", "deactivation preserves continuation")
        try expectEqual(deactivation.isAtFixedPoint, true, "deactivation fixed point")
        deactivation.scheduler.runAll()
        try expectEqual(deactivation.client.text, "가 x", "deactivation stale callback")
    }

    private static func checkStaleTicketKeepsExactClient() throws {
        let scheduler = ManualScheduler()
        let queue = DeferredBoundaryQueue { operation in
            scheduler.enqueue(operation)
        }
        let clientA = FakeClient(name: "A")
        let clientB = FakeClient(name: "B")
        let generation: UInt64 = 7
        var deliveredClients: [String] = []

        queue.schedule(
            text: " ",
            client: clientA,
            contextGeneration: generation,
            expectedInsertionRange: nil
        ) { ticket in
            if let work = queue.takeScheduled(ticket: ticket, contextGeneration: generation),
               let owner = work.client as? FakeClient {
                deliveredClients.append(owner.name)
            }
        }
        let drained = queue.takePending()
        try expectEqual(drained?.client === clientA, true, "drained ticket exact client")

        queue.schedule(
            text: "\u{2003}",
            client: clientB,
            contextGeneration: generation,
            expectedInsertionRange: nil
        ) { ticket in
            if let work = queue.takeScheduled(ticket: ticket, contextGeneration: generation),
               let owner = work.client as? FakeClient {
                deliveredClients.append(owner.name)
            }
        }
        try scheduler.runNext()
        try expectEqual(deliveredClients, [], "stale ticket cannot consume newer client work")
        try expectEqual(queue.hasPendingBoundary, true, "newer client work remains pending")
        try scheduler.runNext()
        try expectEqual(deliveredClients, ["B"], "new ticket keeps exact client")
    }

    private static func checkHostPhaseReentryIsExactlyOnce() throws {
        for targetPhase in HostPhase.allCases {
            let harness = DeferredBoundaryHarness()
            harness.setMarkedText("가")
            var didReenter = false
            harness.client.phaseObserver = { [harness] phase in
                guard phase == targetPhase, !didReenter else {
                    return
                }
                didReenter = true
                harness.deactivate()
            }

            try expectEqual(harness.fallbackEvent(" a b"), true, "\(targetPhase.rawValue) handled")
            harness.scheduler.runAll()

            try expectEqual(didReenter, true, "\(targetPhase.rawValue) reentry reached")
            try expectEqual(harness.client.text, "가 a b", "\(targetPhase.rawValue) committed text")
            try expectEqual(harness.markedText, "", "\(targetPhase.rawValue) final mark committed")
            try expectEqual(harness.isAtFixedPoint, true, "\(targetPhase.rawValue) fixed point")
            for phase in HostPhase.allCases {
                try expectEqual(
                    harness.client.count(phase),
                    1,
                    "\(targetPhase.rawValue) keeps \(phase.rawValue) exact once"
                )
            }
        }
    }

    private static func checkRangeQueryReentryAndOwnership() throws {
        try checkCommitRangeQueryReentry()
        try checkMarkedRangeQueryReentry()
    }

    private static func checkCommitRangeQueryReentry() throws {
        let composition = DeferredBoundaryHarness(text: "abcdefgh", caret: 5)
        composition.setMarkedText("가", ownedRange: NSRange(location: 1, length: 1))
        composition.client.rangeQueryObserver = { [composition] phase in
            guard phase == .compositionSelection else {
                return
            }
            composition.drain()
        }
        composition.fallbackEvent(" ")
        try expectEqual(
            composition.client.count(.compositionSelection),
            1,
            "composition selection query reentry"
        )
        try expectEqual(composition.ownedMarkedRange, nil, "composition query clears marked ownership")
        try expectEqual(composition.ownedInsertionRange, nil, "composition query clears insertion ownership")

        let aggregateCommit = DeferredBoundaryHarness(text: "abcdefgh", caret: 5)
        aggregateCommit.client.rangeQueryObserver = { [aggregateCommit] phase in
            guard phase == .aggregateSelection else {
                return
            }
            aggregateCommit.drain()
        }
        aggregateCommit.startOwnedAggregate(
            committedText: "x",
            finalMarkedText: "",
            replacementRange: NSRange(location: 1, length: 1)
        )
        try expectEqual(
            aggregateCommit.client.count(.aggregateSelection),
            1,
            "aggregate selection query reentry"
        )
        try expectEqual(aggregateCommit.ownedInsertionRange, nil, "aggregate query clears ownership")
    }

    private static func checkMarkedRangeQueryReentry() throws {
        let aggregateMarked = DeferredBoundaryHarness()
        aggregateMarked.client.rangeQueryObserver = { [aggregateMarked] phase in
            guard phase == .aggregateMarkedRange else {
                return
            }
            aggregateMarked.drain()
        }
        aggregateMarked.fallbackEvent("b")
        try expectEqual(
            aggregateMarked.client.count(.aggregateMarkedRange),
            1,
            "aggregate marked-range query reentry"
        )
        try expectEqual(aggregateMarked.ownedMarkedRange, nil, "marked query clears marked ownership")
        try expectEqual(aggregateMarked.ownedInsertionRange, nil, "marked query clears insertion ownership")
        try expectEqual(aggregateMarked.hasPendingMarkedReplacement, false, "marked query clears pending range")

        let inactive = DeferredBoundaryHarness()
        inactive.fallbackEvent("a b")
        try expectEqual(inactive.client.count(.aggregateSelection), 0, "inactive plain commit skips selection query")
        try expectEqual(inactive.client.count(.aggregateMarkedRange), 1, "inactive final mark adopts host range")
        try expectEqual(inactive.ownedMarkedRange != nil, true, "inactive final mark ownership")
        try expectEqual(inactive.hasPendingMarkedReplacement, false, "inactive final mark clears pending range")
    }

    private static func expectEqual<Value: Equatable>(
        _ actual: Value,
        _ expected: Value,
        _ description: String
    ) throws {
        guard actual == expected else {
            throw CheckFailure(
                description: "\(description): expected \(String(describing: expected)), " +
                    "got \(String(describing: actual))"
            )
        }
    }
}
