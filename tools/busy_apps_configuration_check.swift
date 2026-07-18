import Darwin
import Foundation

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

private struct ExpectedReadError: LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }
}

private struct InitializationScenario {
    let environment: [String: String]
    let fallbackHomeDirectory: URL
    let expectedURL: URL
}

@main
// swiftlint:disable:next type_body_length
private enum BusyAppsConfigurationCheck {
    private static var checkCount = 0

    static func main() throws {
        try checkXDGConfigurationHomePrecedence()
        try checkEmptyXDGConfigurationHomeFallsBackToHome()
        try checkMissingHomeUsesFallback()
        try checkParsingAndExactMembership()
        try checkEmptyFile()
        try checkMissingFileDoesNotCreateConfiguration()
        try checkUnreadableAndInvalidUTF8Failures()
        try checkInitializerCreatesResolvedFiles()
        try checkInitializerPreservesExistingFile()
        try checkInitializerAcceptsRegularFileSymbolicLink()
        try checkInitializerRejectsNonRegularDestinations()
        try checkSnapshotDoesNotReload()

        print("Busy apps configuration check passed \(checkCount) checks.")
    }

    private static func checkXDGConfigurationHomePrecedence() throws {
        var readPath: String?
        let snapshot = BusyAppsSnapshot.load(
            environment: [
                "XDG_CONFIG_HOME": "/tmp/hisle-xdg",
                "HOME": "/tmp/hisle-home"
            ],
            reader: { url in
                readPath = url.path
                return "app.from.xdg\n"
            }
        )

        try require(
            readPath == "/tmp/hisle-xdg/hisle/busy-apps.txt",
            "nonempty XDG_CONFIG_HOME did not take precedence: \(readPath ?? "<nil>")"
        )
        try require(snapshot.contains(bundleIdentifier: "app.from.xdg"), "XDG snapshot lost its entry")
        checkCount += 1
    }

    private static func checkEmptyXDGConfigurationHomeFallsBackToHome() throws {
        var readPath: String?
        _ = BusyAppsSnapshot.load(
            environment: [
                "XDG_CONFIG_HOME": "",
                "HOME": "/tmp/hisle-home"
            ],
            reader: { url in
                readPath = url.path
                return ""
            }
        )

        try require(
            readPath == "/tmp/hisle-home/.config/hisle/busy-apps.txt",
            "empty XDG_CONFIG_HOME did not fall back to HOME: \(readPath ?? "<nil>")"
        )
        checkCount += 1
    }

    private static func checkMissingHomeUsesFallback() throws {
        let fallbackHomeDirectory = URL(fileURLWithPath: "/tmp/hisle-fallback-home", isDirectory: true)
        for environment in [[:], ["HOME": ""]] {
            let url = BusyAppsSnapshot.configurationFileURL(
                environment: environment,
                fallbackHomeDirectory: fallbackHomeDirectory
            )

            try require(
                url.path == "/tmp/hisle-fallback-home/.config/hisle/busy-apps.txt",
                "missing or empty HOME did not use the fallback home directory: \(url.path)"
            )
        }
        checkCount += 1
    }

    private static func checkParsingAndExactMembership() throws {
        let contents = """

              # leading whitespace before a comment
            com.google.Chrome
            com.microsoft.teams2\u{20}\u{20}\u{20}
            com.google.Chrome
            COM.GOOGLE.Chrome
            com.example.App#not-a-comment

            """
        let snapshot = BusyAppsSnapshot.load(
            environment: ["HOME": "/tmp/hisle-home"],
            reader: { _ in contents }
        )

        try require(snapshot.bundleIdentifiers.count == 4, "comments, whitespace, or duplicates were not ignored")
        try require(snapshot.contains(bundleIdentifier: "com.google.Chrome"), "trimmed identifier is missing")
        try require(snapshot.contains(bundleIdentifier: "com.microsoft.teams2"), "trailing whitespace was retained")
        try require(snapshot.contains(bundleIdentifier: "COM.GOOGLE.Chrome"), "case-distinct identifier is missing")
        try require(
            snapshot.contains(bundleIdentifier: "com.example.App#not-a-comment"),
            "an inline # was treated as a comment"
        )
        try require(!snapshot.contains(bundleIdentifier: "com.google.chrome"), "membership was not case-sensitive")
        try require(!snapshot.contains(bundleIdentifier: nil), "an unidentified client was treated as busy")
        try require(snapshot.profile(for: "com.google.Chrome") == .busy, "exact member did not select busy")
        try require(snapshot.profile(for: "com.google.chrome") == .defaultProfile, "case mismatch was busy")
        try require(snapshot.profile(for: nil) == .defaultProfile, "unidentified client was not default")
        checkCount += 1
    }

