import Foundation
import InputMethodKit
import os

final class InputMethodServer {
    static let shared = InputMethodServer()

    let server: IMKServer
    private let logger = Logger(subsystem: "hooreique.inputmethod.hisle", category: "InputMethodServer")

    private init(bundle: Bundle = .main) {
        guard let connectionName = bundle.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String else {
            fatalError("Missing InputMethodConnectionName in Info.plist")
        }

        server = IMKServer(name: connectionName, bundleIdentifier: bundle.bundleIdentifier)
        NSLog("hisle server started: connection=\(connectionName) bundle=\(bundle.bundleIdentifier ?? "")")
        logger.notice("server started: connection=\(connectionName, privacy: .public) bundle=\(bundle.bundleIdentifier ?? "", privacy: .public)")
    }
}
