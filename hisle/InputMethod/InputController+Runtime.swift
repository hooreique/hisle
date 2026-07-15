import Foundation
import HisleCore
import os

extension InputController {
    static func makeEngine() -> ColeSebeolEngine {
        do {
            return try ColeSebeolEngine()
        } catch {
            fatalError("Failed to initialize ColeSebeolEngine: \(error)")
        }
    }

    func logRuntimeIdentity(stage: String) {
        let clientBundleIdentifier = self.clientBundleIdentifier ?? "unknown"
        let message = [
            "controller runtime stage=\(stage)",
            "buildProfile=\(Self.buildProfile)",
            "appVersion=\(Self.bundleInfoValue(for: "CFBundleShortVersionString"))",
            "coreVersion=\(HisleCore.version)",
            "build=\(Self.bundleInfoValue(for: "CFBundleVersion"))",
            "pid=\(ProcessInfo.processInfo.processIdentifier)",
            "bundle=\(Bundle.main.bundleURL.path)",
            "clientBundleIdentifier=\(clientBundleIdentifier)",
            "profile=\(hostProfile.rawValue)",
            "replacementPolicy=\(replacementPolicyID)"
        ].joined(separator: " ")
        logger.notice("\(message, privacy: .public)")
    }

    private static func bundleInfoValue(for key: String) -> String {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty else {
            return "unknown"
        }
        return value
    }
}
