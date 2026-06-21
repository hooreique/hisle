import Darwin
import Foundation
import HisleCore

private let expectedColeSebeolOutputByRepresentative: [UInt32: UInt32] = [
    0x21: 0x11A9, 0x22: 0x0022, 0x23: 0x11BD, 0x24: 0x11B5,
    0x25: 0x11B4, 0x26: 0x0026, 0x27: 0x1110, 0x28: 0x0028,
    0x29: 0x0029, 0x2A: 0x002A, 0x2B: 0x002B, 0x2C: 0x002C,
    0x2D: 0x002D, 0x2E: 0x002E, 0x2F: 0x1169, 0x30: 0x110F,
    0x31: 0x11C2, 0x32: 0x11BB, 0x33: 0x11B8, 0x34: 0x116D,
    0x35: 0x1172, 0x36: 0x1163, 0x37: 0x1168, 0x38: 0x1174,
    0x39: 0x116E, 0x3A: 0x0034, 0x3B: 0x1107, 0x3C: 0x003C,
    0x3D: 0x003D, 0x3E: 0x003E, 0x3F: 0x0021, 0x40: 0x11B0,
    0x41: 0x11AE, 0x42: 0x003F, 0x43: 0x11BF, 0x44: 0x11B2,
    0x45: 0x11AC, 0x46: 0x11B1, 0x47: 0x1164, 0x48: 0x0030,
    0x49: 0x0037, 0x4A: 0x0031, 0x4B: 0x0032, 0x4C: 0x0033,
    0x4D: 0x003B, 0x4E: 0x003A, 0x4F: 0x0038, 0x50: 0x0039,
    0x51: 0x11C1, 0x52: 0x11B6, 0x53: 0x11AD, 0x54: 0x11B3,
    0x55: 0x0036, 0x56: 0x11AA, 0x57: 0x11C0, 0x58: 0x11B9,
    0x59: 0x0035, 0x5A: 0x11BE, 0x5B: 0x005B, 0x5C: 0x005C,
    0x5D: 0x005D, 0x5E: 0x005E, 0x5F: 0x005F, 0x60: 0x0060,
    0x61: 0x11BC, 0x62: 0x116E, 0x63: 0x1166, 0x64: 0x1175,
    0x65: 0x1167, 0x66: 0x1161, 0x67: 0x1173, 0x68: 0x1102,
    0x69: 0x1106, 0x6A: 0x110B, 0x6B: 0x1100, 0x6C: 0x110C,
    0x6D: 0x1112, 0x6E: 0x1109, 0x6F: 0x110E, 0x70: 0x1111,
    0x71: 0x11BA, 0x72: 0x1162, 0x73: 0x11AB, 0x74: 0x1165,
    0x75: 0x1103, 0x76: 0x1169, 0x77: 0x11AF, 0x78: 0x11A8,
    0x79: 0x1105, 0x7A: 0x11B7, 0x7B: 0x007B, 0x7C: 0x007C,
    0x7D: 0x007D, 0x7E: 0x007E,
]

