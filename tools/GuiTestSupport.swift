import ApplicationServices
import Carbon
import Cocoa
import Foundation

enum GuiTestFailure: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let text):
            return text
        }
    }
}

enum KeyCode {
    static let b: CGKeyCode = 11
    static let c: CGKeyCode = 8
    static let d: CGKeyCode = 2
    static let e: CGKeyCode = 14
    static let f: CGKeyCode = 3
    static let g: CGKeyCode = 5
    static let j: CGKeyCode = 38
    static let k: CGKeyCode = 40
    static let r: CGKeyCode = 15
    static let t: CGKeyCode = 17
    static let nine: CGKeyCode = 25
    static let slash: CGKeyCode = 44
    static let space: CGKeyCode = 49
    static let escape: CGKeyCode = 53
    static let backtick: CGKeyCode = 50
    static let leftCommand: CGKeyCode = 55
    static let leftShift: CGKeyCode = 56
    static let rightShift: CGKeyCode = 60
    static let downArrow: CGKeyCode = 125
}

enum KeyEventPhase: String {
    case keyDown
    case keyUp
}

struct PostedKeyEvent {
    let sequence: Int
    let wallClock: Date
    let keyCode: CGKeyCode
    let phase: KeyEventPhase
    let flags: CGEventFlags
    let plannedDelay: TimeInterval
}

final class KeyboardDriver {
    private let source: CGEventSource
    private var sequence = 0

    let eventDelay: TimeInterval
    var eventSink: ((PostedKeyEvent) -> Void)?

    init(eventDelay: TimeInterval = 0.08, eventSink: ((PostedKeyEvent) -> Void)? = nil) throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw GuiTestFailure.message("Could not create a CGEventSource.")
        }
        self.source = source
        self.eventDelay = eventDelay
        self.eventSink = eventSink
    }

    func tapKey(_ keyCode: CGKeyCode, flags: CGEventFlags = CGEventFlags(rawValue: 0)) throws {
        try post(keyCode, keyDown: true, flags: flags)
        try post(keyCode, keyDown: false, flags: flags)
    }

    func tapModifier(_ keyCode: CGKeyCode, flag: CGEventFlags) throws {
        try post(keyCode, keyDown: true, flags: flag)
        try post(keyCode, keyDown: false)
    }

    func tapCommandShortcut(_ keyCode: CGKeyCode) throws {
        try post(KeyCode.leftCommand, keyDown: true, flags: .maskCommand)
        try post(keyCode, keyDown: true, flags: .maskCommand)
        try post(keyCode, keyDown: false, flags: .maskCommand)
        try post(KeyCode.leftCommand, keyDown: false)
    }

    func post(
        _ keyCode: CGKeyCode,
        keyDown: Bool,
        flags: CGEventFlags = CGEventFlags(rawValue: 0),
        plannedDelay: TimeInterval? = nil
    ) throws {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else {
            throw GuiTestFailure.message("Could not create a CGEvent for keyCode \(keyCode).")
        }

        let delay = plannedDelay ?? eventDelay
        event.flags = flags
        event.post(tap: .cghidEventTap)

        sequence += 1
        eventSink?(
            PostedKeyEvent(
                sequence: sequence,
                wallClock: Date(),
                keyCode: keyCode,
                phase: keyDown ? .keyDown : .keyUp,
                flags: flags,
                plannedDelay: delay
            )
        )

        Thread.sleep(forTimeInterval: delay)
    }
}

extension KeyboardDriver {
    func saveUsingColemakShortcut() throws {
        try tapCommandShortcut(KeyCode.d)
    }
}

let hisleInputSourceID = "hooreique.inputmethod.hisle.main"
let fallbackRoundTripInputSourceIDs = [
    "com.apple.keylayout.ABC",
    "com.apple.keylayout.US",
    "com.apple.keylayout.Colemak",
]
let cliModePropagationTimeout: TimeInterval = 2.0
let hisleCLIURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library")
    .appendingPathComponent("Input Methods")
    .appendingPathComponent("hisle.app")
    .appendingPathComponent("Contents")
    .appendingPathComponent("Helpers")
    .appendingPathComponent("hisle")

final class HisleLogStream {
    private let process = Process()
    private let outputURL: URL?
    private var outputHandle: FileHandle?

