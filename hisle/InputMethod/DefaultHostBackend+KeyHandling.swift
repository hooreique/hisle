import Foundation
import HisleCore

extension DefaultHostBackend {
    func handleHangulFallbackText(_ text: String, client sender: Any?) -> Bool {
        DefaultHostFallbackProcessor.process(Array(text.unicodeScalars)) { scalar in
            if scalar == " " {
                return process(.whitespace(scalar), client: sender)
            } else if scalar.properties.isWhitespace && !CharacterSet.controlCharacters.contains(scalar) {
                return process(.whitespace(scalar), client: sender)
            } else if ColeSebeolLayout.printableRepresentativeScalars.contains(scalar.value) {
                return process(.representativeKey(scalar), client: sender)
            }
            return nil
        }
    }
}
