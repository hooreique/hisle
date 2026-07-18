import Foundation
import InputMethodKit
import os

final class InputMethodServer {
    let server: IMKServer
    private let logger = Logger(subsystem: "hooreique.inputmethod.hisle", category: "InputMethodServer")

    init(bundle: Bundle = .main) {
        guard let connectionName = bundle.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String else {
            fatalError("Missing InputMethodConnectionName in Info.plist")
        }

        server = IMKServer(name: connectionName, bundleIdentifier: bundle.bundleIdentifier)
        let bundleID = bundle.bundleIdentifier ?? ""
        logger.notice(
            "server started: connection=\(connectionName, privacy: .public) bundle=\(bundleID, privacy: .public)"
        )
    }
}
