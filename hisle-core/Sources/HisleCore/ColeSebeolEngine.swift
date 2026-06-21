public struct ColeSebeolEngine: Sendable {
    public let layout: ColeSebeolLayout

    private var composition = ColeSebeolComposition()
    private var activeInputs: [ColeSebeolJamoInput] = []

    public init(layout: ColeSebeolLayout) {
        self.layout = layout
    }

    public init() throws {
        self.init(layout: try ColeSebeolSpec.bundledLayout())
    }

    public mutating func process(_ input: ColeSebeolInput) -> ColeSebeolOutput {
        switch input {
        case .representativeKey(let representativeKey):
            return processRepresentativeKey(representativeKey)
        case .whitespace(let scalar):
            return flushThenCommit(String(scalar))
        case .flush:
            return ColeSebeolOutput(committedText: flushActiveComposition())
        case .clear:
            clearActiveComposition()
            return .empty
        case .delete:
            return flushThenForward(.delete)
        case .backspace:
            return processBackspace()
        case .shortcut(let modifiers, let representativeKey):
            let forwardedKey = layout.underlyingRomanKey(forRepresentativeKey: representativeKey) ?? representativeKey
            return flushThenForward(.shortcut(modifiers: modifiers, key: forwardedKey))
        }
    }

    public var markedText: String {
        visibleText(for: composition)
    }

    private mutating func processRepresentativeKey(_ representativeKey: Unicode.Scalar) -> ColeSebeolOutput {
        guard let scalar = layout.output(forRepresentativeKey: representativeKey) else {
            return flushThenCommit(String(representativeKey))
        }

        guard let kind = ColeSebeolJamoKind(scalar: scalar) else {
            return flushThenCommit(String(scalar))
        }

        let committedText = processJamoInput(
            ColeSebeolJamoInput(kind: kind, scalar: scalar, sourceKey: representativeKey)
        )
        return ColeSebeolOutput(committedText: committedText, markedText: markedText)
    }

    private mutating func processBackspace() -> ColeSebeolOutput {
        guard activeInputs.isEmpty == false else {
            return ColeSebeolOutput(forwardedActions: [.backspace])
        }

        activeInputs.removeLast()
        rebuildCompositionFromActiveInputs()
        return ColeSebeolOutput(markedText: markedText)
    }

    private mutating func processJamoInput(_ input: ColeSebeolJamoInput) -> String {
        if composition.isEmpty {
            startComposition(with: input)
            return ""
        }

        if incorporate(input) {
            activeInputs.append(input)
            return ""
        }

        let committedText = flushActiveComposition()
        startComposition(with: input)
        return committedText
    }

    private mutating func incorporate(_ input: ColeSebeolJamoInput) -> Bool {
        switch input.kind {
        case .choseong:
            return incorporateChoseong(input)
        case .jungseong:
            return incorporateJungseong(input)
        case .jongseong:
            return incorporateJongseong(input)
        }
    }

    private mutating func incorporateChoseong(_ input: ColeSebeolJamoInput) -> Bool {
        guard composition.jungseong == nil, composition.jongseong == nil else {
            return false
        }

        if composition.choseong == nil {
            composition.set(input.slot, for: .choseong)
            return true
        }

        return combineExistingSlot(.choseong, with: input)
    }

    private mutating func incorporateJungseong(_ input: ColeSebeolJamoInput) -> Bool {
        if composition.choseong == nil {
            if composition.jongseong != nil {
                return false
            }
            if composition.jungseong == nil {
                composition.set(input.slot, for: .jungseong)
                return true
            }
            return combineExistingSlot(.jungseong, with: input)
        }

        if composition.jungseong == nil {
            composition.set(input.slot, for: .jungseong)
            return true
        }

        if composition.jongseong != nil {
            return false
        }

        return combineExistingSlot(.jungseong, with: input)
    }

    private mutating func incorporateJongseong(_ input: ColeSebeolJamoInput) -> Bool {
        if composition.choseong == nil {
            if composition.jungseong != nil {
                return false
            }
            if composition.jongseong == nil {
                composition.set(input.slot, for: .jongseong)
                return true
            }
            return combineExistingSlot(.jongseong, with: input)
        }

        if composition.jongseong == nil {
            composition.set(input.slot, for: .jongseong)
            return true
        }

        return combineExistingSlot(.jongseong, with: input)
    }

    private mutating func combineExistingSlot(
        _ kind: ColeSebeolJamoKind,
        with input: ColeSebeolJamoInput
    ) -> Bool {
        guard var slot = composition.slot(for: kind),
              let result = combinedScalar(kind: kind, existing: slot, input: input)
        else {
            return false
        }

        slot.scalar = result
        slot.sourceKeys.append(input.sourceKey)
        composition.set(slot, for: kind)
        return true
    }

    private func combinedScalar(
        kind: ColeSebeolJamoKind,
        existing: ColeSebeolJamoSlot,
        input: ColeSebeolJamoInput
    ) -> Unicode.Scalar? {
        if kind == .jungseong {
            if existing.sourceKeys.count == 1,
               let result = layout.sourceCombinedJamo(
                firstSourceKey: existing.sourceKeys[0],
                secondSourceKey: input.sourceKey
               ),
               ColeSebeolJamoKind(scalar: result) == kind {
                return result
            }

            if let result = layout.positionalCombinedJamo(
                first: existing.scalar,
                secondRepresentativeKey: input.sourceKey,
                second: input.scalar
            ),
               ColeSebeolJamoKind(scalar: result) == kind {
                return result
            }
        }

        guard let result = layout.combinedJamo(first: existing.scalar, second: input.scalar),
              ColeSebeolJamoKind(scalar: result) == kind
        else {
            return nil
        }
        return result
    }

    private mutating func startComposition(with input: ColeSebeolJamoInput) {
        composition = ColeSebeolComposition()
        activeInputs = [input]
        composition.set(input.slot, for: input.kind)
    }

    private mutating func flushThenCommit(_ text: String) -> ColeSebeolOutput {
        ColeSebeolOutput(committedText: flushActiveComposition() + text)
    }

    private mutating func flushThenForward(_ action: HisleForwardedAction) -> ColeSebeolOutput {
        ColeSebeolOutput(
            committedText: flushActiveComposition(),
            forwardedActions: [action]
        )
    }

    private mutating func flushActiveComposition() -> String {
        let text = visibleText(for: composition)
        clearActiveComposition()
        return text
    }

    private mutating func clearActiveComposition() {
        composition = ColeSebeolComposition()
        activeInputs = []
    }

    private mutating func rebuildCompositionFromActiveInputs() {
        let inputs = activeInputs
        composition = ColeSebeolComposition()
        activeInputs = []

        for input in inputs {
            let committedText = processJamoInput(input)
            precondition(committedText.isEmpty, "active input stack must not contain a flush boundary")
        }
    }

    private func visibleText(for composition: ColeSebeolComposition) -> String {
        if let choseong = composition.choseong?.scalar,
           let jungseong = composition.jungseong?.scalar,
           let syllable = composeSyllable(choseong: choseong, jungseong: jungseong, jongseong: composition.jongseong?.scalar) {
            return String(syllable)
        }

        return composition.order
            .compactMap { composition.slot(for: $0)?.scalar }
            .map { standaloneJamoText(for: $0) }
            .joined()
    }

    private func standaloneJamoText(for scalar: Unicode.Scalar) -> String {
        String(layout.compatibilityJamo(for: scalar) ?? scalar)
    }
}

