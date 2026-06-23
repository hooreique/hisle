import Cocoa
import Foundation

private let chromeAppName = "Google Chrome"
private let chromeAlternateAppNames = ["Google Chrome for Testing", "Google Chrome Canary"]
private let chromeBundleIDs = [
    "com.google.Chrome",
    "com.google.Chrome.forTesting",
    "com.google.Chrome.canary",
]
private let chromeWindowTitle = "hisle Chrome IME Repro"
private let chromeLaunchTimeout: TimeInterval = 45.0
private let chromeFocusTimeout: TimeInterval = 20.0
private let expectedUnitText = "f`\u{C758}f\u{C5B4}\u{315C}f"

private struct DriverOptions {
    let runDirectory: URL
    let readyFile: URL
    let seed: UInt64
    let iterations: Int

    static func parse(arguments: [String]) throws -> DriverOptions {
        var values = [String: String]()
        var index = 0

        while index < arguments.count {
            let key = arguments[index]
            guard key.hasPrefix("--") else {
                throw GuiTestFailure.message("Unexpected argument: \(key)")
            }
            let valueIndex = index + 1
            guard valueIndex < arguments.count else {
                throw GuiTestFailure.message("Missing value for \(key)")
            }
            values[key] = arguments[valueIndex]
            index += 2
        }

        guard let runDirectoryPath = values["--run-dir"], !runDirectoryPath.isEmpty else {
            throw GuiTestFailure.message("Missing required --run-dir argument.")
        }
        guard let readyFilePath = values["--ready-file"], !readyFilePath.isEmpty else {
            throw GuiTestFailure.message("Missing required --ready-file argument.")
        }
        guard let seedText = values["--seed"], let seed = UInt64(seedText) else {
            throw GuiTestFailure.message("Missing or invalid --seed argument.")
        }

        let iterationText = values["--iterations"] ?? "1"
        guard let iterations = Int(iterationText), iterations > 0 else {
            throw GuiTestFailure.message("--iterations must be a positive integer.")
        }

        return DriverOptions(
            runDirectory: URL(fileURLWithPath: runDirectoryPath),
            readyFile: URL(fileURLWithPath: readyFilePath),
            seed: seed,
            iterations: iterations
        )
    }
}

private final class SeededDelayGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 1 : seed
    }

    func nextDelay() -> TimeInterval {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let milliseconds = 55 + Int((state >> 32) % 46)
        return TimeInterval(milliseconds) / 1000.0
    }
}

private final class KeyEventLogger {
    private let handle: FileHandle
    private var failure: Error?

    init(url: URL) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        self.handle = try FileHandle(forWritingTo: url)
    }

    func append(_ event: PostedKeyEvent) {
        guard failure == nil else {
            return
        }

        do {
            let payload: [String: Any] = [
                "sequence": event.sequence,
                "wall_clock_timestamp": guiTestTimestamp(event.wallClock),
                "key_code": Int(event.keyCode),
                "phase": event.phase.rawValue,
                "flags_raw_value": String(event.flags.rawValue),
                "planned_delay_seconds": event.plannedDelay,
            ]
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            handle.write(data)
            handle.write(Data("\n".utf8))
        } catch {
            failure = error
        }
    }

    func close() {
        try? handle.close()
    }

    func throwIfFailed() throws {
        if let failure {
            throw GuiTestFailure.message("Could not write keys.jsonl: \(failure).")
        }
    }
}

private func writeJSONObject(_ value: [String: Any], to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url)
}

private func runningChromeApplications() -> [NSRunningApplication] {
    var appsByProcessID = [pid_t: NSRunningApplication]()

    for bundleID in chromeBundleIDs {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            appsByProcessID[app.processIdentifier] = app
        }
    }

    for app in NSWorkspace.shared.runningApplications where app.localizedName == chromeAppName {
        appsByProcessID[app.processIdentifier] = app
    }
    for name in chromeAlternateAppNames {
        for app in NSWorkspace.shared.runningApplications where app.localizedName == name {
            appsByProcessID[app.processIdentifier] = app
        }
    }

    return Array(appsByProcessID.values)
}

private func chromeAppWithTestWindow() -> NSRunningApplication? {
    for app in runningChromeApplications() {
        activate(app)
        if focusedWindowTitle(for: app)?.contains(chromeWindowTitle) == true {
            return app
        }
    }
    return nil
}

@discardableResult
private func focusChromeTestWindow() throws -> NSRunningApplication {
    guard let app = waitForValue(timeout: chromeLaunchTimeout, interval: 0.25, producer: chromeAppWithTestWindow) else {
        throw GuiTestFailure.message(
            "Timed out waiting for Chrome to open the textarea test page."
        )
    }

    var didClick = false
    let focused = wait(timeout: chromeFocusTimeout, interval: 0.25) {
        activate(app)

        if NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier, !didClick {
            try? clickFocusedWindowCenter(of: app, appName: chromeAppName)
            didClick = true
        }

        return NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier &&
            focusedWindowTitle(for: app)?.contains(chromeWindowTitle) == true
    }

    guard focused else {
        let frontmost = NSWorkspace.shared.frontmostApplication?.localizedName ?? "<unknown>"
        let title = focusedWindowTitle(for: app) ?? "<unknown>"
        throw GuiTestFailure.message(
            "Chrome is not focused on the textarea test page. " +
            "Frontmost app: \(frontmost). Chrome front window title: \(title). Refusing to send GUI key events."
        )
    }

    return app
}

private func waitForObserverReadiness(_ readyFile: URL) throws {
    let isReady = wait(timeout: 45.0, interval: 0.1) {
        FileManager.default.fileExists(atPath: readyFile.path)
    }

    guard isReady else {
        throw GuiTestFailure.message("Timed out waiting for observer readiness file: \(readyFile.path)")
    }
}

