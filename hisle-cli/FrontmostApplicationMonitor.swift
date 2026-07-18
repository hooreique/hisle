import Foundation

final class FrontmostApplicationOutput {
    private let standardOutput: FileHandle
    private let standardError: FileHandle

    init(standardOutput: FileHandle, standardError: FileHandle) {
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    func writeIdentifier(_ bundleIdentifier: String) {
        writeLine(bundleIdentifier, to: standardOutput)
    }

    func writeMissingIdentifier() {
        writeLine("hisle: frontmost application has no bundle identifier", to: standardError)
    }

    private func writeLine(_ line: String, to fileHandle: FileHandle) {
        fileHandle.write(Data("\(line)\n".utf8))
        try? fileHandle.synchronize()
    }
}

final class FrontmostApplicationMonitor {
    typealias IdentifierOutput = (String) -> Void
    typealias MissingIdentifierOutput = () -> Void

    private let outputIdentifier: IdentifierOutput
    private let outputMissingIdentifier: MissingIdentifierOutput
    private var hasObservedApplication = false
    private var previousIdentifier: String?

    init(
        outputIdentifier: @escaping IdentifierOutput,
        outputMissingIdentifier: @escaping MissingIdentifierOutput
    ) {
        self.outputIdentifier = outputIdentifier
        self.outputMissingIdentifier = outputMissingIdentifier
    }

    func observe(bundleIdentifier: String?) {
        defer {
            hasObservedApplication = true
            previousIdentifier = bundleIdentifier
        }

        guard let bundleIdentifier else {
            outputMissingIdentifier()
            return
        }

        guard !hasObservedApplication || previousIdentifier != bundleIdentifier else {
            return
        }

        outputIdentifier(bundleIdentifier)
    }
}