private let expectedColemakUnderlyingByRepresentative: [UInt32: UInt32] = [
    0x21: 0x21, 0x22: 0x22, 0x23: 0x23, 0x24: 0x24, 0x25: 0x25,
    0x26: 0x26, 0x27: 0x27, 0x28: 0x28, 0x29: 0x29, 0x2A: 0x2A,
    0x2B: 0x2B, 0x2C: 0x2C, 0x2D: 0x2D, 0x2E: 0x2E, 0x2F: 0x2F,
    0x30: 0x30, 0x31: 0x31, 0x32: 0x32, 0x33: 0x33, 0x34: 0x34,
    0x35: 0x35, 0x36: 0x36, 0x37: 0x37, 0x38: 0x38, 0x39: 0x39,
    0x3A: 0x4F, 0x3B: 0x6F, 0x3C: 0x3C, 0x3D: 0x3D, 0x3E: 0x3E,
    0x3F: 0x3F, 0x40: 0x40, 0x41: 0x41, 0x42: 0x42, 0x43: 0x43,
    0x44: 0x53, 0x45: 0x46, 0x46: 0x54, 0x47: 0x44, 0x48: 0x48,
    0x49: 0x55, 0x4A: 0x4E, 0x4B: 0x45, 0x4C: 0x49, 0x4D: 0x4D,
    0x4E: 0x4B, 0x4F: 0x59, 0x50: 0x3A, 0x51: 0x51, 0x52: 0x50,
    0x53: 0x52, 0x54: 0x47, 0x55: 0x4C, 0x56: 0x56, 0x57: 0x57,
    0x58: 0x58, 0x59: 0x4A, 0x5A: 0x5A, 0x5B: 0x5B, 0x5C: 0x5C,
    0x5D: 0x5D, 0x5E: 0x5E, 0x5F: 0x5F, 0x60: 0x60, 0x61: 0x61,
    0x62: 0x62, 0x63: 0x63, 0x64: 0x73, 0x65: 0x66, 0x66: 0x74,
    0x67: 0x64, 0x68: 0x68, 0x69: 0x75, 0x6A: 0x6E, 0x6B: 0x65,
    0x6C: 0x69, 0x6D: 0x6D, 0x6E: 0x6B, 0x6F: 0x79, 0x70: 0x3B,
    0x71: 0x71, 0x72: 0x70, 0x73: 0x72, 0x74: 0x67, 0x75: 0x6C,
    0x76: 0x76, 0x77: 0x77, 0x78: 0x78, 0x79: 0x6A, 0x7A: 0x7A,
    0x7B: 0x7B, 0x7C: 0x7C, 0x7D: 0x7D, 0x7E: 0x7E,
]

private let expectedCompatibilityJamo: [UInt32: UInt32] = [
    0x1100: 0x3131, 0x1101: 0x3132, 0x1102: 0x3134,
    0x1103: 0x3137, 0x1104: 0x3138, 0x1105: 0x3139,
    0x1106: 0x3141, 0x1107: 0x3142, 0x1108: 0x3143,
    0x1109: 0x3145, 0x110A: 0x3146, 0x110B: 0x3147,
    0x110C: 0x3148, 0x110D: 0x3149, 0x110E: 0x314A,
    0x110F: 0x314B, 0x1110: 0x314C, 0x1111: 0x314D,
    0x1112: 0x314E, 0x1161: 0x314F, 0x1162: 0x3150,
    0x1163: 0x3151, 0x1164: 0x3152, 0x1165: 0x3153,
    0x1166: 0x3154, 0x1167: 0x3155, 0x1168: 0x3156,
    0x1169: 0x3157, 0x116A: 0x3158, 0x116B: 0x3159,
    0x116C: 0x315A, 0x116D: 0x315B, 0x116E: 0x315C,
    0x116F: 0x315D, 0x1170: 0x315E, 0x1171: 0x315F,
    0x1172: 0x3160, 0x1173: 0x3161, 0x1174: 0x3162,
    0x1175: 0x3163, 0x11A8: 0x3131, 0x11A9: 0x3132,
    0x11AA: 0x3133, 0x11AB: 0x3134, 0x11AC: 0x3135,
    0x11AD: 0x3136, 0x11AE: 0x3137, 0x11AF: 0x3139,
    0x11B0: 0x313A, 0x11B1: 0x313B, 0x11B2: 0x313C,
    0x11B3: 0x313D, 0x11B4: 0x313E, 0x11B5: 0x313F,
    0x11B6: 0x3140, 0x11B7: 0x3141, 0x11B8: 0x3142,
    0x11B9: 0x3144, 0x11BA: 0x3145, 0x11BB: 0x3146,
    0x11BC: 0x3147, 0x11BD: 0x3148, 0x11BE: 0x314A,
    0x11BF: 0x314B, 0x11C0: 0x314C, 0x11C1: 0x314D,
    0x11C2: 0x314E,
]

