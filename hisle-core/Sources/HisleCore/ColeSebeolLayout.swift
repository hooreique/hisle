public struct ColeSebeolJamoPair: Hashable, Sendable {
    public let first: Unicode.Scalar
    public let second: Unicode.Scalar

    public init(first: Unicode.Scalar, second: Unicode.Scalar) {
        self.first = first
        self.second = second
    }
}

public struct ColeSebeolPositionalJamoPair: Hashable, Sendable {
    public let first: Unicode.Scalar
    public let secondRepresentativeKey: Unicode.Scalar
    public let second: Unicode.Scalar

    public init(
        first: Unicode.Scalar,
        secondRepresentativeKey: Unicode.Scalar,
        second: Unicode.Scalar
    ) {
        self.first = first
        self.secondRepresentativeKey = secondRepresentativeKey
        self.second = second
    }
}

public struct ColeSebeolSourceKeyPair: Hashable, Sendable {
    public let first: Unicode.Scalar
    public let second: Unicode.Scalar

    public init(first: Unicode.Scalar, second: Unicode.Scalar) {
        self.first = first
        self.second = second
    }
}

public struct ColeSebeolLayout: Equatable, Sendable {
    public static let printableRepresentativeScalars: ClosedRange<UInt32> = 0x21...0x7E

    public let keyboardID: String
    public let name: String
    public let mapID: String
    public let combinationID: String
    public let keyMappings: [Unicode.Scalar: Unicode.Scalar]
    public let underlyingRomanMappings: [Unicode.Scalar: Unicode.Scalar]
    public let compatibilityJamoMappings: [Unicode.Scalar: Unicode.Scalar]
    public let jamoCombinations: [ColeSebeolJamoPair: Unicode.Scalar]
    public let positionalJamoCombinations: [ColeSebeolPositionalJamoPair: Unicode.Scalar]
    public let sourceKeyCombinations: [ColeSebeolSourceKeyPair: Unicode.Scalar]
    public let referencedJamoScalars: Set<Unicode.Scalar>

    public init(
        keyboardID: String,
        name: String,
        mapID: String,
        combinationID: String,
        keyMappings: [Unicode.Scalar: Unicode.Scalar],
        underlyingRomanMappings: [Unicode.Scalar: Unicode.Scalar],
        compatibilityJamoMappings: [Unicode.Scalar: Unicode.Scalar],
        jamoCombinations: [ColeSebeolJamoPair: Unicode.Scalar],
        positionalJamoCombinations: [ColeSebeolPositionalJamoPair: Unicode.Scalar],
        sourceKeyCombinations: [ColeSebeolSourceKeyPair: Unicode.Scalar],
        referencedJamoScalars: Set<Unicode.Scalar>
    ) {
        self.keyboardID = keyboardID
        self.name = name
        self.mapID = mapID
        self.combinationID = combinationID
        self.keyMappings = keyMappings
        self.underlyingRomanMappings = underlyingRomanMappings
        self.compatibilityJamoMappings = compatibilityJamoMappings
        self.jamoCombinations = jamoCombinations
        self.positionalJamoCombinations = positionalJamoCombinations
        self.sourceKeyCombinations = sourceKeyCombinations
        self.referencedJamoScalars = referencedJamoScalars
    }

    public func output(forRepresentativeKey representativeKey: Unicode.Scalar) -> Unicode.Scalar? {
        keyMappings[representativeKey]
    }

    public func underlyingRomanKey(forRepresentativeKey representativeKey: Unicode.Scalar) -> Unicode.Scalar? {
        underlyingRomanMappings[representativeKey]
    }

    public func compatibilityJamo(for jamo: Unicode.Scalar) -> Unicode.Scalar? {
        compatibilityJamoMappings[jamo]
    }

    public func combinedJamo(first: Unicode.Scalar, second: Unicode.Scalar) -> Unicode.Scalar? {
        jamoCombinations[ColeSebeolJamoPair(first: first, second: second)]
    }

    public func positionalCombinedJamo(
        first: Unicode.Scalar,
        secondRepresentativeKey: Unicode.Scalar,
        second: Unicode.Scalar
    ) -> Unicode.Scalar? {
        positionalJamoCombinations[
            ColeSebeolPositionalJamoPair(
                first: first,
                secondRepresentativeKey: secondRepresentativeKey,
                second: second
            )
        ]
    }

    public func sourceCombinedJamo(
        firstSourceKey: Unicode.Scalar,
        secondSourceKey: Unicode.Scalar
    ) -> Unicode.Scalar? {
        sourceKeyCombinations[ColeSebeolSourceKeyPair(first: firstSourceKey, second: secondSourceKey)]
    }

    public func structuralIssues() -> [ColeSebeolSpecIssue] {
        var issues: [ColeSebeolSpecIssue] = []

        for value in Self.printableRepresentativeScalars {
            guard let representative = Unicode.Scalar(value) else {
                continue
            }
            if keyMappings[representative] == nil {
                issues.append(.init(message: "missing key row for \(formatASCII(representative))"))
            }
            if underlyingRomanMappings[representative] == nil {
                issues.append(.init(message: "missing underlying-key row for \(formatASCII(representative))"))
            }
        }

        for representative in keyMappings.keys
            where !Self.printableRepresentativeScalars.contains(representative.value) {
            issues.append(.init(message: "unexpected key row outside printable ASCII: \(formatScalar(representative))"))
        }

        for representative in underlyingRomanMappings.keys
            where !Self.printableRepresentativeScalars.contains(representative.value) {
            issues.append(.init(
                message: "unexpected underlying-key row outside printable ASCII: " +
                    "\(formatScalar(representative))"
            ))
        }

        for jamo in referencedJamoScalars.sorted(by: { $0.value < $1.value })
            where compatibilityJamoMappings[jamo] == nil {
            issues.append(.init(message: "missing compat-jamo row for \(formatScalar(jamo))"))
        }

        return issues
    }
}

func isHangulJamo(_ scalar: Unicode.Scalar) -> Bool {
    (0x1100...0x11FF).contains(scalar.value)
}

func formatScalar(_ scalar: Unicode.Scalar) -> String {
    "U+\(String(scalar.value, radix: 16, uppercase: true).leftPadded(toLength: 4, with: "0"))"
}

func formatASCII(_ scalar: Unicode.Scalar) -> String {
    "0x\(String(scalar.value, radix: 16, uppercase: true).leftPadded(toLength: 2, with: "0"))"
}

private extension String {
    func leftPadded(toLength length: Int, with pad: Character) -> String {
        if count >= length {
            return self
        }
        return String(repeating: String(pad), count: length - count) + self
    }
}
