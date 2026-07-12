import Foundation
import InputMethodKit

enum MarkedTextRangeReason: String {
    case marked
    case currentSelection = "current-selection"
    case markedContinuation = "marked-continuation"
    case ownedInsertion = "owned-insertion"
    case ownedMarked = "owned-marked"
}

struct MarkedTextReplacementDecision {
    let replacementRange: NSRange
    let selectedRange: NSRange
    let markedRange: NSRange
    let reason: MarkedTextRangeReason
}

struct PendingMarkedTextReplacement {
    let range: NSRange
    let reason: MarkedTextRangeReason
}

enum MarkedTextRangePolicy {
    static let policyID = "current-selection-nsnotfound+split-boundary+" +
        "deferred-boundary+strict-selection-consistency+conditional-postcommit-caret"

    static var currentSelectionReplacementRange: NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    static func updateCompositionReplacementDecision(
        pendingMarkedTextReplacement: PendingMarkedTextReplacement?
    ) -> (NSRange, MarkedTextRangeReason) {
        guard let pendingMarkedTextReplacement else {
            return (currentSelectionReplacementRange, .currentSelection)
        }
        return (pendingMarkedTextReplacement.range, pendingMarkedTextReplacement.reason)
    }

    static func replacementDecision(
        hasMarkedText: Bool,
        ownedMarkedRange: NSRange?,
        ownedInsertionRange: NSRange?,
        client: IMKTextInput
    ) -> MarkedTextReplacementDecision {
        let selectedRange = client.selectedRange()
        let markedRange = client.markedRange()

        if hasMarkedText, markedRange.location != NSNotFound, markedRange.length > 0 {
            let replacementRange = ownedMarkedRange ?? markedRange
            return MarkedTextReplacementDecision(
                replacementRange: replacementRange,
                selectedRange: selectedRange,
                markedRange: markedRange,
                reason: ownedMarkedRange == nil ? .marked : .ownedMarked
            )
        }

        if hasMarkedText, let ownedMarkedRange {
            return MarkedTextReplacementDecision(
                replacementRange: ownedMarkedRange,
                selectedRange: selectedRange,
                markedRange: markedRange,
                reason: .ownedMarked
            )
        }

        return MarkedTextReplacementDecision(
            replacementRange: currentSelectionReplacementRange,
            selectedRange: selectedRange,
            markedRange: markedRange,
            reason: .currentSelection
        )
    }

    static func continuationReplacement(
        afterReplacing replacementRange: NSRange,
        withCommittedText committedText: String
    ) -> PendingMarkedTextReplacement? {
        let committedLength = committedText.utf16.count

        if replacementRange.location != NSNotFound {
            let (location, overflow) = replacementRange.location.addingReportingOverflow(committedLength)
            if !overflow {
                return PendingMarkedTextReplacement(
                    range: NSRange(location: location, length: 0),
                    reason: .markedContinuation
                )
            }
        }

        return nil
    }

    static func isSelectionRange(_ selectedRange: NSRange, consistentWithMarkedRange markedRange: NSRange) -> Bool {
        guard let selectedEnd = upperBound(of: selectedRange),
              let markedEnd = upperBound(of: markedRange)
        else {
            return false
        }

        if selectedRange.length > 0 {
            return selectedRange.location == markedRange.location && selectedEnd == markedEnd
        }

        if selectedRange.location == markedRange.location || selectedRange.location == markedEnd {
            return true
        }

        let (terminalLocation, overflow) = markedEnd.addingReportingOverflow(1)
        return !overflow && selectedRange.location == terminalLocation
    }

    private static func upperBound(of range: NSRange) -> Int? {
        guard range.location != NSNotFound,
              range.location >= 0,
              range.length >= 0
        else {
            return nil
        }

        let (upperBound, overflow) = range.location.addingReportingOverflow(range.length)
        return overflow ? nil : upperBound
    }
}

struct MarkedTextRangeTracker {
    private(set) var markedRange: NSRange?
    private(set) var insertionRange: NSRange?

    func replacementForMarkedTextUpdate(wasMarkedTextActive: Bool) -> PendingMarkedTextReplacement? {
        if wasMarkedTextActive, let markedRange {
            return PendingMarkedTextReplacement(range: markedRange, reason: .ownedMarked)
        }

        guard let insertionRange else {
            return nil
        }
        return PendingMarkedTextReplacement(range: insertionRange, reason: .ownedInsertion)
    }