private func tapKey(
    _ keyCode: CGKeyCode,
    keyboard: KeyboardDriver,
    delays: SeededDelayGenerator,
    flags: CGEventFlags = CGEventFlags(rawValue: 0)
) throws {
    try keyboard.post(keyCode, keyDown: true, flags: flags, plannedDelay: delays.nextDelay())
    try keyboard.post(keyCode, keyDown: false, flags: flags, plannedDelay: delays.nextDelay())
}

private func tapModifier(
    _ keyCode: CGKeyCode,
    keyboard: KeyboardDriver,
    delays: SeededDelayGenerator,
    flag: CGEventFlags
) throws {
    try keyboard.post(keyCode, keyDown: true, flags: flag, plannedDelay: delays.nextDelay())
    try keyboard.post(keyCode, keyDown: false, plannedDelay: delays.nextDelay())
}

private func typeDiagnosticSequence(
    keyboard: KeyboardDriver,
    delays: SeededDelayGenerator,
    iterations: Int
) throws {
    for iteration in 1...iterations {
        print("Typing Chrome IME sequence iteration \(iteration)/\(iterations)")
        try verifyHisleCLIMode("roman", stage: "Iteration \(iteration) initial mode")
        try tapKey(KeyCode.e, keyboard: keyboard, delays: delays)
        try tapModifier(KeyCode.rightShift, keyboard: keyboard, delays: delays, flag: .maskShift)
        try verifyHisleCLIMode("hangul", stage: "Iteration \(iteration) right Shift")
        try tapKey(KeyCode.backtick, keyboard: keyboard, delays: delays)
        try tapKey(KeyCode.j, keyboard: keyboard, delays: delays)
        try tapKey(KeyCode.g, keyboard: keyboard, delays: delays)
        try tapKey(KeyCode.d, keyboard: keyboard, delays: delays)
        try tapKey(KeyCode.escape, keyboard: keyboard, delays: delays)
        try verifyHisleCLIMode("roman", stage: "Iteration \(iteration) Escape")
        try tapKey(KeyCode.e, keyboard: keyboard, delays: delays)
        try tapModifier(KeyCode.rightShift, keyboard: keyboard, delays: delays, flag: .maskShift)
        try verifyHisleCLIMode("hangul", stage: "Iteration \(iteration) second right Shift")
        try tapKey(KeyCode.j, keyboard: keyboard, delays: delays)
        try tapKey(KeyCode.t, keyboard: keyboard, delays: delays)
        try tapKey(KeyCode.b, keyboard: keyboard, delays: delays)
        try tapModifier(KeyCode.leftShift, keyboard: keyboard, delays: delays, flag: .maskShift)
        try verifyHisleCLIMode("roman", stage: "Iteration \(iteration) left Shift")
        try tapKey(KeyCode.e, keyboard: keyboard, delays: delays)
    }
}

private func runChromeDriver() throws {
    let options = try DriverOptions.parse(arguments: Array(CommandLine.arguments.dropFirst()))
    try requireAccessibilityPermission(rerunCommand: "make chrome-ime-repro")
    try waitForObserverReadiness(options.readyFile)

    let originalInputSourceID = currentInputSourceID()
    let driverStartTime = guiTestTimestamp()
    let expectedText = String(repeating: expectedUnitText, count: options.iterations)
    let driverStateURL = options.runDirectory.appendingPathComponent("driver-state.json")
    try writeJSONObject(
        [
            "active_input_source_before_selection": originalInputSourceID ?? NSNull(),
            "driver_start_time": driverStartTime,
            "expected_value": expectedText,
            "iteration_count": options.iterations,
            "seed": options.seed,
            "selected_input_source_id": hisleInputSourceID,
        ],
        to: driverStateURL
    )

    var didSelectHisle = false
    defer {
        if didSelectHisle, let originalInputSourceID, originalInputSourceID != hisleInputSourceID {
            try? selectInputSource(id: originalInputSourceID)
        }
    }

    let app = try focusChromeTestWindow()
    try clickFocusedWindowCenter(of: app, appName: chromeAppName)

    print("Selecting hisle input source: \(hisleInputSourceID)")
    try selectInputSource(id: hisleInputSourceID)
    didSelectHisle = true
    Thread.sleep(forTimeInterval: 0.3)

    let focusedApp = try focusChromeTestWindow()
    try clickFocusedWindowCenter(of: focusedApp, appName: chromeAppName)

    let logStream = HisleLogStream(outputURL: options.runDirectory.appendingPathComponent("ime.log"))
    try logStream.start()
    defer {
        logStream.stop()
    }
    Thread.sleep(forTimeInterval: 0.5)

    let keyLogger = try KeyEventLogger(url: options.runDirectory.appendingPathComponent("keys.jsonl"))
    defer {
        keyLogger.close()
    }

    let delays = SeededDelayGenerator(seed: options.seed)
    let keyboard = try KeyboardDriver(eventSink: { event in
        keyLogger.append(event)
    })

    try typeDiagnosticSequence(keyboard: keyboard, delays: delays, iterations: options.iterations)
    try keyLogger.throwIfFailed()
    print("Chrome IME HID sequence completed. Expected final textarea value: \(String(reflecting: expectedText))")
}

@main
private enum ChromeIMEDriver {
    static func main() {
        do {
            try runChromeDriver()
        } catch {
            if let failure = error as? GuiTestFailure {
                fputs("Chrome IME driver failed: \(failure.description)\n", stderr)
            } else {
                fputs("Chrome IME driver failed: \(error)\n", stderr)
            }
            exit(1)
        }
    }
}
