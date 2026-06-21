import ApplicationServices
import Carbon
import Cocoa
import Foundation

private enum SmokeFailure: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let text):
            return text
        }
    }
}

private enum KeyCode {
    static let b: CGKeyCode = 11
    static let c: CGKeyCode = 8
    static let d: CGKeyCode = 2
    static let f: CGKeyCode = 3
    static let e: CGKeyCode = 14
    static let g: CGKeyCode = 5
    static let j: CGKeyCode = 38
    static let r: CGKeyCode = 15
    static let t: CGKeyCode = 17
    static let nine: CGKeyCode = 25
    static let k: CGKeyCode = 40
    static let slash: CGKeyCode = 44
    static let space: CGKeyCode = 49
    static let escape: CGKeyCode = 53
    static let backtick: CGKeyCode = 50
    static let leftCommand: CGKeyCode = 55
    static let leftShift: CGKeyCode = 56
    static let rightShift: CGKeyCode = 60
}

private final class KeyboardDriver {
    private let source: CGEventSource
    private let eventDelay: TimeInterval = 0.08

    init() throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw SmokeFailure.message("Could not create a CGEventSource.")
        }
        self.source = source
    }

    func tapKey(_ keyCode: CGKeyCode, flags: CGEventFlags = CGEventFlags(rawValue: 0)) throws {
        try post(keyCode, keyDown: true, flags: flags)
        try post(keyCode, keyDown: false, flags: flags)
    }

    func tapModifier(_ keyCode: CGKeyCode, flag: CGEventFlags) throws {
        try post(keyCode, keyDown: true, flags: flag)
        Thread.sleep(forTimeInterval: eventDelay)
        try post(keyCode, keyDown: false)
    }

    func tapCommandShortcut(_ keyCode: CGKeyCode) throws {
        try post(KeyCode.leftCommand, keyDown: true, flags: .maskCommand)
        try post(keyCode, keyDown: true, flags: .maskCommand)
        try post(keyCode, keyDown: false, flags: .maskCommand)
        try post(KeyCode.leftCommand, keyDown: false)
    }

    private func post(
        _ keyCode: CGKeyCode,
        keyDown: Bool,
        flags: CGEventFlags = CGEventFlags(rawValue: 0)
    ) throws {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else {
            throw SmokeFailure.message("Could not create a CGEvent for keyCode \(keyCode).")
        }
        event.flags = flags
        event.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: eventDelay)
    }
}

private extension KeyboardDriver {
    func saveUsingColemakShortcut() throws {
        try tapCommandShortcut(KeyCode.d)
    }
}

private let inputSourceID = "hooreique.inputmethod.hisle.main"
private let fallbackRoundTripInputSourceIDs = [
    "com.apple.keylayout.ABC",
    "com.apple.keylayout.US",
    "com.apple.keylayout.Colemak",
]
private let sublimeAppName = "Sublime Text"
private let sublimeBundleIDs = ["com.sublimetext.4", "com.sublimetext.3"]
private let sublimeDownloadURL = "https://www.sublimetext.com/download"
private let sublimeLaunchTimeout: TimeInterval = 45.0
private let sublimeFocusTimeout: TimeInterval = 20.0
private let cliModePropagationTimeout: TimeInterval = 2.0
private let hisleCLIURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library")
    .appendingPathComponent("Input Methods")
    .appendingPathComponent("hisle.app")
    .appendingPathComponent("Contents")
    .appendingPathComponent("Helpers")
    .appendingPathComponent("hisle")
private let expectedHangulSaveText = "f`\u{C758}f\u{C5B4}\u{315C}"
private let expectedRomanSaveText = "f`\u{C758}f\u{C5B4}\u{315C}f"
private let expectedText = "f`\u{C758}f\u{C5B4}\u{315C}ff"
private let smokeFileName = "hisle-gui-smoke-\(UUID().uuidString).txt"
private let smokeFileURL = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent(smokeFileName)
private var didSelectHisle = false

private final class HisleLogStream {
    private let process = Process()

    func start() throws {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "stream",
            "--style", "compact",
            "--level", "debug",
            "--predicate", "subsystem == \"hooreique.inputmethod.hisle\""
        ]
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
    }

    func stop() {
        guard process.isRunning else {
            return
        }
        process.terminate()
        process.waitUntilExit()
    }
}

