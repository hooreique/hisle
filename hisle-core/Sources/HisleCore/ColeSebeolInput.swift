public enum HisleInputModifier: String, CaseIterable, Hashable, Sendable {
    case command
    case control
    case option
    case shift
}

public enum ColeSebeolInput: Equatable, Sendable {
    case representativeKey(Unicode.Scalar)
    case whitespace(Unicode.Scalar)
    case flush
    case clear
    case delete
    case backspace
    case shortcut(modifiers: Set<HisleInputModifier>, representativeKey: Unicode.Scalar)
}

public enum HisleForwardedAction: Equatable, Sendable {
    case delete
    case backspace
    case shortcut(modifiers: Set<HisleInputModifier>, key: Unicode.Scalar)
}

public struct ColeSebeolOutput: Equatable, Sendable {
    public let committedText: String
    public let markedText: String
    public let forwardedActions: [HisleForwardedAction]

    public init(
        committedText: String = "",
        markedText: String = "",
        forwardedActions: [HisleForwardedAction] = []
    ) {
        self.committedText = committedText
        self.markedText = markedText
        self.forwardedActions = forwardedActions
    }

    public static let empty = ColeSebeolOutput()
}
