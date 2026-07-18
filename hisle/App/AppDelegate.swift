import Cocoa
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "hooreique.inputmethod.hisle", category: "App")
    private let hisleCore = HisleCoreBootstrap.loadOrCrash()
    private let inputMethodRuntime = InputMethodRuntime.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "NSApplicationCrashOnExceptions": true
        ])

        let busyAppsSnapshot = inputMethodRuntime.busyAppsSnapshot
        let configurationPath = busyAppsSnapshot.configurationFileURL.path
        let configurationMessage = "busy apps configuration: path=\(configurationPath) " +
            "entries=\(busyAppsSnapshot.bundleIdentifiers.count)"
        logger.notice("\(configurationMessage, privacy: .public)")
        if let loadErrorDescription = busyAppsSnapshot.loadErrorDescription {
            let readFailureMessage = "busy apps configuration read failed: path=\(configurationPath) " +
                "error=\(loadErrorDescription)"
            logger.error("\(readFailureMessage, privacy: .public)")
        }

        _ = inputMethodRuntime.inputMethodServer
        logger.notice("application launched")
        logger.notice("core initialized: \(self.hisleCore.logSummary, privacy: .public)")
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