private let expectedJamoCombinations: [(UInt32, UInt32, UInt32)] = [
    (0x110B, 0x1100, 0x1101), (0x1100, 0x110B, 0x1101),
    (0x1100, 0x110C, 0x110D), (0x110C, 0x1100, 0x110D),
    (0x110C, 0x1107, 0x1108), (0x1107, 0x110C, 0x1108),
    (0x1103, 0x1106, 0x1104), (0x1106, 0x1103, 0x1104),
    (0x1109, 0x1112, 0x110A), (0x1112, 0x1109, 0x110A),
    (0x1175, 0x1161, 0x1164), (0x1161, 0x1175, 0x1164),
    (0x1175, 0x1173, 0x1174), (0x1173, 0x1175, 0x1174),
    (0x1167, 0x1162, 0x1168), (0x1162, 0x1167, 0x1168),
    (0x11BC, 0x11AB, 0x11AD), (0x11AB, 0x11BC, 0x11AD),
    (0x11BA, 0x11AF, 0x11B9), (0x11AF, 0x11BA, 0x11B9),
    (0x11B8, 0x11BB, 0x11BD), (0x11BB, 0x11B8, 0x11BD),
    (0x11C2, 0x11BB, 0x11A9), (0x11BB, 0x11C2, 0x11A9),
    (0x11A8, 0x11A8, 0x11A9),
    (0x11A8, 0x11BA, 0x11AA), (0x11AB, 0x11BD, 0x11AC),
    (0x11AB, 0x11C2, 0x11AD), (0x11AF, 0x11A8, 0x11B0),
    (0x11AF, 0x11B7, 0x11B1), (0x11AF, 0x11B8, 0x11B2),
    (0x11AF, 0x11C0, 0x11B4), (0x11AF, 0x11C1, 0x11B5),
    (0x11AF, 0x11C2, 0x11B6), (0x11B8, 0x11BA, 0x11B9),
    (0x11BA, 0x11BA, 0x11BB),
]

private let expectedPositionalJamoCombinations: [(UInt32, UInt32, UInt32, UInt32)] = []

private let expectedSourceKeyCombinations: [(Unicode.Scalar, Unicode.Scalar, UInt32)] = [
    ("/", "f", 0x116A),
    ("f", "/", 0x116A),
    ("v", "f", 0x116A),
    ("/", "r", 0x116B),
    ("r", "/", 0x116B),
    ("v", "r", 0x116B),
    ("/", "d", 0x116C),
    ("d", "/", 0x116C),
    ("v", "d", 0x116C),
    ("9", "t", 0x116F),
    ("t", "9", 0x116F),
    ("b", "t", 0x116F),
    ("9", "c", 0x1170),
    ("c", "9", 0x1170),
    ("b", "c", 0x1170),
    ("9", "d", 0x1171),
    ("d", "9", 0x1171),
    ("b", "d", 0x1171),
]

private var failures: [String] = []
private var checkCount = 0
private var currentSection = "startup"

private func section(_ name: String, _ body: () throws -> Void) throws {
    let previousSection = currentSection
    currentSection = name
    defer { currentSection = previousSection }
    try body()
}

private func fail(_ message: String) {
    failures.append("[\(currentSection)] \(message)")
}

private func expect(_ condition: Bool, _ message: @autoclosure () -> String) {
    checkCount += 1
    if condition == false {
        fail(message())
    }
}

private func expectEqual<T: Equatable>(
    _ actual: T,
    _ expected: T,
    _ message: @autoclosure () -> String
) {
    checkCount += 1
    if actual != expected {
        fail("\(message()); actual \(actual), expected \(expected)")
    }
}

private func expectEqualScalar(
    _ actual: Unicode.Scalar?,
    _ expected: Unicode.Scalar,
    _ message: @autoclosure () -> String
) {
    checkCount += 1
    if actual != expected {
        fail("\(message()); actual \(formatOptionalScalar(actual)), expected \(unicode(expected))")
    }
}

private func scalar(_ value: UInt32) -> Unicode.Scalar {
    guard let scalar = Unicode.Scalar(value) else {
        fatalError("invalid Unicode scalar \(value)")
    }
    return scalar
}

private func hex(_ scalar: Unicode.Scalar) -> String {
    String(format: "0x%02X", scalar.value)
}

private func unicode(_ scalar: Unicode.Scalar) -> String {
    String(format: "U+%04X", scalar.value)
}

private func formatOptionalScalar(_ scalar: Unicode.Scalar?) -> String {
    scalar.map(unicode) ?? "nil"
}

private func loadSpecText() throws -> String {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if let explicitPath = arguments.first {
        return try String(contentsOfFile: explicitPath, encoding: .utf8)
    }
    return try ColeSebeolSpec.bundledText()
}

