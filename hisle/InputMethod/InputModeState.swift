import Foundation

enum HisleInputMode: CustomStringConvertible {
    case hangul
    case roman

    var description: String {
        switch self {
        case .hangul:
            return "hangul"
        case .roman:
            return "roman"
        }
    }
}

enum HisleInputModeState {
    static let suiteName = "hooreique.inputmethod.hisle"
    static let key = "inputMode"

    static func write(_ mode: HisleInputMode) {
        let domain = suiteName as CFString
        CFPreferencesSetAppValue(key as CFString, mode.description as CFString, domain)
        CFPreferencesAppSynchronize(domain)
    }
}