    init(outputURL: URL? = nil) {
        self.outputURL = outputURL
    }

    func start() throws {
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "stream",
            "--style", "compact",
            "--level", "debug",
            "--predicate", "subsystem == \"hooreique.inputmethod.hisle\"",
        ]

        if let outputURL {
            FileManager.default.createFile(atPath: outputURL.path, contents: nil)
            let handle = try FileHandle(forWritingTo: outputURL)
            outputHandle = handle
            process.standardOutput = handle
            process.standardError = handle
        } else {
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError
        }

        try process.run()
    }

    func stop() {
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }

        try? outputHandle?.close()
        outputHandle = nil
    }
}

func requireAccessibilityPermission(rerunCommand: String) throws {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    guard AXIsProcessTrustedWithOptions(options) else {
        throw GuiTestFailure.message(
            "Accessibility permission is required to send GUI key events. " +
            "Grant permission to the terminal/Codex process in System Settings > Privacy & Security > Accessibility, then rerun \(rerunCommand)."
        )
    }
}

func inputSourceID(for source: TISInputSource) -> String? {
    guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
        return nil
    }
    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
}

func currentInputSourceID() -> String? {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
        return nil
    }
    return inputSourceID(for: source)
}

func inputSourceExists(id: String) -> Bool {
    let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
    let sources = TISCreateInputSourceList(filter, true).takeRetainedValue() as NSArray
    return sources.count > 0
}

func roundTripInputSourceID(prefer originalID: String?) -> String? {
    if let originalID,
       originalID != hisleInputSourceID,
       inputSourceExists(id: originalID) {
        return originalID
    }

    for id in fallbackRoundTripInputSourceIDs where id != hisleInputSourceID && inputSourceExists(id: id) {
        return id
    }

    let filter = [kTISPropertyInputSourceCategory as String: kTISCategoryKeyboardInputSource] as CFDictionary
    let sources = TISCreateInputSourceList(filter, true).takeRetainedValue() as NSArray

    for sourceValue in sources {
        let source = sourceValue as! TISInputSource
        guard let id = inputSourceID(for: source),
              id != hisleInputSourceID else {
            continue
        }
        return id
    }

    return nil
}

func selectInputSource(id: String) throws {
    let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
    let sources = TISCreateInputSourceList(filter, true).takeRetainedValue() as NSArray

    guard sources.count > 0 else {
        throw GuiTestFailure.message(
            "Input source \(id) was not found. Run make install-debug and enable hisle in System Settings > Keyboard > Input Sources."
        )
    }

    let source = sources[0] as! TISInputSource
    let enableStatus = TISEnableInputSource(source)
    guard enableStatus == noErr else {
        throw GuiTestFailure.message("Could not enable input source \(id): OSStatus \(enableStatus).")
    }

    let selectStatus = TISSelectInputSource(source)
    guard selectStatus == noErr else {
        throw GuiTestFailure.message("Could not select input source \(id): OSStatus \(selectStatus).")
    }

    guard wait(timeout: 2.0, interval: 0.05, until: { currentInputSourceID() == id }) else {
        throw GuiTestFailure.message("Timed out waiting for input source \(id) to become active.")
    }
}

func switchAwayAndBackToHisle(originalInputSourceID: String?) throws {
    guard let otherInputSourceID = roundTripInputSourceID(prefer: originalInputSourceID) else {
        throw GuiTestFailure.message("Could not find another input source for the round-trip check.")
    }

    print("Switching away from hisle input source: \(otherInputSourceID)")
    try selectInputSource(id: otherInputSourceID)
    Thread.sleep(forTimeInterval: 0.3)

    print("Selecting hisle input source again: \(hisleInputSourceID)")
    try selectInputSource(id: hisleInputSourceID)
    Thread.sleep(forTimeInterval: 0.3)
}

func runningApplication(bundleIDs: [String], appName: String) -> NSRunningApplication? {
    for bundleID in bundleIDs {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            return app
        }
    }

    return NSWorkspace.shared.runningApplications.first { app in
        app.localizedName == appName
    }
}