private func inputToken(_ token: String) -> ColeSebeolInput {
    switch token {
    case "Flush":
        return .flush
    case "Clear":
        return .clear
    case "Space":
        return .whitespace(" ")
    case "Delete":
        return .delete
    case "Backspace":
        return .backspace
    default:
        break
    }

    if token.hasPrefix("Command("), token.hasSuffix(")") {
        return .shortcut(modifiers: [.command], representativeKey: sourceKey(in: token))
    }
    if token.hasPrefix("Control("), token.hasSuffix(")") {
        return .shortcut(modifiers: [.control], representativeKey: sourceKey(in: token))
    }

    let scalars = Array(token.unicodeScalars)
    guard scalars.count == 1 else {
        fatalError("invalid test token: \(token)")
    }
    return .representativeKey(scalars[0])
}

private func sourceKey(in wrappedToken: String) -> Unicode.Scalar {
    guard let open = wrappedToken.firstIndex(of: "("),
          let close = wrappedToken.lastIndex(of: ")")
    else {
        fatalError("invalid shortcut token: \(wrappedToken)")
    }

    let scalars = Array(wrappedToken[wrappedToken.index(after: open)..<close].unicodeScalars)
    guard scalars.count == 1 else {
        fatalError("invalid shortcut key token: \(wrappedToken)")
    }
    return scalars[0]
}

private func run(_ sequence: String, layout: ColeSebeolLayout) -> ColeSebeolOutput {
    var engine = ColeSebeolEngine(layout: layout)
    var committedText = ""
    var forwardedActions: [HisleForwardedAction] = []

    for token in sequence.split(separator: " ").map(String.init) {
        let output = engine.process(inputToken(token))
        committedText += output.committedText
        forwardedActions += output.forwardedActions
    }

    return ColeSebeolOutput(
        committedText: committedText,
        markedText: engine.markedText,
        forwardedActions: forwardedActions
    )
}

private func expectVisible(_ sequence: String, _ expected: String, layout: ColeSebeolLayout) {
    let output = run(sequence + " Flush", layout: layout)
    expectEqual(
        output,
        ColeSebeolOutput(committedText: expected),
        "\(sequence) final visible output"
    )
}

private func expectState(
    _ sequence: String,
    committedText: String,
    markedText: String,
    layout: ColeSebeolLayout
) {
    let output = run(sequence, layout: layout)
    expectEqual(
        output.committedText,
        committedText,
        "\(sequence) committed text"
    )
    expectEqual(
        output.markedText,
        markedText,
        "\(sequence) marked text"
    )
    expectEqual(
        output.forwardedActions,
        [],
        "\(sequence) forwarded actions"
    )
}

private func expectForward(
    _ sequence: String,
    committedText: String,
    forwardedActions: [HisleForwardedAction],
    layout: ColeSebeolLayout
) {
    let output = run(sequence, layout: layout)
    expectEqual(
        output.committedText,
        committedText,
        "\(sequence) committed text before forwarding"
    )
    expectEqual(
        output.markedText,
        "",
        "\(sequence) marked text after forwarding"
    )
    expectEqual(
        output.forwardedActions,
        forwardedActions,
        "\(sequence) forwarded actions"
    )
}

private func checkParserDiagnostics() {
    let duplicateKey = ColeSebeolSpec.parse("""
    keyboard duplicate-key "Duplicate Key"
    key duplicate-key 0x61 U+1100
    key duplicate-key 0x61 U+1102
    """)
    expect(
        duplicateKey.issues.contains { $0.description.contains("duplicate key") },
        "parser reports duplicate key rows"
    )

    let duplicateUnderlyingKey = ColeSebeolSpec.parse("""
    keyboard duplicate-underlying "Duplicate Underlying"
    underlying-key duplicate-underlying 0x61 0x61
    underlying-key duplicate-underlying 0x61 0x62
    """)
    expect(
        duplicateUnderlyingKey.issues.contains { $0.description.contains("duplicate underlying-key") },
        "parser reports duplicate underlying-key rows"
    )

    let malformedRows = ColeSebeolSpec.parse("""
    keyboard malformed "Malformed"
    key malformed not-a-scalar U+1100
    combine malformed U+1100 U+110B
    positional-combine malformed U+1161 0x2F U+1169
    source-combine malformed too-long f U+116A
    """)
    let malformedDescriptions = malformedRows.issues.map(\.description).joined(separator: "\n")
    expect(malformedDescriptions.contains("malformed key row"), "parser reports malformed key rows")
    expect(malformedDescriptions.contains("malformed combine row"), "parser reports malformed combine rows")
    expect(
        malformedDescriptions.contains("malformed positional-combine row"),
        "parser reports malformed positional-combine rows"
    )
    expect(
        malformedDescriptions.contains("malformed source-combine row"),
        "parser reports malformed source-combine rows"
    )

    let metadata = ColeSebeolSpec.parse("""
    keyboard custom-layout "Custom Layout" map=custom-map combination=custom-combination
    """).layout
    expectEqual(metadata.keyboardID, "custom-layout", "parser preserves keyboard id")
    expectEqual(metadata.name, "Custom Layout", "parser preserves quoted keyboard name")
    expectEqual(metadata.mapID, "custom-map", "parser preserves map id")
    expectEqual(metadata.combinationID, "custom-combination", "parser preserves combination id")
}

