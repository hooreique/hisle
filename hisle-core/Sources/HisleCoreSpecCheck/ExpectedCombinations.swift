struct ExpectedCombination<Part> {
    let first: Part
    let second: Part
    let result: UInt32

    init(_ first: Part, _ second: Part, _ result: UInt32) {
        self.first = first
        self.second = second
        self.result = result
    }
}

typealias ExpectedJamoCombination = ExpectedCombination<UInt32>
typealias ExpectedSourceKeyCombination = ExpectedCombination<Unicode.Scalar>

struct ExpectedPositionalJamoCombination {
    let first: UInt32
    let secondRepresentativeKey: UInt32
    let second: UInt32
    let result: UInt32

    init(_ first: UInt32, _ secondRepresentativeKey: UInt32, _ second: UInt32, _ result: UInt32) {
        self.first = first
        self.secondRepresentativeKey = secondRepresentativeKey
        self.second = second
        self.result = result
    }
}