func focusedWindowTitle(for app: NSRunningApplication) -> String? {
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

func focusedWindowFrame(for app: NSRunningApplication) -> CGRect? {
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

private func frame(of element: AXUIElement) -> CGRect? {
    var positionValue: CFTypeRef?
    var sizeValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
          AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
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

private func firstAccessibilityDescendant(
    of element: AXUIElement,
    role expectedRole: String,
    depth: Int = 0
) -> AXUIElement? {
    guard depth < 12 else {
        return nil
    }

    var roleValue: CFTypeRef?
    if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
       let role = roleValue as? String,
       role == expectedRole {
        return element
    }

    var childrenValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
          let children = childrenValue as? [AXUIElement] else {
        return nil
    }

    for child in children {
        if let descendant = firstAccessibilityDescendant(of: child, role: expectedRole, depth: depth + 1) {
            return descendant
        }
    }

    return nil
}

func focusedWebAreaFrame(for app: NSRunningApplication) -> CGRect? {
    let application = AXUIElementCreateApplication(app.processIdentifier)
    var windowValue: CFTypeRef?
    guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
          let window = windowValue else {
        return nil
    }

    guard let webArea = firstAccessibilityDescendant(of: window as! AXUIElement, role: "AXWebArea") else {
        return nil
    }

    return frame(of: webArea)
}

func activate(_ app: NSRunningApplication) {
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

func clickFocusedWindowCenter(of app: NSRunningApplication, appName: String) throws {
    guard let frame = focusedWindowFrame(for: app) else {
        throw GuiTestFailure.message("Could not determine the focused \(appName) window frame.")
    }
    guard let source = CGEventSource(stateID: .hidSystemState) else {
        throw GuiTestFailure.message("Could not create a CGEventSource for mouse focus.")
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
        throw GuiTestFailure.message("Could not create mouse events for \(appName) focus.")
    }

    mouseDown.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.08)
    mouseUp.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.2)
}

func clickScreenPoint(_ point: CGPoint, description: String) throws {
    guard let source = CGEventSource(stateID: .hidSystemState) else {
        throw GuiTestFailure.message("Could not create a CGEventSource for \(description).")
    }

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
        throw GuiTestFailure.message("Could not create mouse events for \(description).")
    }

    mouseDown.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.08)
    mouseUp.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.2)
}

func wait(timeout: TimeInterval, interval: TimeInterval, until condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if condition() {
            return true
        }
        Thread.sleep(forTimeInterval: interval)
    } while Date() < deadline
    return condition()
}

func waitForValue<T>(timeout: TimeInterval, interval: TimeInterval, producer: () -> T?) -> T? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if let value = producer() {
            return value
        }
        Thread.sleep(forTimeInterval: interval)
    } while Date() < deadline
    return producer()
}

func runHisleCLI(arguments: [String] = []) throws -> String {
    guard FileManager.default.isExecutableFile(atPath: hisleCLIURL.path) else {
        throw GuiTestFailure.message(
            "Bundled hisle CLI was not found or is not executable at \(hisleCLIURL.path). Run make install-debug, then rerun the GUI test."
        )
    }

    let process = Process()
    let stdout = Pipe()
    let stderr = Pipe()
    process.executableURL = hisleCLIURL
    process.arguments = arguments
    process.standardOutput = stdout
    process.standardError = stderr

    do {
        try process.run()
    } catch {
        throw GuiTestFailure.message("Could not run bundled hisle CLI at \(hisleCLIURL.path): \(error).")
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
        throw GuiTestFailure.message(
            "Bundled hisle CLI exited with status \(process.terminationStatus). stderr: \(String(reflecting: stderrText))"
        )
    }

    return stdoutText.trimmingCharacters(in: .whitespacesAndNewlines)
}

func verifyHisleCLIMode(_ expected: String, stage: String) throws {
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
            throw GuiTestFailure.message("\(stage) CLI mode verification failed: \(lastFailure)")
        }

        throw GuiTestFailure.message(
            "\(stage) CLI mode verification failed. Expected \(String(reflecting: expected)), got \(String(reflecting: lastOutput))."
        )
    }

    print("\(stage) CLI mode verified: \(expected)")
}

private let guiTestTimestampFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

func guiTestTimestamp(_ date: Date = Date()) -> String {
    guiTestTimestampFormatter.string(from: date)
}