private func checkBundledSpec(layout: ColeSebeolLayout, parseIssues: [ColeSebeolSpecIssue]) {
    let structuralIssues = layout.structuralIssues()
    expect(parseIssues.isEmpty, "bundled spec parse issues: \(parseIssues)")
    expect(structuralIssues.isEmpty, "bundled spec structural issues: \(structuralIssues)")

    expectEqual(layout.keyboardID, "cole-sebeol", "keyboard id")
    expectEqual(layout.name, "Cole Sebeol", "keyboard name")
    expectEqual(layout.mapID, "0", "keyboard map id")
    expectEqual(layout.combinationID, "default", "keyboard combination id")

    do {
        _ = try ColeSebeolSpec.bundledLayout()
        expect(true, "bundled layout loads without throwing")
    } catch {
        expect(false, "bundled layout should load without throwing: \(error.localizedDescription)")
    }
}

private func checkPrintableKeyMap(layout: ColeSebeolLayout) {
    expectEqual(
        layout.keyMappings.count,
        expectedColeSebeolOutputByRepresentative.count,
        "printable key map row count"
    )

    for value in ColeSebeolLayout.printableRepresentativeScalars {
        let representative = scalar(value)
        guard let expectedValue = expectedColeSebeolOutputByRepresentative[value] else {
            expect(false, "missing independent Cole Sebeol expectation for \(hex(representative))")
            continue
        }
        expectEqualScalar(
            layout.output(forRepresentativeKey: representative),
            scalar(expectedValue),
            "\(hex(representative)) Cole Sebeol output"
        )
    }
}

private func checkUnderlyingRomanMap(layout: ColeSebeolLayout) {
    expectEqual(
        layout.underlyingRomanMappings.count,
        expectedColemakUnderlyingByRepresentative.count,
        "underlying roman map row count"
    )

    for value in ColeSebeolLayout.printableRepresentativeScalars {
        let representative = scalar(value)
        guard let expectedValue = expectedColemakUnderlyingByRepresentative[value] else {
            expect(false, "missing independent Colemak expectation for \(hex(representative))")
            continue
        }
        expectEqualScalar(
            layout.underlyingRomanKey(forRepresentativeKey: representative),
            scalar(expectedValue),
            "\(hex(representative)) underlying roman output"
        )
    }
}

private func checkCompatibilityJamoMap(layout: ColeSebeolLayout) {
    expectEqual(
        layout.compatibilityJamoMappings.count,
        expectedCompatibilityJamo.count,
        "compatibility jamo row count"
    )

    for expected in expectedCompatibilityJamo.sorted(by: { $0.key < $1.key }) {
        expectEqualScalar(
            layout.compatibilityJamo(for: scalar(expected.key)),
            scalar(expected.value),
            "\(unicode(scalar(expected.key))) compatibility jamo"
        )
    }
}

