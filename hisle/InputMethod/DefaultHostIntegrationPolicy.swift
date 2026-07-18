import Foundation

enum DefaultMarkedTextAction: Equatable {
    case update(String)
    case clear
    case none
}

struct DefaultHostApplyPlan: Equatable {
    let committedText: String?
    let needsMarkedTextContinuation: Bool
    let markedTextAction: DefaultMarkedTextAction

    static func make(
        committedText: String,
        markedText: String,
        wasMarkedTextActive: Bool
    ) -> DefaultHostApplyPlan {
        let committedText = committedText.isEmpty ? nil : committedText
        let markedTextAction: DefaultMarkedTextAction
        if !markedText.isEmpty {
            markedTextAction = .update(markedText)
        } else if committedText == nil, wasMarkedTextActive {
            markedTextAction = .clear
        } else {
            markedTextAction = .none
        }

        return DefaultHostApplyPlan(
            committedText: committedText,
            needsMarkedTextContinuation: committedText != nil && !markedText.isEmpty,
            markedTextAction: markedTextAction
        )
    }
}

enum DefaultHostFallbackProcessor {
    static func process(
        _ scalars: [Unicode.Scalar],
        scalarHandler: (Unicode.Scalar) -> Bool?
    ) -> Bool {
        var handled = false

        for scalar in scalars {
            guard let scalarHandled = scalarHandler(scalar) else {
                continue
            }
            handled = scalarHandled || handled
        }

        return handled
    }
}
