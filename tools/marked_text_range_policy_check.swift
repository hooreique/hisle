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
        for example in examples {
            let actual = MarkedTextRangePolicy.isSelectionRange(
                example.selectedRange,
                consistentWithMarkedRange: example.markedRange
            )
            guard actual == example.expected else {
                throw SelectionConsistencyFailure(example: example, actual: actual)
            }
        }

        print("Marked text range policy check passed \(examples.count) examples.")
    }
}