private func checkCombinationTables(layout: ColeSebeolLayout) {
    expectEqual(
        layout.jamoCombinations.count,
        expectedJamoCombinations.count,
        "jamo combination row count"
    )
    for expected in expectedJamoCombinations {
        let first = scalar(expected.0)
        let second = scalar(expected.1)
        let result = scalar(expected.2)
        expectEqualScalar(
            layout.combinedJamo(first: first, second: second),
            result,
            "\(unicode(first)) + \(unicode(second)) combination"
        )
    }

    expectEqual(
        layout.positionalJamoCombinations.count,
        expectedPositionalJamoCombinations.count,
        "positional jamo combination row count"
    )
    for expected in expectedPositionalJamoCombinations {
        let first = scalar(expected.0)
        let representative = scalar(expected.1)
        let second = scalar(expected.2)
        let result = scalar(expected.3)
        expectEqualScalar(
            layout.positionalCombinedJamo(
                first: first,
                secondRepresentativeKey: representative,
                second: second
            ),
            result,
            "\(unicode(first)) + representative \(hex(representative)) \(unicode(second)) positional combination"
        )
    }

    expectEqual(
        layout.sourceKeyCombinations.count,
        expectedSourceKeyCombinations.count,
        "source-key combination row count"
    )
    for expected in expectedSourceKeyCombinations {
        expectEqualScalar(
            layout.sourceCombinedJamo(firstSourceKey: expected.0, secondSourceKey: expected.1),
            scalar(expected.2),
            "\(expected.0) + \(expected.1) source-key combination"
        )
    }

    let rejectedSourcePairs: [(Unicode.Scalar, Unicode.Scalar)] = [
        ("f", "v"),
        ("r", "v"),
        ("d", "v"),
        ("t", "b"),
        ("c", "b"),
        ("d", "b"),
        ("/", "t"),
        ("9", "f"),
    ]
    for pair in rejectedSourcePairs {
        expect(
            layout.sourceCombinedJamo(firstSourceKey: pair.0, secondSourceKey: pair.1) == nil,
            "source-key pair \(pair.0) \(pair.1) must not combine"
        )
    }
}

private func checkInputOutputTypes() {
    let shortcut = ColeSebeolInput.shortcut(modifiers: [.command], representativeKey: "e")
    let expectedShortcut = ColeSebeolInput.shortcut(modifiers: [.command], representativeKey: "e")
    expectEqual(shortcut, expectedShortcut, "ColeSebeolInput shortcut equality")

    let output = ColeSebeolOutput(
        committedText: "가",
        markedText: "",
        forwardedActions: [.shortcut(modifiers: [.command], key: "f")]
    )
    expectEqual(output.committedText, "가", "ColeSebeolOutput committed text")
    expectEqual(output.markedText, "", "ColeSebeolOutput marked text")
    expectEqual(
        output.forwardedActions,
        [.shortcut(modifiers: [.command], key: "f")],
        "ColeSebeolOutput forwarded actions"
    )
}

private func checkChoseongFirstPolicy(layout: ColeSebeolLayout) {
    let examples: [(String, String)] = [
        ("k f x", "각"),
        ("k x f", "각"),
        ("x k f", "ㄱ가"),
        ("f k x", "ㅏㄱㄱ"),
        ("k x k", "ㄱㄱㄱ"),
        ("k x .", "ㄱㄱ."),
        ("k x Space", "ㄱㄱ "),
    ]

    for example in examples {
        expectVisible(example.0, example.1, layout: layout)
    }
}

private func checkSlashNinePolicy(layout: ColeSebeolLayout) {
    let examples: [(String, String)] = [
        ("/ f", "ㅘ"),
        ("f /", "ㅘ"),
        ("v f", "ㅘ"),
        ("f v", "ㅏㅗ"),
        ("/ r", "ㅙ"),
        ("r /", "ㅙ"),
        ("v r", "ㅙ"),
        ("r v", "ㅐㅗ"),
        ("/ d", "ㅚ"),
        ("d /", "ㅚ"),
        ("v d", "ㅚ"),
        ("d v", "ㅣㅗ"),
        ("9 t", "ㅝ"),
        ("t 9", "ㅝ"),
        ("b t", "ㅝ"),
        ("t b", "ㅓㅜ"),
        ("9 c", "ㅞ"),
        ("c 9", "ㅞ"),
        ("b c", "ㅞ"),
        ("c b", "ㅔㅜ"),
        ("9 d", "ㅟ"),
        ("d 9", "ㅟ"),
        ("b d", "ㅟ"),
        ("d b", "ㅣㅜ"),
        ("k / f", "과"),
        ("k f /", "과"),
        ("k v f", "과"),
        ("k f v", "가ㅗ"),
        ("k / r", "괘"),
        ("k r /", "괘"),
        ("k v r", "괘"),
        ("k r v", "개ㅗ"),
        ("k / d", "괴"),
        ("k d /", "괴"),
        ("k v d", "괴"),
        ("k d v", "기ㅗ"),
        ("k 9 t", "궈"),
        ("k t 9", "궈"),
        ("k b t", "궈"),
        ("k t b", "거ㅜ"),
        ("k 9 c", "궤"),
        ("k c 9", "궤"),
        ("k b c", "궤"),
        ("k c b", "게ㅜ"),
        ("k 9 d", "귀"),
        ("k d 9", "귀"),
        ("k b d", "귀"),
        ("k d b", "기ㅜ"),
    ]

    for example in examples {
        expectVisible(example.0, example.1, layout: layout)
    }
}

