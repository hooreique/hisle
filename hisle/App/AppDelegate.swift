import Cocoa
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "hooreique.inputmethod.hisle", category: "App")
    private let hisleCore = HisleCoreBootstrap.loadOrCrash()

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "NSApplicationCrashOnExceptions": true,
        ])

        _ = InputMethodServer.shared
        logger.notice("application launched")
        logger.notice("core initialized: \(self.hisleCore.logSummary, privacy: .public)")
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
