import Foundation

private struct SelectionConsistencyExample {
    let name: String
    let selectedRange: NSRange
    let markedRange: NSRange
    let expected: Bool
}

private struct SelectionConsistencyFailure: Error, CustomStringConvertible {
    let example: SelectionConsistencyExample
    let actual: Bool

    var description: String {
        "\(example.name): selected=\(NSStringFromRange(example.selectedRange)) " +
            "marked=\(NSStringFromRange(example.markedRange)) " +
            "expected=\(example.expected) actual=\(actual)"
    }
}

private struct ReplacementDecisionFailure: Error, CustomStringConvertible {
    let description: String
}

@main
private enum MarkedTextRangePolicyCheck {
    private static let examples = [
        SelectionConsistencyExample(
            name: "exact non-collapsed range",
            selectedRange: NSRange(location: 10, length: 3),
            markedRange: NSRange(location: 10, length: 3),
            expected: true
        ),
        SelectionConsistencyExample(
            name: "collapsed at start",
            selectedRange: NSRange(location: 10, length: 0),
            markedRange: NSRange(location: 10, length: 3),
            expected: true
        ),
        SelectionConsistencyExample(
            name: "collapsed at end",
            selectedRange: NSRange(location: 13, length: 0),
            markedRange: NSRange(location: 10, length: 3),
            expected: true
        ),
        SelectionConsistencyExample(
            name: "collapsed one past end",
            selectedRange: NSRange(location: 14, length: 0),
            markedRange: NSRange(location: 10, length: 3),
            expected: true
        ),
        SelectionConsistencyExample(
            name: "shorter range sharing start",
            selectedRange: NSRange(location: 10, length: 2),
            markedRange: NSRange(location: 10, length: 3),
            expected: false
        ),
        SelectionConsistencyExample(
            name: "longer range sharing start",
            selectedRange: NSRange(location: 10, length: 4),
            markedRange: NSRange(location: 10, length: 3),
            expected: false
        ),
        SelectionConsistencyExample(
            name: "shorter range sharing end",
            selectedRange: NSRange(location: 11, length: 2),
            markedRange: NSRange(location: 10, length: 3),
            expected: false
        ),
        SelectionConsistencyExample(
            name: "longer range sharing end",
            selectedRange: NSRange(location: 9, length: 4),
            markedRange: NSRange(location: 10, length: 3),
            expected: false
        ),
        SelectionConsistencyExample(
            name: "non-collapsed one past end",
            selectedRange: NSRange(location: 14, length: 1),
            markedRange: NSRange(location: 10, length: 3),
            expected: false
        ),
        SelectionConsistencyExample(
            name: "contained non-collapsed range",
            selectedRange: NSRange(location: 11, length: 1),
            markedRange: NSRange(location: 10, length: 3),
            expected: false
        ),
        SelectionConsistencyExample(
            name: "collapsed before start",
            selectedRange: NSRange(location: 9, length: 0),
            markedRange: NSRange(location: 10, length: 3),
            expected: false
        ),
        SelectionConsistencyExample(
            name: "collapsed after compatible positions",
            selectedRange: NSRange(location: 15, length: 0),
            markedRange: NSRange(location: 10, length: 3),
            expected: false
        ),
        SelectionConsistencyExample(
            name: "selected range not found",
            selectedRange: NSRange(location: NSNotFound, length: 0),
            markedRange: NSRange(location: 10, length: 3),
            expected: false
        ),
        SelectionConsistencyExample(
            name: "marked range not found",
            selectedRange: NSRange(location: 10, length: 0),
            markedRange: NSRange(location: NSNotFound, length: 0),
            expected: false
        ),
        SelectionConsistencyExample(
            name: "selected range upper-bound overflow",
            selectedRange: NSRange(location: Int.max - 1, length: 2),
            markedRange: NSRange(location: 10, length: 3),
            expected: false
        ),
        SelectionConsistencyExample(
            name: "marked range upper-bound overflow",
            selectedRange: NSRange(location: 10, length: 0),
            markedRange: NSRange(location: Int.max - 1, length: 2),
            expected: false
        ),
        SelectionConsistencyExample(
            name: "negative selected location",
            selectedRange: NSRange(location: -1, length: 0),
            markedRange: NSRange(location: 10, length: 3),
            expected: false
        ),
        SelectionConsistencyExample(
            name: "negative selected length",
            selectedRange: NSRange(location: 10, length: -1),
            markedRange: NSRange(location: 10, length: 3),
            expected: false
        ),
        SelectionConsistencyExample(
            name: "negative marked location",
            selectedRange: NSRange(location: 10, length: 0),
            markedRange: NSRange(location: -1, length: 3),
            expected: false
        ),
        SelectionConsistencyExample(
            name: "negative marked length",
            selectedRange: NSRange(location: 10, length: 0),
            markedRange: NSRange(location: 10, length: -1),
            expected: false
        )
    ]