private func requireAccessibilityPermission() throws {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    guard AXIsProcessTrustedWithOptions(options) else {
        throw SmokeFailure.message(
            "Accessibility permission is required to send GUI key events. " +
            "Grant permission to the terminal/Codex process in System Settings > Privacy & Security > Accessibility, then rerun make gui-smoke-test."
        )
    }
}

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
        throw SmokeFailure.message(
            "\(sublimeAppName) is required for the GUI smoke test but was not found. " +
            "Install it from \(sublimeDownloadURL), then rerun make gui-smoke-test."
        )
    }

    print("Found \(sublimeAppName): \(url.path)")
}

private func inputSourceID(for source: TISInputSource) -> String? {
    guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
        return nil
    }
    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
}

private func currentInputSourceID() -> String? {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
        return nil
    }
    return inputSourceID(for: source)
}

private func inputSourceExists(id: String) -> Bool {
    let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
    let sources = TISCreateInputSourceList(filter, true).takeRetainedValue() as NSArray
    return sources.count > 0
}

private func roundTripInputSourceID(prefer originalID: String?) -> String? {
    if let originalID,
       originalID != inputSourceID,
       inputSourceExists(id: originalID) {
        return originalID
    }

    for id in fallbackRoundTripInputSourceIDs where id != inputSourceID && inputSourceExists(id: id) {
        return id
    }

    let filter = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource] as CFDictionary
    let sources = TISCreateInputSourceList(filter, true).takeRetainedValue() as NSArray

    for sourceValue in sources {
        let source = sourceValue as! TISInputSource
        guard let id = inputSourceID(for: source),
              id != inputSourceID else {
            continue
        }
        return id
    }

    return nil
}

private func selectInputSource(id: String) throws {
    let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
    let sources = TISCreateInputSourceList(filter, true).takeRetainedValue() as NSArray

    guard sources.count > 0 else {
        throw SmokeFailure.message(
            "Input source \(id) was not found. Run make install-debug and enable hisle in System Settings > Keyboard > Input Sources."
        )
    }

    let source = sources[0] as! TISInputSource
    let enableStatus = TISEnableInputSource(source)
    guard enableStatus == noErr else {
        throw SmokeFailure.message("Could not enable input source \(id): OSStatus \(enableStatus).")
    }

    let selectStatus = TISSelectInputSource(source)
    guard selectStatus == noErr else {
        throw SmokeFailure.message("Could not select input source \(id): OSStatus \(selectStatus).")
    }

    guard wait(timeout: 2.0, interval: 0.05, until: { currentInputSourceID() == id }) else {
        throw SmokeFailure.message("Timed out waiting for input source \(id) to become active.")
    }
}

private func switchAwayAndBackToHisle(originalInputSourceID: String?) throws {
    guard let otherInputSourceID = roundTripInputSourceID(prefer: originalInputSourceID) else {
        throw SmokeFailure.message("Could not find another input source for the round-trip check.")
    }

    print("Switching away from hisle input source: \(otherInputSourceID)")
    try selectInputSource(id: otherInputSourceID)
    Thread.sleep(forTimeInterval: 0.3)

    print("Selecting hisle input source again: \(inputSourceID)")
    try selectInputSource(id: inputSourceID)
    didSelectHisle = true
    Thread.sleep(forTimeInterval: 0.3)
}

private func launchSublime(with fileURL: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-a", sublimeAppName, fileURL.path]
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw SmokeFailure.message(
            "Could not open \(sublimeAppName). Confirm it is installed from \(sublimeDownloadURL), then rerun make gui-smoke-test."
        )
    }
}

private func runningSublime() -> NSRunningApplication? {
    for bundleID in sublimeBundleIDs {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            return app
        }
    }

    return NSWorkspace.shared.runningApplications.first { app in
        app.localizedName == sublimeAppName
    }
}

private func focusedWindowTitle(for app: NSRunningApplication) -> String? {
    let element = AXUIElementCreateApplication(app.processIdentifier)
    var windowValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
          let window = windowValue else {
        return nil
    }

    var titleValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &titleValue) == .success else {
        return nil
    }

    return titleValue as? String
}

