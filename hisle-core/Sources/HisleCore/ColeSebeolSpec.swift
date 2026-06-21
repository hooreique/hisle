import Foundation

public struct ColeSebeolSpecIssue: Equatable, Sendable, CustomStringConvertible {
    public let lineNumber: Int?
    public let message: String

    public init(lineNumber: Int? = nil, message: String) {
        self.lineNumber = lineNumber
        self.message = message
    }

    public var description: String {
        if let lineNumber {
            return "line \(lineNumber): \(message)"
        }
        return message
    }
}

public struct ColeSebeolSpecParseResult: Equatable, Sendable {
    public let layout: ColeSebeolLayout
    public let issues: [ColeSebeolSpecIssue]

    public init(layout: ColeSebeolLayout, issues: [ColeSebeolSpecIssue]) {
        self.layout = layout
        self.issues = issues
    }
}

public struct ColeSebeolSpecError: Error, LocalizedError, CustomStringConvertible {
    public let issues: [ColeSebeolSpecIssue]

    public init(issues: [ColeSebeolSpecIssue]) {
        self.issues = issues
    }

    public var description: String {
        issues.map(\.description).joined(separator: "\n")
    }

    public var errorDescription: String? {
        description
    }
}

public enum ColeSebeolSpec {
    public static func bundledText() throws -> String {
        guard let url = Bundle.module.url(forResource: "cole-sebeol-spec", withExtension: "txt") else {
            throw ColeSebeolSpecError(issues: [.init(message: "cole-sebeol-spec.txt resource not found")])
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    public static func bundledLayout() throws -> ColeSebeolLayout {
        let result = parse(try bundledText())
        let issues = result.issues + result.layout.structuralIssues()
        if issues.isEmpty == false {
            throw ColeSebeolSpecError(issues: issues)
        }
        return result.layout
    }

    public static func parse(_ text: String) -> ColeSebeolSpecParseResult {
        var parser = ColeSebeolSpecParser()
        return parser.parse(text)
    }
}

private struct ColeSebeolSpecParser {
    private var keyboardID = "cole-sebeol"
    private var name = "Cole Sebeol"
    private var mapID = "0"
    private var combinationID = "default"
    private var keyMappings: [Unicode.Scalar: Unicode.Scalar] = [:]
    private var underlyingRomanMappings: [Unicode.Scalar: Unicode.Scalar] = [:]
    private var compatibilityJamoMappings: [Unicode.Scalar: Unicode.Scalar] = [:]
    private var jamoCombinations: [ColeSebeolJamoPair: Unicode.Scalar] = [:]
    private var positionalJamoCombinations: [ColeSebeolPositionalJamoPair: Unicode.Scalar] = [:]
    private var sourceKeyCombinations: [ColeSebeolSourceKeyPair: Unicode.Scalar] = [:]
    private var referencedJamoScalars: Set<Unicode.Scalar> = []
    private var issues: [ColeSebeolSpecIssue] = []

    mutating func parse(_ text: String) -> ColeSebeolSpecParseResult {
        for (offset, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            parseLine(String(rawLine), lineNumber: offset + 1)
        }

        return ColeSebeolSpecParseResult(
            layout: ColeSebeolLayout(
                keyboardID: keyboardID,
                name: name,
                mapID: mapID,
                combinationID: combinationID,
                keyMappings: keyMappings,
                underlyingRomanMappings: underlyingRomanMappings,
                compatibilityJamoMappings: compatibilityJamoMappings,
                jamoCombinations: jamoCombinations,
                positionalJamoCombinations: positionalJamoCombinations,
                sourceKeyCombinations: sourceKeyCombinations,
                referencedJamoScalars: referencedJamoScalars
            ),
            issues: issues
        )
    }

    private mutating func parseLine(_ rawLine: String, lineNumber: Int) {
        let body = rawLine
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if body.isEmpty {
            return
        }

        let parts = body.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        switch parts.first {
        case "keyboard":
            parseKeyboard(body: body, parts: parts, lineNumber: lineNumber)
        case "underlying-key":
            parseUnderlyingKey(parts, lineNumber: lineNumber)
        case "key":
            parseKey(parts, lineNumber: lineNumber)
        case "compat-jamo":
            parseCompatibilityJamo(parts, lineNumber: lineNumber)
        case "combine":
            parseCombine(parts, lineNumber: lineNumber)
        case "positional-combine":
            parsePositionalCombine(parts, lineNumber: lineNumber)
        case "source-combine":
            parseSourceCombine(parts, lineNumber: lineNumber)
        default:
            return
        }
    }

    private mutating func parseKeyboard(body: String, parts: [String], lineNumber: Int) {
        guard parts.count >= 2 else {
            fail("malformed keyboard row", lineNumber: lineNumber)
            return
        }

        keyboardID = parts[1]
        name = quotedName(in: body) ?? keyboardID

        for part in parts {
            if part.hasPrefix("map=") {
                mapID = String(part.dropFirst("map=".count))
            } else if part.hasPrefix("combination=") {
                combinationID = String(part.dropFirst("combination=".count))
            }
        }
    }

    private mutating func parseUnderlyingKey(_ parts: [String], lineNumber: Int) {
        guard parts.count >= 4,
              let representative = scalarCodePoint(parts[2]),
              let underlying = scalarCodePoint(parts[3])
        else {
            fail("malformed underlying-key row", lineNumber: lineNumber)
            return
        }

        if let duplicate = insertUnique(
            underlying,
            for: representative,
            into: &underlyingRomanMappings,
            rowName: "underlying-key"
        ) {
            fail(duplicate, lineNumber: lineNumber)
        }
    }

    private mutating func parseKey(_ parts: [String], lineNumber: Int) {
        guard parts.count >= 4,
              let representative = scalarCodePoint(parts[2]),
              let value = scalarCodePoint(parts[3])
        else {
            fail("malformed key row", lineNumber: lineNumber)
            return
        }

        if let duplicate = insertUnique(
            value,
            for: representative,
            into: &keyMappings,
            rowName: "key"
        ) {
            fail(duplicate, lineNumber: lineNumber)
        }
        rememberJamo(value)
    }

    private mutating func parseCompatibilityJamo(_ parts: [String], lineNumber: Int) {
        guard parts.count >= 3,
              let jamo = scalarCodePoint(parts[1]),
              let compatibilityJamo = scalarCodePoint(parts[2])
        else {
            fail("malformed compat-jamo row", lineNumber: lineNumber)
            return
        }

        if let duplicate = insertUnique(
            compatibilityJamo,
            for: jamo,
            into: &compatibilityJamoMappings,
            rowName: "compat-jamo"
        ) {
            fail(duplicate, lineNumber: lineNumber)
        }
    }

    private mutating func parseCombine(_ parts: [String], lineNumber: Int) {
        guard parts.count >= 5,
              let first = scalarCodePoint(parts[2]),
              let second = scalarCodePoint(parts[3]),
              let result = scalarCodePoint(parts[4])
        else {
            fail("malformed combine row", lineNumber: lineNumber)
            return
        }

        if let duplicate = insertUnique(
            result,
            for: ColeSebeolJamoPair(first: first, second: second),
            into: &jamoCombinations,
            rowName: "combine"
        ) {
            fail(duplicate, lineNumber: lineNumber)
        }
        rememberJamo(first)
        rememberJamo(second)
        rememberJamo(result)
    }

    private mutating func parsePositionalCombine(_ parts: [String], lineNumber: Int) {
        guard parts.count >= 6,
              let first = scalarCodePoint(parts[2]),
              let representative = scalarCodePoint(parts[3]),
              let second = scalarCodePoint(parts[4]),
              let result = scalarCodePoint(parts[5])
        else {
            fail("malformed positional-combine row", lineNumber: lineNumber)
            return
        }

        if let duplicate = insertUnique(
            result,
            for: ColeSebeolPositionalJamoPair(
                first: first,
                secondRepresentativeKey: representative,
                second: second
            ),
            into: &positionalJamoCombinations,
            rowName: "positional-combine"
        ) {
            fail(duplicate, lineNumber: lineNumber)
        }
        rememberJamo(first)
        rememberJamo(second)
        rememberJamo(result)
    }

    private mutating func parseSourceCombine(_ parts: [String], lineNumber: Int) {
        guard parts.count >= 5,
              let first = sourceKey(parts[2]),
              let second = sourceKey(parts[3]),
              let result = scalarCodePoint(parts[4])
        else {
            fail("malformed source-combine row", lineNumber: lineNumber)
            return
        }

        if let duplicate = insertUnique(
            result,
            for: ColeSebeolSourceKeyPair(first: first, second: second),
            into: &sourceKeyCombinations,
            rowName: "source-combine"
        ) {
            fail(duplicate, lineNumber: lineNumber)
        }
        rememberJamo(result)
    }

    private mutating func rememberJamo(_ scalar: Unicode.Scalar) {
        if isHangulJamo(scalar) {
            referencedJamoScalars.insert(scalar)
        }
    }

    private mutating func fail(_ message: String, lineNumber: Int) {
        issues.append(.init(lineNumber: lineNumber, message: message))
    }

    private func quotedName(in body: String) -> String? {
        guard let firstQuote = body.firstIndex(of: "\"") else {
            return nil
        }
        let afterFirstQuote = body.index(after: firstQuote)
        guard let secondQuote = body[afterFirstQuote...].firstIndex(of: "\"") else {
            return nil
        }
        return String(body[afterFirstQuote..<secondQuote])
    }

    private func scalarCodePoint(_ token: String) -> Unicode.Scalar? {
        let uppercased = token.uppercased()
        let digits: Substring
        if uppercased.hasPrefix("U+") {
            digits = uppercased.dropFirst(2)
        } else if uppercased.hasPrefix("0X") {
            digits = uppercased.dropFirst(2)
        } else {
            return nil
        }

        guard let value = UInt32(digits, radix: 16) else {
            return nil
        }
        return Unicode.Scalar(value)
    }

    private func sourceKey(_ token: String) -> Unicode.Scalar? {
        let scalars = Array(token.unicodeScalars)
        guard scalars.count == 1 else {
            return nil
        }
        return scalars[0]
    }
}

private func insertUnique<Key: Hashable>(
    _ value: Unicode.Scalar,
    for key: Key,
    into rows: inout [Key: Unicode.Scalar],
    rowName: String
) -> String? {
    let duplicate = rows[key].map {
        "duplicate \(rowName); previous \(formatScalar($0)), new \(formatScalar(value))"
    }
    rows[key] = value
    return duplicate
}