private func checkWeakBelowPolicy(layout: ColeSebeolLayout) {
    let examples: [(String, String)] = [
        ("j k f", "까"),
        ("k j f", "까"),
        ("j f k", "아ㄱ"),
        ("k k f", "ㄱ가"),
        ("k l f", "짜"),
        ("l k f", "짜"),
        ("l l f", "ㅈ자"),
        ("l ; f", "빠"),
        ("; l f", "빠"),
        ("; ; f", "ㅂ바"),
        ("u i f", "따"),
        ("i u f", "따"),
        ("u u f", "ㄷ다"),
        ("n m f", "싸"),
        ("m n f", "싸"),
        ("n n f", "ㅅ사"),
        ("d f", "ㅒ"),
        ("f d", "ㅒ"),
        ("d g", "ㅢ"),
        ("g d", "ㅢ"),
        ("k d f", "걔"),
        ("k f d", "걔"),
        ("k d g", "긔"),
        ("k g d", "긔"),
        ("k e r", "계"),
        ("k r e", "계"),
        ("k f a s", "갆"),
        ("k f s a", "갆"),
        ("k f q w", "값"),
        ("k f w q", "값"),
        ("k f 3 2", "갖"),
        ("k f 2 3", "갖"),
        ("k f 1 2", "갂"),
        ("k f 2 1", "갂"),
    ]

    for example in examples {
        expectVisible(example.0, example.1, layout: layout)
    }
}

private func checkNoChoseongAndFlushBoundaries(layout: ColeSebeolLayout) {
    let examples: [(String, String)] = [
        ("k f r", "가ㅐ"),
        ("k f x z", "각ㅁ"),
        ("k x q f", "갃"),
        ("k x z", "ㄱㄱㅁ"),
        ("x q", "ㄳ"),
        ("f r", "ㅏㅐ"),
        ("f x", "ㅏㄱ"),
        ("x f", "ㄱㅏ"),
        ("/ f k f", "ㅘ가"),
        ("f / k f", "ㅘ가"),
        ("k f x f", "각ㅏ"),
        ("k f x /", "각ㅗ"),
        ("k x f /", "각ㅗ"),
        ("k 가", "ㄱ가"),
    ]

    for example in examples {
        expectVisible(example.0, example.1, layout: layout)
    }
}

private func checkMarkedTextAndBackspace(layout: ColeSebeolLayout) {
    expectState("k", committedText: "", markedText: "ㄱ", layout: layout)
    expectState("k x", committedText: "", markedText: "ㄱㄱ", layout: layout)
    expectState("k f", committedText: "", markedText: "가", layout: layout)
    expectState("k x f", committedText: "", markedText: "각", layout: layout)
    expectState("/ f", committedText: "", markedText: "ㅘ", layout: layout)
    expectState("f /", committedText: "", markedText: "ㅘ", layout: layout)
    expectState("k f x f", committedText: "각", markedText: "ㅏ", layout: layout)

    let examples: [(String, String)] = [
        ("k Backspace", ""),
        ("k f Backspace", "ㄱ"),
        ("k x Backspace f", "가"),
        ("k f x Backspace", "가"),
        ("/ f Backspace", "ㅗ"),
        ("f / Backspace", "ㅏ"),
        ("v f Backspace", "ㅗ"),
    ]

    for example in examples {
        expectVisible(example.0, example.1, layout: layout)
    }
}

