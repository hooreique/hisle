import Foundation

private struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

@main
private enum FrontmostMonitorCheck {
    static func main() throws {
        try checkInitialAndChangedIdentifiers()
        try checkMissingIdentifierAndContinuation()
        try checkLineFramingAndErrorChannel()

        print("Frontmost monitor check passed 3 scenarios.")
    }

    private static func checkInitialAndChangedIdentifiers() throws {
        var identifiers: [String] = []
        var missingIdentifierCount = 0
        let monitor = FrontmostApplicationMonitor(
            outputIdentifier: { identifiers.append($0) },
            outputMissingIdentifier: { missingIdentifierCount += 1 }
        )

        monitor.observe(bundleIdentifier: "com.example.Initial")
        monitor.observe(bundleIdentifier: "com.example.Initial")
        monitor.observe(bundleIdentifier: "com.example.Changed")
        monitor.observe(bundleIdentifier: "com.example.Changed")

        guard identifiers == ["com.example.Initial", "com.example.Changed"] else {
            throw CheckFailure(
                description: "initial/change output mismatch: \(identifiers)"
            )
        }
        guard missingIdentifierCount == 0 else {
            throw CheckFailure(
                description: "identified applications reported missing identifiers"
            )
        }
    }

    private static func checkMissingIdentifierAndContinuation() throws {
        var identifiers: [String] = []
        var missingIdentifierCount = 0
        let monitor = FrontmostApplicationMonitor(
            outputIdentifier: { identifiers.append($0) },
            outputMissingIdentifier: { missingIdentifierCount += 1 }
        )

        monitor.observe(bundleIdentifier: nil)
        monitor.observe(bundleIdentifier: "com.example.Available")
        monitor.observe(bundleIdentifier: nil)
        monitor.observe(bundleIdentifier: "com.example.Available")

        guard missingIdentifierCount == 2 else {
            throw CheckFailure(
                description: "missing identifier count mismatch: \(missingIdentifierCount)"
            )
        }
        guard identifiers == ["com.example.Available", "com.example.Available"] else {
            throw CheckFailure(
                description: "monitor did not continue across a missing identifier: \(identifiers)"
            )
        }
    }

    private static func checkLineFramingAndErrorChannel() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hisle-frontmost-\(UUID().uuidString)", isDirectory: true)
        let standardOutputURL = temporaryDirectory.appendingPathComponent("stdout")
        let standardErrorURL = temporaryDirectory.appendingPathComponent("stderr")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
        _ = FileManager.default.createFile(atPath: standardOutputURL.path, contents: nil)
        _ = FileManager.default.createFile(atPath: standardErrorURL.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }

        let standardOutput = try FileHandle(forWritingTo: standardOutputURL)
        let standardError = try FileHandle(forWritingTo: standardErrorURL)
        let output = FrontmostApplicationOutput(
            standardOutput: standardOutput,
            standardError: standardError
        )
        let monitor = FrontmostApplicationMonitor(
            outputIdentifier: output.writeIdentifier,
            outputMissingIdentifier: output.writeMissingIdentifier
        )

        monitor.observe(bundleIdentifier: "com.example.Exact")
        monitor.observe(bundleIdentifier: nil)
        try standardOutput.close()
        try standardError.close()

        let standardOutputText = try String(contentsOf: standardOutputURL, encoding: .utf8)
        let standardErrorText = try String(contentsOf: standardErrorURL, encoding: .utf8)
        guard standardOutputText == "com.example.Exact\n" else {
            throw CheckFailure(
                description: "stdout framing mismatch: \(String(reflecting: standardOutputText))"
            )
        }
        guard standardErrorText == "hisle: frontmost application has no bundle identifier\n" else {
            throw CheckFailure(
                description: "stderr framing mismatch: \(String(reflecting: standardErrorText))"
            )
        }
    }
}