    static func main() throws {
        try checkPlainCommitFastPath()
        try checkActiveMarkedTextRangeReads()

        for example in examples {
            let actual = MarkedTextRangePolicy.isSelectionRange(
                example.selectedRange,
                consistentWithMarkedRange: example.markedRange
            )
            guard actual == example.expected else {
                throw SelectionConsistencyFailure(example: example, actual: actual)
            }
        }

        print(
            "Marked text range policy check passed \(examples.count) selection examples " +
                "and 2 replacement-decision examples."
        )
    }

    private static func checkPlainCommitFastPath() throws {
        var selectedRangeReadCount = 0
        var markedRangeReadCount = 0

        func readSelectedRange() -> NSRange {
            selectedRangeReadCount += 1
            return NSRange(location: 40, length: 2)
        }

        func readMarkedRange() -> NSRange {
            markedRangeReadCount += 1
            return NSRange(location: 40, length: 2)
        }

        let decision = MarkedTextRangePolicy.replacementDecision(
            hasMarkedText: false,
            ownedMarkedRange: NSRange(location: 30, length: 2),
            selectedRange: readSelectedRange(),
            markedRange: readMarkedRange()
        )
        let currentSelection = MarkedTextRangePolicy.currentSelectionReplacementRange

        guard selectedRangeReadCount == 0, markedRangeReadCount == 0 else {
            throw ReplacementDecisionFailure(
                description: "plain commit read client ranges: " +
                    "selected=\(selectedRangeReadCount) marked=\(markedRangeReadCount)"
            )
        }
        guard decision.replacementRange == currentSelection,
              decision.selectedRange == currentSelection,
              decision.markedRange == currentSelection,
              decision.reason.rawValue == MarkedTextRangeReason.currentSelection.rawValue
        else {
            throw ReplacementDecisionFailure(
                description: "plain commit did not return the current-selection decision"
            )
        }
    }

    private static func checkActiveMarkedTextRangeReads() throws {
        var selectedRangeReadCount = 0
        var markedRangeReadCount = 0
        let selectedRange = NSRange(location: 12, length: 0)
        let markedRange = NSRange(location: 10, length: 3)

        func readSelectedRange() -> NSRange {
            selectedRangeReadCount += 1
            return selectedRange
        }

        func readMarkedRange() -> NSRange {
            markedRangeReadCount += 1
            return markedRange
        }

        let decision = MarkedTextRangePolicy.replacementDecision(
            hasMarkedText: true,
            ownedMarkedRange: nil,
            selectedRange: readSelectedRange(),
            markedRange: readMarkedRange()
        )

        guard selectedRangeReadCount == 1, markedRangeReadCount == 1 else {
            throw ReplacementDecisionFailure(
                description: "active marked text did not read each client range once: " +
                    "selected=\(selectedRangeReadCount) marked=\(markedRangeReadCount)"
            )
        }
        guard decision.replacementRange == markedRange,
              decision.selectedRange == selectedRange,
              decision.markedRange == markedRange,
              decision.reason.rawValue == MarkedTextRangeReason.marked.rawValue
        else {
            throw ReplacementDecisionFailure(
                description: "active marked text did not preserve the host marked-range decision"
            )
        }
    }
}