    mutating func recordCommittedText(
        replacementRange: NSRange,
        preCommitSelectedRange: NSRange,
        committedLength: Int,
        wasMarkedTextActive: Bool,
        client: IMKTextInput
    ) {
        markedRange = nil

        guard committedLength > 0 else {
            return
        }

        guard wasMarkedTextActive else {
            insertionRange = nil
            return
        }

        if shouldTrustPostCommitSelectedRange(
            preCommitSelectedRange: preCommitSelectedRange,
            replacementRange: replacementRange
        ), let selectedRange = Self.validCollapsedRange(client.selectedRange()) {
            insertionRange = selectedRange
            return
        }

        guard let startLocation = startLocationForCommit(replacementRange: replacementRange),
              let insertionRange = Self.collapsedRange(
                at: startLocation,
                advancedBy: committedLength
              )
        else {
            self.insertionRange = nil
            return
        }

        self.insertionRange = insertionRange
    }

    mutating func recordMarkedTextUpdate(
        replacementRange: NSRange,
        markedLength: Int,
        client: IMKTextInput
    ) {
        guard markedLength > 0,
              let startLocation = startLocationForMarkedTextUpdate(
                replacementRange: replacementRange,
                client: client
              ),
              let markedRange = Self.range(location: startLocation, length: markedLength),
              let insertionRange = Self.collapsedRange(at: startLocation, advancedBy: markedLength)
        else {
            return
        }

        self.markedRange = markedRange
        self.insertionRange = insertionRange
    }

    mutating func recordBoundaryTextAfterActiveComposition(committedLength: Int) {
        markedRange = nil

        guard committedLength > 0,
              let insertionRange,
              let advancedRange = Self.collapsedRange(
                at: insertionRange.location,
                advancedBy: committedLength
              )
        else {
            self.insertionRange = nil
            return
        }

        self.insertionRange = advancedRange
    }

    mutating func recordMarkedTextClear(client: IMKTextInput) {
        if let markedRange {
            insertionRange = NSRange(location: markedRange.location, length: 0)
            self.markedRange = nil
            return
        }

        let clientMarkedRange = client.markedRange()
        if let markedRange = Self.validMarkedRange(clientMarkedRange) {
            insertionRange = NSRange(location: markedRange.location, length: 0)
        }
        self.markedRange = nil
    }

    mutating func clear() {
        markedRange = nil
        insertionRange = nil
    }

    private func startLocationForCommit(replacementRange: NSRange) -> Int? {
        if replacementRange.location != NSNotFound {
            return replacementRange.location
        }

        if let markedRange {
            return markedRange.location
        }

        return insertionRange?.location
    }

    private func shouldTrustPostCommitSelectedRange(
        preCommitSelectedRange: NSRange,
        replacementRange: NSRange
    ) -> Bool {
        guard replacementRange.location != NSNotFound,
              preCommitSelectedRange.location != NSNotFound
        else {
            return false
        }

        return !MarkedTextRangePolicy.isSelectionRange(
            preCommitSelectedRange,
            consistentWithMarkedRange: replacementRange
        )
    }

    private func startLocationForMarkedTextUpdate(
        replacementRange: NSRange,
        client: IMKTextInput
    ) -> Int? {
        let clientMarkedRange = client.markedRange()
        if let markedRange = Self.validMarkedRange(clientMarkedRange) {
            return markedRange.location
        }

        if replacementRange.location != NSNotFound {
            return replacementRange.location
        }

        if let markedRange {
            return markedRange.location
        }

        return insertionRange?.location
    }

    private static func validMarkedRange(_ range: NSRange) -> NSRange? {
        guard range.location != NSNotFound, range.length > 0 else {
            return nil
        }
        return range
    }

    private static func validCollapsedRange(_ range: NSRange) -> NSRange? {
        guard range.location != NSNotFound, range.length == 0 else {
            return nil
        }
        return range
    }

    private static func range(location: Int, length: Int) -> NSRange? {
        guard location != NSNotFound, length >= 0 else {
            return nil
        }

        let (_, overflow) = location.addingReportingOverflow(length)
        guard !overflow else {
            return nil
        }

        return NSRange(location: location, length: length)
    }

    private static func collapsedRange(at location: Int, advancedBy length: Int) -> NSRange? {
        guard location != NSNotFound, length >= 0 else {
            return nil
        }

        let (advancedLocation, overflow) = location.addingReportingOverflow(length)
        guard !overflow else {
            return nil
        }

        return NSRange(location: advancedLocation, length: 0)
    }
}
