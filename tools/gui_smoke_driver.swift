import Cocoa
import Foundation

private let sublimeAppName = "Sublime Text"
private let sublimeBundleIDs = ["com.sublimetext.4", "com.sublimetext.3"]
private let sublimeDownloadURL = "https://www.sublimetext.com/download"
private let sublimeLaunchTimeout: TimeInterval = 45.0
private let sublimeFocusTimeout: TimeInterval = 20.0
private let expectedHangulSaveText = "f`\u{C758}f\u{C5B4}\u{315C}"
private let expectedRomanSaveText = "f`\u{C758}f\u{C5B4}\u{315C}f"
private let expectedText = "f`\u{C758}f\u{C5B4}\u{315C}ff"
private let smokeFileName = "hisle-gui-smoke-\(UUID().uuidString).txt"
private let smokeFileURL = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent(smokeFileName)
private var didSelectHisle = false

private func installedSublimeApplicationURL() -> URL? {
    for bundleID in sublimeBundleIDs {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url
        }
    }

    return nil
}

private func requireSublimeTextInstalled() throws {
    guard let url = installedSublimeApplicationURL() else {
        throw GuiTestFailure.message(
            "\(sublimeAppName) is required for the GUI smoke test but was not found. " +
            "Install it from \(sublimeDownloadURL), then rerun make gui-smoke-test."
        )
    }

    print("Found \(sublimeAppName): \(url.path)")
}

private func launchSublime(with fileURL: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-a", sublimeAppName, fileURL.path]
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw GuiTestFailure.message(
            "Could not open \(sublimeAppName). Confirm it is installed from \(sublimeDownloadURL), then rerun make gui-smoke-test."
        )
    }
}

private func runningSublime() -> NSRunningApplication? {
    runningApplication(bundleIDs: sublimeBundleIDs, appName: sublimeAppName)
}

@discardableResult
private func focusSublimeSmokeFile() throws -> NSRunningApplication {
    guard let app = waitForValue(timeout: sublimeLaunchTimeout, interval: 0.25, producer: runningSublime) else {
        throw GuiTestFailure.message("Timed out waiting for \(sublimeAppName) to launch.")
    }

    let hasSmokeWindow = wait(timeout: sublimeLaunchTimeout, interval: 0.25) {
        activate(app)
        return focusedWindowTitle(for: app)?.contains(smokeFileName) == true
    }

    guard hasSmokeWindow else {
        let title = focusedWindowTitle(for: app) ?? "<unknown>"
        throw GuiTestFailure.message(
            "Timed out waiting for \(sublimeAppName) to open the smoke-test file. Front window title: \(title)."
        )
    }

    var didClick = false
    let focused = wait(timeout: sublimeFocusTimeout, interval: 0.25) {
        activate(app)

        if NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier, !didClick {
            try? clickFocusedWindowCenter(of: app, appName: sublimeAppName)
            didClick = true
        }

        return NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier &&
            focusedWindowTitle(for: app)?.contains(smokeFileName) == true
    }

    guard focused else {
        let frontmost = NSWorkspace.shared.frontmostApplication?.localizedName ?? "<unknown>"
        let title = focusedWindowTitle(for: app) ?? "<unknown>"
        throw GuiTestFailure.message(
            "\(sublimeAppName) is not focused on the smoke-test file. " +
            "Frontmost app: \(frontmost). \(sublimeAppName) front window title: \(title). Refusing to send GUI key events."
        )
    }

    return app
}

private func savedFileContents() -> String {
    (try? String(contentsOf: smokeFileURL, encoding: .utf8)) ?? ""
}

private func verifySavedFileContents(_ expected: String, stage: String) throws {
    let didSave = wait(timeout: 5.0, interval: 0.1) {
        savedFileContents() == expected
    }

    guard didSave else {
        throw GuiTestFailure.message(
            "\(stage) save verification failed. Expected saved file content " +
            "\(String(reflecting: expected)), got \(String(reflecting: savedFileContents()))."
        )
    }

    print("\(stage) save verified: \(String(reflecting: expected))")
}

