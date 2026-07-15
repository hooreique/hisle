import AppKit
import Darwin
import Foundation
import HisleCore

private enum ExitCode {
    static let success: Int32 = 0
    static let usage: Int32 = 64
    static let cannotCreate: Int32 = 73
}

private enum ModeState {
    static let suiteName = "hooreique.inputmethod.hisle"
    static let key = "inputMode"
    static let fallback = "roman"

    static var current: String {
        let domain = suiteName as CFString
        CFPreferencesAppSynchronize(domain)

        guard let value = CFPreferencesCopyAppValue(key as CFString, domain) as? String else {
            return fallback
        }

        switch value {
        case "hangul", "roman":
            return value
        default:
            return fallback
        }
    }
}

private func printHelp() {
    print("""
    usage: hisle [init | frontmost | --help | --version]

    Without options, prints the current input mode: roman or hangul.
    init creates busy-apps.txt if missing and prints its path.
    frontmost prints the current app bundle identifier and monitors changes.
    """)
}

private func printVersion() {
    print("hisle \(displayedHisleVersion())")
    print("hisle-core \(HisleCore.version)")
}

private func displayedHisleVersion() -> String {
    let version = hisleVersion()

    #if DEBUG
    return version == "unknown" ? version : "\(version)-debug"
    #else
    return version
    #endif
}

private func hisleVersion() -> String {
    if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
       !version.isEmpty {
        return version
    }

    if let appBundle = containingAppBundle(),
       let version = appBundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
       !version.isEmpty {
        return version
    }

    return "unknown"
}

private func containingAppBundle() -> Bundle? {
    let executableURL = currentExecutableURL()
    let contentsURL = executableURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    guard contentsURL.lastPathComponent == "Contents" else {
        return nil
    }

    let appURL = contentsURL.deletingLastPathComponent()
    guard appURL.pathExtension == "app" else {
        return nil
    }
    return Bundle(url: appURL)
}

private func currentExecutableURL() -> URL {
    var size: UInt32 = 0
    _ = _NSGetExecutablePath(nil, &size)

    var buffer = [CChar](repeating: 0, count: Int(size))
    _ = _NSGetExecutablePath(&buffer, &size)
    return URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath()
}

private func printError(_ message: String) {
    FileHandle.standardError.write(Data("hisle: \(message)\n".utf8))
}

private func monitorFrontmostApplications() {
    let workspace = NSWorkspace.shared
    let output = FrontmostApplicationOutput(
        standardOutput: .standardOutput,
        standardError: .standardError
    )
    let monitor = FrontmostApplicationMonitor(
        outputIdentifier: output.writeIdentifier,
        outputMissingIdentifier: output.writeMissingIdentifier
    )
    let observer = workspace.notificationCenter.addObserver(
        forName: NSWorkspace.didActivateApplicationNotification,
        object: nil,
        queue: .main
    ) { notification in
        let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication
        monitor.observe(bundleIdentifier: application?.bundleIdentifier)
    }

    monitor.observe(bundleIdentifier: workspace.frontmostApplication?.bundleIdentifier)

    withExtendedLifetime(observer) {
        RunLoop.main.run()
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())

switch arguments {
case []:
    print(ModeState.current)
    exit(ExitCode.success)
case ["--help"], ["-h"]:
    printHelp()
    exit(ExitCode.success)
case ["--version"]:
    printVersion()
    exit(ExitCode.success)
case ["init"]:
    let configurationFileURL = BusyAppsSnapshot.configurationFileURL()
    do {
        let result = try BusyAppsSnapshot.initializeConfigurationFile()
        print(result.configurationFileURL.path)
        exit(ExitCode.success)
    } catch {
        printError(
            "could not initialize busy apps configuration at \(configurationFileURL.path): " +
                error.localizedDescription
        )
        exit(ExitCode.cannotCreate)
    }
case ["frontmost"]:
    monitorFrontmostApplications()
    exit(ExitCode.success)
default:
    printError("unknown arguments: \(arguments.joined(separator: " "))")
    printError("run 'hisle --help' for usage")
    exit(ExitCode.usage)
}
