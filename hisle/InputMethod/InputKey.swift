import Cocoa
import HisleCore

enum InputKeyAction {
    case selectInputMode(HisleInputMode, handled: Bool)
    case forwardToHost
    case whitespace(Unicode.Scalar)
    case deleteBackward
    case representativeKey(Unicode.Scalar)
    case fallbackText(String)
    case ignored
}

struct InputKeyClassifier {
    func classify(
        text: String?,
        keyCode: UInt16,
        modifiers flags: NSEvent.ModifierFlags
    ) -> InputKeyAction {
        let modifiers = flags.subtracting(.capsLock)

        if keyCode == KeyCode.escape {
            return .selectInputMode(.roman, handled: false)
        }

        if modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.option) {
            return .forwardToHost
        }

        switch keyCode {
        case KeyCode.space:
            return .whitespace(" ")
        case KeyCode.deleteBackward:
            return .deleteBackward
        case KeyCode.deleteForward, KeyCode.returnKey, KeyCode.tab:
            return .forwardToHost
        default:
            break
        }

        if KeyCode.forwardedNonPrintableKeys.contains(keyCode) {
            return .forwardToHost
        }

        if let representativeKey = RepresentativeKeyMap.scalar(
            forKeyCode: keyCode,
            shifted: modifiers.contains(.shift)
        ) {
            return .representativeKey(representativeKey)
        }

        guard let text else {
            return .ignored
        }
        return .fallbackText(text)
    }
}

enum KeyCode {
    static let returnKey: UInt16 = 36
    static let tab: UInt16 = 48
    static let space: UInt16 = 49
    static let deleteBackward: UInt16 = 51
    static let escape: UInt16 = 53
    static let leftShift: UInt16 = 56
    static let rightShift: UInt16 = 60
    static let deleteForward: UInt16 = 117

    static let keyF1: UInt16 = 122
    static let keyF2: UInt16 = 120
    static let keyF3: UInt16 = 99
    static let keyF4: UInt16 = 118
    static let keyF5: UInt16 = 96
    static let keyF6: UInt16 = 97
    static let keyF7: UInt16 = 98
    static let keyF8: UInt16 = 100
    static let keyF9: UInt16 = 101
    static let keyF10: UInt16 = 109
    static let keyF11: UInt16 = 103
    static let keyF12: UInt16 = 111
    static let home: UInt16 = 115
    static let end: UInt16 = 119
    static let pageUp: UInt16 = 116
    static let pageDown: UInt16 = 121
    static let leftArrow: UInt16 = 123
    static let rightArrow: UInt16 = 124
    static let downArrow: UInt16 = 125
    static let upArrow: UInt16 = 126

    static let forwardedNonPrintableKeys: Set<UInt16> = [
        keyF1, keyF2, keyF3, keyF4, keyF5, keyF6, keyF7, keyF8, keyF9, keyF10, keyF11, keyF12,
        home, end, pageUp, pageDown,
        leftArrow, rightArrow, downArrow, upArrow
    ]
}

enum RepresentativeKeyMap {
    private static let unshifted: [UInt16: Unicode.Scalar] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
        8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
        16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 37: "l",
        38: "j", 39: "'", 40: "k", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "n", 46: "m", 47: ".", 50: "`"
    ]

    private static let shifted: [UInt16: Unicode.Scalar] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "!", 19: "@", 20: "#", 21: "$", 22: "^",
        23: "%", 24: "+", 25: "(", 26: "&", 27: "_", 28: "*", 29: ")",
        30: "}", 31: "O", 32: "U", 33: "{", 34: "I", 35: "P", 37: "L",
        38: "J", 39: "\"", 40: "K", 41: ":", 42: "|", 43: "<", 44: "?",
        45: "N", 46: "M", 47: ">", 50: "~"
    ]

    static func scalar(forKeyCode keyCode: UInt16, shifted isShifted: Bool) -> Unicode.Scalar? {
        if isShifted {
            return shifted[keyCode]
        }
        return unshifted[keyCode]
    }
}