private enum ColeSebeolJamoKind: Hashable, Sendable {
    case choseong
    case jungseong
    case jongseong

    init?(scalar: Unicode.Scalar) {
        switch scalar.value {
        case 0x1100...0x115F:
            self = .choseong
        case 0x1160...0x11A7:
            self = .jungseong
        case 0x11A8...0x11FF:
            self = .jongseong
        default:
            return nil
        }
    }
}

private struct ColeSebeolJamoInput: Sendable {
    let kind: ColeSebeolJamoKind
    let scalar: Unicode.Scalar
    let sourceKey: Unicode.Scalar

    var slot: ColeSebeolJamoSlot {
        ColeSebeolJamoSlot(scalar: scalar, sourceKeys: [sourceKey])
    }
}

private struct ColeSebeolJamoSlot: Sendable {
    var scalar: Unicode.Scalar
    var sourceKeys: [Unicode.Scalar]
}

private struct ColeSebeolComposition: Sendable {
    var choseong: ColeSebeolJamoSlot?
    var jungseong: ColeSebeolJamoSlot?
    var jongseong: ColeSebeolJamoSlot?
    var order: [ColeSebeolJamoKind] = []

    var isEmpty: Bool {
        choseong == nil && jungseong == nil && jongseong == nil
    }

    func slot(for kind: ColeSebeolJamoKind) -> ColeSebeolJamoSlot? {
        switch kind {
        case .choseong:
            return choseong
        case .jungseong:
            return jungseong
        case .jongseong:
            return jongseong
        }
    }

    mutating func set(_ slot: ColeSebeolJamoSlot, for kind: ColeSebeolJamoKind) {
        if self.slot(for: kind) == nil, order.contains(kind) == false {
            order.append(kind)
        }

        switch kind {
        case .choseong:
            choseong = slot
        case .jungseong:
            jungseong = slot
        case .jongseong:
            jongseong = slot
        }
    }
}

private let choseongIndexes: [UInt32: UInt32] = [
    0x1100: 0, 0x1101: 1, 0x1102: 2, 0x1103: 3, 0x1104: 4,
    0x1105: 5, 0x1106: 6, 0x1107: 7, 0x1108: 8, 0x1109: 9,
    0x110A: 10, 0x110B: 11, 0x110C: 12, 0x110D: 13, 0x110E: 14,
    0x110F: 15, 0x1110: 16, 0x1111: 17, 0x1112: 18,
]

private func composeSyllable(
    choseong: Unicode.Scalar,
    jungseong: Unicode.Scalar,
    jongseong: Unicode.Scalar?
) -> Unicode.Scalar? {
    guard let choseongIndex = choseongIndexes[choseong.value],
          (0x1161...0x1175).contains(jungseong.value)
    else {
        return nil
    }

    let jungseongIndex = jungseong.value - 0x1161
    let jongseongIndex: UInt32
    if let jongseong {
        guard (0x11A8...0x11C2).contains(jongseong.value) else {
            return nil
        }
        jongseongIndex = jongseong.value - 0x11A7
    } else {
        jongseongIndex = 0
    }

    return Unicode.Scalar(0xAC00 + ((choseongIndex * 21) + jungseongIndex) * 28 + jongseongIndex)
}
