import Foundation
import InputMethodKit

enum MarkedTextRangeReason: String {
    case marked
    case currentSelection = "current-selection"
    case markedContinuation = "marked-continuation"
}

struct MarkedTextReplacementDecision {
    let replacementRange: NSRange
    let selectedRange: NSRange
    let markedRange: NSRange
    let reason: MarkedTextRangeReason
}

enum MarkedTextRangePolicy {
    static let policyID = "current-selection-nsnotfound+marked-continuation"

    static var currentSelectionReplacementRange: NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    static func updateCompositionReplacementDecision(
        pendingMarkedTextReplacementRange: NSRange?
    ) -> (NSRange, MarkedTextRangeReason) {
        guard let pendingMarkedTextReplacementRange else {
            return (currentSelectionReplacementRange, .currentSelection)
        }
        return (pendingMarkedTextReplacementRange, .markedContinuation)
    }

    static func replacementDecision(
        hasMarkedText: Bool,
        client: IMKTextInput
    ) -> MarkedTextReplacementDecision {
        let selectedRange = client.selectedRange()
        let markedRange = client.markedRange()

        if hasMarkedText, markedRange.location != NSNotFound, markedRange.length > 0 {
            return MarkedTextReplacementDecision(
                replacementRange: markedRange,
                selectedRange: selectedRange,
                markedRange: markedRange,
                reason: .marked
            )
        }

        return MarkedTextReplacementDecision(
            replacementRange: currentSelectionReplacementRange,
            selectedRange: selectedRange,
            markedRange: markedRange,
            reason: .currentSelection
        )
    }

    static func continuationRange(
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

    static func isSelectionRange(_ selectedRange: NSRange, consistentWithMarkedRange markedRange: NSRange) -> Bool {
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

    private static func upperBound(of range: NSRange) -> Int? {
        guard range.location != NSNotFound else {
            return nil
        }

        let (upperBound, overflow) = range.location.addingReportingOverflow(range.length)
        return overflow ? nil : upperBound
    }
}
