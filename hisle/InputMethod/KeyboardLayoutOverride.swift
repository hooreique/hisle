import Carbon
import Foundation
import InputMethodKit
import os

enum KeyboardLayoutOverride {
    private static let colemakInputSourceID = "com.apple.keylayout.Colemak"
    private static let logger = Logger(
        subsystem: "hooreique.inputmethod.hisle",
        category: "KeyboardLayoutOverride"
    )

    @discardableResult
    static func installColemak(for client: Any?, logSuccess: Bool = false) -> Bool {
        if let textInput = client as? IMKTextInput {
            textInput.overrideKeyboard(withKeyboardNamed: colemakInputSourceID)
            if logSuccess {
                logger.notice("requested keyboard layout override via IMK client: \(colemakInputSourceID, privacy: .public)")
            }
            return true
        }

        return installColemakThroughTIS(logSuccess: logSuccess)
    }

    @discardableResult
    static func installColemakThroughTIS(logSuccess: Bool = false) -> Bool {
        let filter = [kTISPropertyInputSourceID as String: colemakInputSourceID] as CFDictionary
        let sources = TISCreateInputSourceList(filter, true).takeRetainedValue() as NSArray

        guard sources.count > 0 else {
            logger.error("could not find keyboard layout source: \(colemakInputSourceID, privacy: .public)")
            return false
        }

        let source = sources[0] as! TISInputSource
        let status = TISSetInputMethodKeyboardLayoutOverride(source)
        guard status == noErr else {
            logger.error("could not set keyboard layout override through TIS: OSStatus \(status, privacy: .public)")
            return false
        }

        if logSuccess {
            logger.notice("set keyboard layout override through TIS: \(colemakInputSourceID, privacy: .public)")
        }
        return true
    }
}
