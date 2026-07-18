import Foundation

enum DefaultMarkedTextRangeReason: String {
    case marked
    case currentSelection = "current-selection"
    case markedContinuation = "marked-continuation"
}

struct DefaultMarkedTextReplacementDecision {
    let replacementRange: NSRange
    let selectedRange: NSRange
    let markedRange: NSRange
    let reason: DefaultMarkedTextRangeReason
}

enum DefaultMarkedTextRangePolicy {
    static let policyID = "current-selection-nsnotfound+marked-continuation"

    static var currentSelectionReplacementRange: NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    static func updateCompositionReplacementDecision(
        pendingMarkedTextReplacementRange: NSRange?
    ) -> (NSRange, DefaultMarkedTextRangeReason) {
        guard let pendingMarkedTextReplacementRange else {
            return (currentSelectionReplacementRange, .currentSelection)
        }
        return (pendingMarkedTextReplacementRange, .markedContinuation)
    }

    static func replacementDecision(
        hasMarkedText: Bool,
        selectedRange selectedRangeProvider: @autoclosure () -> NSRange,
        markedRange markedRangeProvider: @autoclosure () -> NSRange
    ) -> DefaultMarkedTextReplacementDecision {
        let selectedRange = selectedRangeProvider()
        let markedRange = markedRangeProvider()

        if hasMarkedText, markedRange.location != NSNotFound, markedRange.length > 0 {
            return DefaultMarkedTextReplacementDecision(
                replacementRange: markedRange,
                selectedRange: selectedRange,
                markedRange: markedRange,
                reason: .marked
            )
        }

        return DefaultMarkedTextReplacementDecision(
            replacementRange: currentSelectionReplacementRange,
            selectedRange: selectedRange,
            markedRange: markedRange,
            reason: .currentSelection
        )
    }

    static func continuationRange(
        afterReplacing replacementRange: NSRange,
        withCommittedText committedText: String,
        selectedRange selectedRangeProvider: @autoclosure () -> NSRange
    ) -> NSRange? {
        let committedLength = committedText.utf16.count

        if replacementRange.location != NSNotFound {
            let (location, overflow) = replacementRange.location.addingReportingOverflow(committedLength)
            if !overflow {
                return NSRange(location: location, length: 0)
            }
        }

        let selectedRange = selectedRangeProvider()
        guard selectedRange.location != NSNotFound, selectedRange.length == 0 else {
            return nil
        }
        return selectedRange
    }

    static func isSelectionRange(
        _ selectedRange: NSRange,
        consistentWithMarkedRange markedRange: NSRange
    ) -> Bool {
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
