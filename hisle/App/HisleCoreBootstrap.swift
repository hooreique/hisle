import Darwin
import Foundation
import HisleCore

struct HisleCoreBootstrap {
    let version: String
    let layout: ColeSebeolLayout

    init() throws {
        version = HisleCore.version
        layout = try ColeSebeolSpec.bundledLayout()
        _ = ColeSebeolEngine(layout: layout)
    }

    var logSummary: String {
        [
            "version=\(version)",
            "keyboard=\(layout.keyboardID)",
            "name=\(layout.name)",
            "map=\(layout.mapID)",
            "combination=\(layout.combinationID)",
            "keys=\(layout.keyMappings.count)",
            "underlyingKeys=\(layout.underlyingRomanMappings.count)"
        ].joined(separator: " ")
    }

    static func loadOrCrash() -> HisleCoreBootstrap {
        do {
            return try HisleCoreBootstrap()
        } catch {
            fatalError("Failed to initialize HisleCore: \(error)")
        }
    }

    static func runCommandLineCheck() -> Never {
        do {
            let bootstrap = try HisleCoreBootstrap()
            print("hisle-core initialized: \(bootstrap.logSummary)")
            exit(EXIT_SUCCESS)
        } catch {
            let message = "hisle-core initialization failed: \(error)\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(EXIT_FAILURE)
        }
    }
}