private func runSmokeTest() throws {
    try requireSublimeTextInstalled()
    try requireAccessibilityPermission(rerunCommand: "make gui-smoke-test")

    let originalInputSourceID = currentInputSourceID()
    defer {
        if didSelectHisle, let originalInputSourceID, originalInputSourceID != hisleInputSourceID {
            try? selectInputSource(id: originalInputSourceID)
        }
        print("Smoke-test file left open in \(sublimeAppName): \(smokeFileURL.path)")
    }

    try "".write(to: smokeFileURL, atomically: true, encoding: .utf8)
    print("Opening \(sublimeAppName) with \(smokeFileURL.path)")
    try launchSublime(with: smokeFileURL)
    let app = try focusSublimeSmokeFile()
    try clickFocusedWindowCenter(of: app, appName: sublimeAppName)

    print("Selecting hisle input source: \(hisleInputSourceID)")
    try selectInputSource(id: hisleInputSourceID)
    didSelectHisle = true
    Thread.sleep(forTimeInterval: 0.3)
    let focusedApp = try focusSublimeSmokeFile()
    try clickFocusedWindowCenter(of: focusedApp, appName: sublimeAppName)

    let logStream = HisleLogStream()
    print("Streaming hisle logs. Watch \(sublimeAppName) for final text: \(expectedText)")
    try logStream.start()
    defer {
        logStream.stop()
    }
    Thread.sleep(forTimeInterval: 0.5)

    let keyboard = try KeyboardDriver()
    try verifyHisleCLIMode("roman", stage: "Initial hisle selection")

    print("Typing smoke sequence: initial E, right Shift, backtick, j g d, Escape, E, right Shift, j t b")
    try keyboard.tapKey(KeyCode.e)
    try keyboard.tapModifier(KeyCode.rightShift, flag: .maskShift)
    try verifyHisleCLIMode("hangul", stage: "Right Shift")
    try keyboard.tapKey(KeyCode.backtick)
    try keyboard.tapKey(KeyCode.j)
    try keyboard.tapKey(KeyCode.g)
    try keyboard.tapKey(KeyCode.d)
    try keyboard.tapKey(KeyCode.escape)
    try verifyHisleCLIMode("roman", stage: "Escape")
    try keyboard.tapKey(KeyCode.e)
    try keyboard.tapModifier(KeyCode.rightShift, flag: .maskShift)
    try verifyHisleCLIMode("hangul", stage: "Second right Shift")
    try keyboard.tapKey(KeyCode.j)
    try keyboard.tapKey(KeyCode.t)
    try keyboard.tapKey(KeyCode.b)

    print("Saving text after Hangul sequence with Command+representative d, which is Colemak Command+S")
    try keyboard.saveUsingColemakShortcut()
    try verifySavedFileContents(expectedHangulSaveText, stage: "Hangul-sequence")

    print("Completing smoke sequence: left Shift, E, final save")
    try keyboard.tapModifier(KeyCode.leftShift, flag: .maskShift)
    try verifyHisleCLIMode("roman", stage: "Left Shift")
    try keyboard.tapKey(KeyCode.e)
    try keyboard.saveUsingColemakShortcut()
    try verifySavedFileContents(expectedRomanSaveText, stage: "Roman-mode")

    print("Verifying input-source round trip: right Shift, other input source, hisle, E, final save")
    try keyboard.tapModifier(KeyCode.rightShift, flag: .maskShift)
    try verifyHisleCLIMode("hangul", stage: "Pre-round-trip right Shift")
    try switchAwayAndBackToHisle(originalInputSourceID: originalInputSourceID)
    didSelectHisle = true
    let roundTripFocusedApp = try focusSublimeSmokeFile()
    try clickFocusedWindowCenter(of: roundTripFocusedApp, appName: sublimeAppName)
    try verifyHisleCLIMode("roman", stage: "Input-source round-trip")
    try keyboard.tapKey(KeyCode.e)
    try keyboard.saveUsingColemakShortcut()
    try verifySavedFileContents(expectedText, stage: "Input-source round-trip")

    print("Scripted GUI smoke sequence completed. Saved file content is exactly \(expectedText).")
}

@main
private enum GuiSmokeDriver {
    static func main() {
        do {
            try runSmokeTest()
        } catch {
            if let failure = error as? GuiTestFailure {
                fputs("GUI smoke test failed: \(failure.description)\n", stderr)
            } else {
                fputs("GUI smoke test failed: \(error)\n", stderr)
            }
            exit(1)
        }
    }
}