private func checkForwardingBoundaries(layout: ColeSebeolLayout) {
    expectForward("k f Delete", committedText: "가", forwardedActions: [.delete], layout: layout)
    expectForward("k x Delete", committedText: "ㄱㄱ", forwardedActions: [.delete], layout: layout)
    expectForward("Delete", committedText: "", forwardedActions: [.delete], layout: layout)
    expectForward("Backspace", committedText: "", forwardedActions: [.backspace], layout: layout)
    expectForward(
        "k Command(e)",
        committedText: "ㄱ",
        forwardedActions: [.shortcut(modifiers: [.command], key: "f")],
        layout: layout
    )
    expectForward(
        "k f Command(e)",
        committedText: "가",
        forwardedActions: [.shortcut(modifiers: [.command], key: "f")],
        layout: layout
    )
    expectForward(
        "Command(n)",
        committedText: "",
        forwardedActions: [.shortcut(modifiers: [.command], key: "k")],
        layout: layout
    )
    expectForward(
        "Control(e)",
        committedText: "",
        forwardedActions: [.shortcut(modifiers: [.control], key: "f")],
        layout: layout
    )

    var engine = ColeSebeolEngine(layout: layout)
    let output = engine.process(.shortcut(modifiers: [.option, .shift], representativeKey: "e"))
    expectEqual(
        output,
        ColeSebeolOutput(
            forwardedActions: [.shortcut(modifiers: [.option, .shift], key: "f")]
        ),
        "direct shortcut preserves option and shift modifiers while forwarding underlying key"
    )

    let fallback = engine.process(.shortcut(modifiers: [.command], representativeKey: "가"))
    expectEqual(
        fallback,
        ColeSebeolOutput(forwardedActions: [.shortcut(modifiers: [.command], key: "가")]),
        "shortcut with unknown representative key falls back to the original scalar"
    )
}

private func checkClearWhitespaceAndPrintableBoundaries(layout: ColeSebeolLayout) {
    expectState("Flush", committedText: "", markedText: "", layout: layout)
    expectState("Clear", committedText: "", markedText: "", layout: layout)
    expectState("k f Clear", committedText: "", markedText: "", layout: layout)
    expectState("k f Space x", committedText: "가 ", markedText: "ㄱ", layout: layout)

    let examples: [(String, String)] = [
        ("k f .", "가."),
        ("k f H", "가0"),
        ("k f ~", "가~"),
        ("k f \"", "가\""),
        ("k f {", "가{"),
        ("k f <", "가<"),
        ("k f N", "가:"),
        ("k f M", "가;"),
        ("k f ?", "가!"),
        ("f Space", "ㅏ "),
        ("k f Clear x", "ㄱ"),
    ]

    for example in examples {
        expectVisible(example.0, example.1, layout: layout)
    }
}

do {
    let specText = try loadSpecText()
    let parseResult = ColeSebeolSpec.parse(specText)
    let layout = parseResult.layout

    try section("parser diagnostics") {
        checkParserDiagnostics()
    }
    try section("bundled spec") {
        checkBundledSpec(layout: layout, parseIssues: parseResult.issues)
    }
    try section("printable key map") {
        checkPrintableKeyMap(layout: layout)
    }
    try section("underlying roman map") {
        checkUnderlyingRomanMap(layout: layout)
    }
    try section("compatibility jamo map") {
        checkCompatibilityJamoMap(layout: layout)
    }
    try section("combination tables") {
        checkCombinationTables(layout: layout)
    }
    try section("input and output types") {
        checkInputOutputTypes()
    }
    try section("choseong-first automata") {
        checkChoseongFirstPolicy(layout: layout)
    }
    try section("slash-nine automata") {
        checkSlashNinePolicy(layout: layout)
    }
    try section("weak-below automata") {
        checkWeakBelowPolicy(layout: layout)
    }
    try section("no-choseong and flush boundaries") {
        checkNoChoseongAndFlushBoundaries(layout: layout)
    }
    try section("marked text and backspace") {
        checkMarkedTextAndBackspace(layout: layout)
    }
    try section("forwarding boundaries") {
        checkForwardingBoundaries(layout: layout)
    }
    try section("clear whitespace and printable boundaries") {
        checkClearWhitespaceAndPrintableBoundaries(layout: layout)
    }
} catch {
    fail(error.localizedDescription)
}

if failures.isEmpty {
    print("Cole Sebeol core contract check passed (\(checkCount) checks).")
} else {
    for failure in failures {
        fputs("error: \(failure)\n", stderr)
    }
    exit(1)
}