    private static func checkEmptyFile() throws {
        let snapshot = BusyAppsSnapshot.load(
            environment: ["HOME": "/tmp/hisle-home"],
            reader: { _ in " \n\t\n# comment only\n" }
        )

        try require(snapshot.bundleIdentifiers.isEmpty, "an empty configuration produced entries")
        try require(snapshot.loadErrorDescription == nil, "an empty configuration was treated as a read failure")
        checkCount += 1
    }

    private static func checkMissingFileDoesNotCreateConfiguration() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("hisle-busy-apps-missing-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }

        let snapshot = BusyAppsSnapshot.load(
            environment: ["XDG_CONFIG_HOME": temporaryRoot.path]
        )

        try require(snapshot.bundleIdentifiers.isEmpty, "missing file produced entries")
        try require(snapshot.loadErrorDescription != nil, "missing file did not preserve its read error")
        try require(
            !FileManager.default.fileExists(atPath: temporaryRoot.path),
            "loading a missing file created its configuration directory"
        )
        checkCount += 1
    }

    private static func checkUnreadableAndInvalidUTF8Failures() throws {
        let unreadableSnapshot = BusyAppsSnapshot.load(
            environment: ["HOME": "/tmp/hisle-home"],
            reader: { _ in throw ExpectedReadError(message: "unreadable test file") }
        )
        try require(unreadableSnapshot.bundleIdentifiers.isEmpty, "unreadable file produced entries")
        try require(
            unreadableSnapshot.loadErrorDescription?.contains("unreadable test file") == true,
            "unreadable file did not preserve the error cause"
        )

        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("hisle-busy-apps-invalid-\(UUID().uuidString)", isDirectory: true)
        let configurationDirectory = temporaryRoot.appendingPathComponent("hisle", isDirectory: true)
        let configurationFile = configurationDirectory.appendingPathComponent("busy-apps.txt")
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }

        try FileManager.default.createDirectory(
            at: configurationDirectory,
            withIntermediateDirectories: true
        )
        try Data([0xFF, 0xFE, 0xFD]).write(to: configurationFile)
        let invalidUTF8Snapshot = BusyAppsSnapshot.load(
            environment: ["XDG_CONFIG_HOME": temporaryRoot.path]
        )
        try require(invalidUTF8Snapshot.bundleIdentifiers.isEmpty, "invalid UTF-8 produced entries")
        try require(invalidUTF8Snapshot.loadErrorDescription != nil, "invalid UTF-8 had no read error")
        checkCount += 1
    }

    private static func checkInitializerCreatesResolvedFiles() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("hisle-busy-apps-init-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }

        let xdgHome = temporaryRoot.appendingPathComponent("xdg", isDirectory: true)
        let home = temporaryRoot.appendingPathComponent("home", isDirectory: true)
        let fallbackHome = temporaryRoot.appendingPathComponent("fallback", isDirectory: true)
        let scenarios = [
            InitializationScenario(
                environment: ["XDG_CONFIG_HOME": xdgHome.path, "HOME": home.path],
                fallbackHomeDirectory: fallbackHome,
                expectedURL: xdgHome.appendingPathComponent("hisle/busy-apps.txt")
            ),
            InitializationScenario(
                environment: ["XDG_CONFIG_HOME": "", "HOME": home.path],
                fallbackHomeDirectory: fallbackHome,
                expectedURL: home.appendingPathComponent(".config/hisle/busy-apps.txt")
            ),
            InitializationScenario(
                environment: [:],
                fallbackHomeDirectory: fallbackHome,
                expectedURL: fallbackHome.appendingPathComponent(".config/hisle/busy-apps.txt")
            )
        ]

        for scenario in scenarios {
            let result = try BusyAppsSnapshot.initializeConfigurationFile(
                environment: scenario.environment,
                fallbackHomeDirectory: scenario.fallbackHomeDirectory
            )
            let contents = try Data(contentsOf: scenario.expectedURL)
            try require(
                result.created,
                "initializer reported a new file as existing: \(scenario.expectedURL.path)"
            )
            try require(
                result.configurationFileURL == scenario.expectedURL,
                "initializer used the wrong path: \(result.configurationFileURL.path)"
            )
            try require(
                contents.isEmpty,
                "initializer did not create an empty file: \(scenario.expectedURL.path)"
            )
        }
        checkCount += 1
    }

    private static func checkInitializerPreservesExistingFile() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("hisle-busy-apps-existing-\(UUID().uuidString)", isDirectory: true)
        let configurationDirectory = temporaryRoot.appendingPathComponent("hisle", isDirectory: true)
        let configurationFile = configurationDirectory.appendingPathComponent("busy-apps.txt")
        let originalContents = Data([0xFF, 0x00, 0x41, 0x0A])
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }

        try FileManager.default.createDirectory(
            at: configurationDirectory,
            withIntermediateDirectories: true
        )
        try originalContents.write(to: configurationFile)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: configurationFile.path
        )

        let firstResult = try BusyAppsSnapshot.initializeConfigurationFile(
            environment: ["XDG_CONFIG_HOME": temporaryRoot.path]
        )
        let secondResult = try BusyAppsSnapshot.initializeConfigurationFile(
            environment: ["XDG_CONFIG_HOME": temporaryRoot.path]
        )
        let currentContents = try Data(contentsOf: configurationFile)
        let attributes = try FileManager.default.attributesOfItem(atPath: configurationFile.path)

        try require(!firstResult.created, "initializer replaced an existing file on its first run")
        try require(!secondResult.created, "initializer replaced an existing file on a repeated run")
        try require(currentContents == originalContents, "initializer changed existing file bytes")
        try require(
            (attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,
            "initializer changed existing file permissions"
        )
        checkCount += 1
    }

    private static func checkInitializerAcceptsRegularFileSymbolicLink() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("hisle-busy-apps-symlink-\(UUID().uuidString)", isDirectory: true)
        let configurationDirectory = temporaryRoot.appendingPathComponent("hisle", isDirectory: true)
        let configurationFile = configurationDirectory.appendingPathComponent("busy-apps.txt")
        let targetFile = temporaryRoot.appendingPathComponent("managed-busy-apps.txt")
        let originalContents = Data("com.example.Managed\n".utf8)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }

        try FileManager.default.createDirectory(
            at: configurationDirectory,
            withIntermediateDirectories: true
        )
        try originalContents.write(to: targetFile)
        try FileManager.default.createSymbolicLink(
            at: configurationFile,
            withDestinationURL: targetFile
        )

        let result = try BusyAppsSnapshot.initializeConfigurationFile(
            environment: ["XDG_CONFIG_HOME": temporaryRoot.path]
        )
        let currentContents = try Data(contentsOf: targetFile)
        let currentDestination = try FileManager.default.destinationOfSymbolicLink(
            atPath: configurationFile.path
        )

        try require(!result.created, "initializer reported a regular-file symlink as newly created")
        try require(
            currentContents == originalContents,
            "initializer changed a regular-file symlink target"
        )
        try require(
            currentDestination == targetFile.path,
            "initializer replaced the regular-file symlink"
        )
        checkCount += 1
    }

    private static func checkInitializerRejectsNonRegularDestinations() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("hisle-busy-apps-directory-\(UUID().uuidString)", isDirectory: true)
        let destination = temporaryRoot.appendingPathComponent("hisle/busy-apps.txt", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }

        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var didThrow = false
        do {
            _ = try BusyAppsSnapshot.initializeConfigurationFile(
                environment: ["XDG_CONFIG_HOME": temporaryRoot.path]
            )
        } catch {
            didThrow = true
        }

        var isDirectory = ObjCBool(false)
        try require(didThrow, "initializer accepted a directory at the file path")
        try require(
            FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory) &&
                isDirectory.boolValue,
            "initializer changed the destination directory"
        )

        try FileManager.default.removeItem(at: destination)
        guard Darwin.mkfifo(destination.path, mode_t(0o600)) == 0 else {
            throw CheckFailure(description: "could not create the initializer FIFO fixture")
        }
        let fifoAttributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        let fifoFileNumber = (fifoAttributes[.systemFileNumber] as? NSNumber)?.uint64Value
        didThrow = false
        do {
            _ = try BusyAppsSnapshot.initializeConfigurationFile(
                environment: ["XDG_CONFIG_HOME": temporaryRoot.path]
            )
        } catch {
            didThrow = true
        }

        let preservedAttributes = try FileManager.default.attributesOfItem(atPath: destination.path)
        let preservedFileNumber = (preservedAttributes[.systemFileNumber] as? NSNumber)?.uint64Value
        try require(didThrow, "initializer accepted a FIFO at the file path")
        try require(
            fifoFileNumber != nil && preservedFileNumber == fifoFileNumber,
            "initializer changed the destination FIFO"
        )
        checkCount += 1
    }

    private static func checkSnapshotDoesNotReload() throws {
        var contents = "app.before.restart\n"
        var readCount = 0
        let snapshot = BusyAppsSnapshot.load(
            environment: ["HOME": "/tmp/hisle-home"],
            reader: { _ in
                readCount += 1
                return contents
            }
        )

        contents = "app.after.restart\n"
        try require(readCount == 1, "configuration was read \(readCount) times")
        try require(snapshot.contains(bundleIdentifier: "app.before.restart"), "snapshot lost its initial entry")
        try require(!snapshot.contains(bundleIdentifier: "app.after.restart"), "snapshot reloaded changed contents")
        checkCount += 1
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ description: String) throws {
        guard condition() else {
            throw CheckFailure(description: description)
        }
    }
}