private func focusedWindowFrame(for app: NSRunningApplication) -> CGRect? {
    let element = AXUIElementCreateApplication(app.processIdentifier)
    var windowValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
          let window = windowValue else {
        return nil
    }

    var positionValue: CFTypeRef?
    var sizeValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXPositionAttribute as CFString, &positionValue) == .success,
          AXUIElementCopyAttributeValue(window as! AXUIElement, kAXSizeAttribute as CFString, &sizeValue) == .success,
          let positionAXValue = positionValue,
          let sizeAXValue = sizeValue else {
        return nil
    }

    var position = CGPoint.zero
    var size = CGSize.zero
    guard AXValueGetValue(positionAXValue as! AXValue, .cgPoint, &position),
          AXValueGetValue(sizeAXValue as! AXValue, .cgSize, &size) else {
        return nil
    }

    return CGRect(origin: position, size: size)
}

private func activate(_ app: NSRunningApplication) {
    if #available(macOS 14.0, *) {
        app.activate(options: [.activateAllWindows])
    } else {
        app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    let element = AXUIElementCreateApplication(app.processIdentifier)
    var windowValue: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
       let windowValue {
        AXUIElementPerformAction(windowValue as! AXUIElement, kAXRaiseAction as CFString)
    }
}

@discardableResult
private func focusSublimeSmokeFile() throws -> NSRunningApplication {
    guard let app = waitForValue(timeout: sublimeLaunchTimeout, interval: 0.25, producer: runningSublime) else {
        throw SmokeFailure.message("Timed out waiting for \(sublimeAppName) to launch.")
    }

    let hasSmokeWindow = wait(timeout: sublimeLaunchTimeout, interval: 0.25) {
        activate(app)
        return focusedWindowTitle(for: app)?.contains(smokeFileName) == true
    }

    guard hasSmokeWindow else {
        let title = focusedWindowTitle(for: app) ?? "<unknown>"
        throw SmokeFailure.message(
            "Timed out waiting for \(sublimeAppName) to open the smoke-test file. Front window title: \(title)."
        )
    }

    var didClick = false
    let focused = wait(timeout: sublimeFocusTimeout, interval: 0.25) {
        activate(app)

        if NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier, !didClick {
            try? clickFocusedWindowCenter(of: app)
            didClick = true
        }

        return NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier &&
            focusedWindowTitle(for: app)?.contains(smokeFileName) == true
    }

    guard focused else {
        let frontmost = NSWorkspace.shared.frontmostApplication?.localizedName ?? "<unknown>"
        let title = focusedWindowTitle(for: app) ?? "<unknown>"
        throw SmokeFailure.message(
            "\(sublimeAppName) is not focused on the smoke-test file. " +
            "Frontmost app: \(frontmost). \(sublimeAppName) front window title: \(title). Refusing to send GUI key events."
        )
    }

    return app
}

private func clickFocusedWindowCenter(of app: NSRunningApplication) throws {
    guard let frame = focusedWindowFrame(for: app) else {
        throw SmokeFailure.message("Could not determine the focused \(sublimeAppName) window frame.")
    }
    guard let source = CGEventSource(stateID: .hidSystemState) else {
        throw SmokeFailure.message("Could not create a CGEventSource for mouse focus.")
    }

    let point = CGPoint(x: frame.midX, y: frame.midY)
    guard let mouseDown = CGEvent(
        mouseEventSource: source,
        mouseType: .leftMouseDown,
        mouseCursorPosition: point,
        mouseButton: .left
    ),
    let mouseUp = CGEvent(
        mouseEventSource: source,
        mouseType: .leftMouseUp,
        mouseCursorPosition: point,
        mouseButton: .left
    ) else {
        throw SmokeFailure.message("Could not create mouse events for \(sublimeAppName) focus.")
    }

    mouseDown.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.08)
    mouseUp.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.2)
}

private func wait(timeout: TimeInterval, interval: TimeInterval, until condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if condition() {
            return true
        }
        Thread.sleep(forTimeInterval: interval)
    } while Date() < deadline
    return condition()
}

private func waitForValue<T>(timeout: TimeInterval, interval: TimeInterval, producer: () -> T?) -> T? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if let value = producer() {
            return value
        }
        Thread.sleep(forTimeInterval: interval)
    } while Date() < deadline
    return producer()
}

private func savedFileContents() -> String {
    (try? String(contentsOf: smokeFileURL, encoding: .utf8)) ?? ""
}

private func verifySavedFileContents(_ expected: String, stage: String) throws {
    let didSave = wait(timeout: 5.0, interval: 0.1) {
        savedFileContents() == expected
    }

    guard didSave else {
        throw SmokeFailure.message(
            "\(stage) save verification failed. Expected saved file content " +
            "\(String(reflecting: expected)), got \(String(reflecting: savedFileContents()))."
        )
    }

    print("\(stage) save verified: \(String(reflecting: expected))")
}

private func runHisleCLI() throws -> String {
    guard FileManager.default.isExecutableFile(atPath: hisleCLIURL.path) else {
        throw SmokeFailure.message(
            "Bundled hisle CLI was not found or is not executable at \(hisleCLIURL.path). Run make install-debug, then rerun make gui-smoke-test."
        )
    }

    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()
    process.executableURL = hisleCLIURL
    process.standardOutput = stdout
    process.standardError = stderr

    do {
        try process.run()
    } catch {
        throw SmokeFailure.message("Could not run bundled hisle CLI at \(hisleCLIURL.path): \(error).")
    }

    process.waitUntilExit()

    let stdoutText = String(
        data: stdout.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
    ) ?? ""
    let stderrText = String(
        data: stderr.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
    ) ?? ""

    guard process.terminationStatus == 0 else {
        throw SmokeFailure.message(
            "Bundled hisle CLI exited with status \(process.terminationStatus). stderr: \(String(reflecting: stderrText))"
        )
    }

    return stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func verifyHisleCLIMode(_ expected: String, stage: String) throws {
    var lastOutput = "<not run>"
    var lastFailure: String?

    let didMatch = wait(timeout: cliModePropagationTimeout, interval: 0.1) {
        do {
            lastOutput = try runHisleCLI()
            lastFailure = nil
            return lastOutput == expected
        } catch {
            lastFailure = String(describing: error)
            return false
        }
    }

    guard didMatch else {
        if let lastFailure {
            throw SmokeFailure.message("\(stage) CLI mode verification failed: \(lastFailure)")
        }

        throw SmokeFailure.message(
            "\(stage) CLI mode verification failed. Expected \(String(reflecting: expected)), got \(String(reflecting: lastOutput))."
        )
    }

    print("\(stage) CLI mode verified: \(expected)")
}

private func runSmokeTest() throws {
    try requireSublimeTextInstalled()
    try requireAccessibilityPermission()

    let originalInputSourceID = currentInputSourceID()
    defer {
        if didSelectHisle, let originalInputSourceID, originalInputSourceID != inputSourceID {
            try? selectInputSource(id: originalInputSourceID)
        }
        print("Smoke-test file left open in \(sublimeAppName): \(smokeFileURL.path)")
    }

    try "".write(to: smokeFileURL, atomically: true, encoding: .utf8)
    print("Opening \(sublimeAppName) with \(smokeFileURL.path)")
    try launchSublime(with: smokeFileURL)
    let app = try focusSublimeSmokeFile()
    try clickFocusedWindowCenter(of: app)

    print("Selecting hisle input source: \(inputSourceID)")
    try selectInputSource(id: inputSourceID)
    didSelectHisle = true
    Thread.sleep(forTimeInterval: 0.3)
    let focusedApp = try focusSublimeSmokeFile()
    try clickFocusedWindowCenter(of: focusedApp)

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
    let roundTripFocusedApp = try focusSublimeSmokeFile()
    try clickFocusedWindowCenter(of: roundTripFocusedApp)
    try verifyHisleCLIMode("roman", stage: "Input-source round-trip")
    try keyboard.tapKey(KeyCode.e)
    try keyboard.saveUsingColemakShortcut()
    try verifySavedFileContents(expectedText, stage: "Input-source round-trip")

    print("Scripted GUI smoke sequence completed. Saved file content is exactly \(expectedText).")
}

do {
    try runSmokeTest()
} catch {
    if let failure = error as? SmokeFailure {
        fputs("GUI smoke test failed: \(failure.description)\n", stderr)
    } else {
        fputs("GUI smoke test failed: \(error)\n", stderr)
    }
    exit(1)
}
