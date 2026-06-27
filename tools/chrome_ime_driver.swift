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
private let chromeTargetKind = ProcessInfo.processInfo.environment["HISLE_CHROME_TARGET"] ?? "textarea"
private let chromeScenario = ProcessInfo.processInfo.environment["HISLE_CHROME_SCENARIO"] ?? "standard"
private let delayMinMilliseconds = environmentInteger("HISLE_CHROME_DELAY_MIN_MS", defaultValue: 55, minimum: 0)
private let delayMaxMilliseconds = environmentInteger("HISLE_CHROME_DELAY_MAX_MS", defaultValue: 100, minimum: 0)
private let idleMilliseconds = environmentInteger("HISLE_CHROME_IDLE_MS", defaultValue: 900, minimum: 0)
private let skipFocusClick = ProcessInfo.processInfo.environment["HISLE_CHROME_SKIP_FOCUS_CLICK"] == "1"
private let clickInitialCaret = ProcessInfo.processInfo.environment["HISLE_CHROME_CLICK_INITIAL_CARET"] == "1"
private let clickScreenDX = environmentDouble("HISLE_CHROME_CLICK_SCREEN_DX", defaultValue: 0)
private let clickScreenDY = environmentDouble("HISLE_CHROME_CLICK_SCREEN_DY", defaultValue: 0)
private let expectedValueOverride = ProcessInfo.processInfo.environment["EXPECTED_VALUE"].flatMap {
    $0.isEmpty ? nil : $0
}

private func logShowStartArgument(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter.string(from: date)
}

private func writeRuntimeIdentityLog(to outputURL: URL, since startDate: Date) {
    let process = Process()
    let pipe = Pipe()

    process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
    process.arguments = [
        "show",
        "--style", "compact",
        "--start", logShowStartArgument(for: startDate),
        "--predicate", "subsystem == \"hooreique.inputmethod.hisle\" && eventMessage CONTAINS \"controller runtime\"",
    ]
    process.standardOutput = pipe
    process.standardError = pipe

    do {
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        try data.write(to: outputURL)
    } catch {
        let message = "Failed to capture runtime identity log: \(error)\n"
        try? message.write(to: outputURL, atomically: true, encoding: .utf8)
    }
}

private func environmentInteger(_ name: String, defaultValue: Int, minimum: Int) -> Int {
    guard let text = ProcessInfo.processInfo.environment[name],
          !text.isEmpty,
          let value = Int(text)
    else {
        return defaultValue
    }
    return max(minimum, value)
}

private func environmentDouble(_ name: String, defaultValue: Double) -> Double {
    guard let text = ProcessInfo.processInfo.environment[name],
          !text.isEmpty,
          let value = Double(text)
    else {
        return defaultValue
    }
    return value
}

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

private struct ObserverReadyMetadata {
    let initialCaretScreenPoint: CGPoint?
    let initialCaretClientPoint: CGPoint?
    let clickAfterInputScreenPoint: CGPoint?
    let clickAfterInputClientPoint: CGPoint?
    let dragSelectionStartScreenPoint: CGPoint?
    let dragSelectionStartClientPoint: CGPoint?
    let dragSelectionEndScreenPoint: CGPoint?
    let dragSelectionEndClientPoint: CGPoint?

    static func load(from url: URL) -> ObserverReadyMetadata {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let initialState = root["initial_state"] as? [String: Any]
        else {
            return ObserverReadyMetadata(
                initialCaretScreenPoint: nil,
                initialCaretClientPoint: nil,
                clickAfterInputScreenPoint: nil,
                clickAfterInputClientPoint: nil,
                dragSelectionStartScreenPoint: nil,
                dragSelectionStartClientPoint: nil,
                dragSelectionEndScreenPoint: nil,
                dragSelectionEndClientPoint: nil
            )
        }

        let screenPoint = Self.point(from: initialState["estimated_screen_point"])
        let clientPoint = Self.point(from: initialState["caret_client_point"])
        let clickAfterInputScreenPoint = Self.point(from: initialState["click_after_input_screen_point"])
        let clickAfterInputClientPoint = Self.point(from: initialState["click_after_input_client_point"])
        let dragSelectionStartScreenPoint = Self.point(from: initialState["drag_selection_start_screen_point"])
        let dragSelectionStartClientPoint = Self.point(from: initialState["drag_selection_start_client_point"])
        let dragSelectionEndScreenPoint = Self.point(from: initialState["drag_selection_end_screen_point"])
        let dragSelectionEndClientPoint = Self.point(from: initialState["drag_selection_end_client_point"])

        return ObserverReadyMetadata(
            initialCaretScreenPoint: screenPoint,
            initialCaretClientPoint: clientPoint,
            clickAfterInputScreenPoint: clickAfterInputScreenPoint,
            clickAfterInputClientPoint: clickAfterInputClientPoint,
            dragSelectionStartScreenPoint: dragSelectionStartScreenPoint,
            dragSelectionStartClientPoint: dragSelectionStartClientPoint,
            dragSelectionEndScreenPoint: dragSelectionEndScreenPoint,
            dragSelectionEndClientPoint: dragSelectionEndClientPoint
        )
    }

    private static func point(from value: Any?) -> CGPoint? {
        (value as? [String: Any]).flatMap { point -> CGPoint? in
            guard let x = point["x"] as? Double,
                  let y = point["y"] as? Double else {
                return nil
            }
            return CGPoint(x: x, y: y)
        }
    }
}

private func adjustedClickPoint(_ point: CGPoint) -> CGPoint {
    CGPoint(x: point.x + clickScreenDX, y: point.y + clickScreenDY)
}

private func observedScreenPoint(
    clientPoint: CGPoint?,
    screenPoint: CGPoint?,
    focusedApp: NSRunningApplication
) -> CGPoint? {
    if let clientPoint,
       let webAreaFrame = focusedWebAreaFrame(for: focusedApp) {
        return CGPoint(x: webAreaFrame.minX + clientPoint.x, y: webAreaFrame.minY + clientPoint.y)
    }

    return screenPoint
}

private final class SeededDelayGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 1 : seed
    }

    func nextDelay() -> TimeInterval {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let minDelay = min(delayMinMilliseconds, delayMaxMilliseconds)
        let maxDelay = max(delayMinMilliseconds, delayMaxMilliseconds)
        let spread = maxDelay - minDelay + 1
        let milliseconds = minDelay + Int((state >> 32) % UInt64(spread))
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
private func focusChromeTestWindow(allowFocusClick: Bool = true) throws -> NSRunningApplication {
    guard let app = waitForValue(timeout: chromeLaunchTimeout, interval: 0.25, producer: chromeAppWithTestWindow) else {
        throw GuiTestFailure.message(
            "Timed out waiting for Chrome to open the \(chromeTargetKind) test page."
        )
    }

    var didClick = false
    let focused = wait(timeout: chromeFocusTimeout, interval: 0.25) {
        activate(app)

        if allowFocusClick,
           NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier, !didClick {
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
            "Target: \(chromeTargetKind). " +
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

private func typeClickDuringCompositionSequence(
    keyboard: KeyboardDriver,
    delays: SeededDelayGenerator
) throws {
    print("Typing Chrome IME click-during-composition sequence")
    try verifyHisleCLIMode("roman", stage: "Click scenario initial mode")
    try keyboard.tapCommandShortcut(KeyCode.downArrow)
    Thread.sleep(forTimeInterval: 0.2)
    try tapModifier(KeyCode.rightShift, keyboard: keyboard, delays: delays, flag: .maskShift)
    try verifyHisleCLIMode("hangul", stage: "Click scenario right Shift")
    try tapKey(KeyCode.j, keyboard: keyboard, delays: delays)

    let app = try focusChromeTestWindow(allowFocusClick: chromeScenario != "click-during-composition")
    if chromeScenario != "click-during-composition" {
        try clickFocusedWindowCenter(of: app, appName: chromeAppName)
    }
    Thread.sleep(forTimeInterval: 0.25)

    try tapKey(KeyCode.g, keyboard: keyboard, delays: delays)
    try tapKey(KeyCode.d, keyboard: keyboard, delays: delays)
    try tapModifier(KeyCode.leftShift, keyboard: keyboard, delays: delays, flag: .maskShift)
    try verifyHisleCLIMode("roman", stage: "Click scenario left Shift")
    try tapKey(KeyCode.e, keyboard: keyboard, delays: delays)
}

private func typeIdleStressSequence(
    keyboard: KeyboardDriver,
    delays: SeededDelayGenerator,
    iterations: Int
) throws {
    print("Typing Chrome IME idle-stress sequence for \(iterations) iterations")
    try verifyHisleCLIMode("roman", stage: "Idle stress initial mode")
    try tapModifier(KeyCode.rightShift, keyboard: keyboard, delays: delays, flag: .maskShift)
    try verifyHisleCLIMode("hangul", stage: "Idle stress right Shift")

    let idleDelay = TimeInterval(idleMilliseconds) / 1000.0
    for iteration in 1...iterations {
        print("Idle-stress iteration \(iteration)/\(iterations)")
        try tapKey(KeyCode.j, keyboard: keyboard, delays: delays)
        Thread.sleep(forTimeInterval: idleDelay)
        try tapKey(KeyCode.g, keyboard: keyboard, delays: delays)
        try tapKey(KeyCode.d, keyboard: keyboard, delays: delays)
        Thread.sleep(forTimeInterval: idleDelay)
        try tapKey(KeyCode.j, keyboard: keyboard, delays: delays)
        try tapKey(KeyCode.t, keyboard: keyboard, delays: delays)
        try tapKey(KeyCode.b, keyboard: keyboard, delays: delays)

        if iteration % 3 == 0 {
            try tapKey(KeyCode.space, keyboard: keyboard, delays: delays)
        }

        Thread.sleep(forTimeInterval: idleDelay)
    }

    try tapModifier(KeyCode.leftShift, keyboard: keyboard, delays: delays, flag: .maskShift)
    try verifyHisleCLIMode("roman", stage: "Idle stress left Shift")
    try tapKey(KeyCode.e, keyboard: keyboard, delays: delays)
}

private func typeMidlineInsertSequence(
    keyboard: KeyboardDriver,
    delays: SeededDelayGenerator
) throws {
    print("Typing Chrome IME midline-insert sequence")
    try verifyHisleCLIMode("roman", stage: "Midline insert initial mode")
    try tapModifier(KeyCode.rightShift, keyboard: keyboard, delays: delays, flag: .maskShift)
    try verifyHisleCLIMode("hangul", stage: "Midline insert right Shift")
    try tapKey(KeyCode.j, keyboard: keyboard, delays: delays)
    try tapKey(KeyCode.g, keyboard: keyboard, delays: delays)
    try tapKey(KeyCode.d, keyboard: keyboard, delays: delays)
    try tapKey(KeyCode.escape, keyboard: keyboard, delays: delays)
    try verifyHisleCLIMode("roman", stage: "Midline insert Escape")
}

private func typeTwoInsertMoveSequence(
    keyboard: KeyboardDriver,
    delays: SeededDelayGenerator
) throws {
    print("Typing Chrome IME two-insert-move sequence")
    try verifyHisleCLIMode("roman", stage: "Two insert initial mode")
    try tapModifier(KeyCode.rightShift, keyboard: keyboard, delays: delays, flag: .maskShift)
    try verifyHisleCLIMode("hangul", stage: "Two insert first right Shift")
    try tapKey(KeyCode.j, keyboard: keyboard, delays: delays)
    try tapKey(KeyCode.g, keyboard: keyboard, delays: delays)
    try tapKey(KeyCode.d, keyboard: keyboard, delays: delays)
    try tapKey(KeyCode.escape, keyboard: keyboard, delays: delays)
    try verifyHisleCLIMode("roman", stage: "Two insert first Escape")

    Thread.sleep(forTimeInterval: TimeInterval(idleMilliseconds) / 1000.0)

    try tapModifier(KeyCode.rightShift, keyboard: keyboard, delays: delays, flag: .maskShift)
    try verifyHisleCLIMode("hangul", stage: "Two insert second right Shift")
    try tapKey(KeyCode.j, keyboard: keyboard, delays: delays)
    try tapKey(KeyCode.g, keyboard: keyboard, delays: delays)
    try tapKey(KeyCode.d, keyboard: keyboard, delays: delays)
    try tapKey(KeyCode.escape, keyboard: keyboard, delays: delays)
    try verifyHisleCLIMode("roman", stage: "Two insert second Escape")
}

private func typeActiveMoveContinueSequence(
    keyboard: KeyboardDriver,
    delays: SeededDelayGenerator
) throws {
    print("Typing Chrome IME active-move-continue sequence")
    try verifyHisleCLIMode("roman", stage: "Active move initial mode")
    try tapModifier(KeyCode.rightShift, keyboard: keyboard, delays: delays, flag: .maskShift)
    try verifyHisleCLIMode("hangul", stage: "Active move right Shift")
    try tapKey(KeyCode.j, keyboard: keyboard, delays: delays)
    Thread.sleep(forTimeInterval: TimeInterval(idleMilliseconds) / 1000.0)
    try tapKey(KeyCode.g, keyboard: keyboard, delays: delays)
    try tapKey(KeyCode.d, keyboard: keyboard, delays: delays)
    try tapKey(KeyCode.escape, keyboard: keyboard, delays: delays)
    try verifyHisleCLIMode("roman", stage: "Active move Escape")
}

private func typeClickMoveContinueSequence(
    keyboard: KeyboardDriver,
    delays: SeededDelayGenerator,
    clickPoint: CGPoint
) throws {
    print("Typing Chrome IME click-move-continue sequence")
    try verifyHisleCLIMode("roman", stage: "Click move initial mode")
    try tapModifier(KeyCode.rightShift, keyboard: keyboard, delays: delays, flag: .maskShift)
    try verifyHisleCLIMode("hangul", stage: "Click move right Shift")
    try tapKey(KeyCode.j, keyboard: keyboard, delays: delays)
    Thread.sleep(forTimeInterval: TimeInterval(idleMilliseconds) / 1000.0)
    print("Clicking after first input screen point: \(clickPoint)")
    try clickScreenPoint(clickPoint, description: "Chrome click move caret")
    Thread.sleep(forTimeInterval: 0.2)
    try tapKey(KeyCode.g, keyboard: keyboard, delays: delays)
    try tapKey(KeyCode.d, keyboard: keyboard, delays: delays)
    try tapKey(KeyCode.escape, keyboard: keyboard, delays: delays)
    try verifyHisleCLIMode("roman", stage: "Click move Escape")
}

private func typeDragSelectionInputSequence(
    keyboard: KeyboardDriver,
    delays: SeededDelayGenerator,
    selectionStartPoint: CGPoint,
    selectionEndPoint: CGPoint
) throws {
    print("Typing Chrome IME drag-selection-input sequence")
    try verifyHisleCLIMode("roman", stage: "Drag selection input initial mode")
    print("Dragging textarea selection from \(selectionStartPoint) to \(selectionEndPoint)")
    try dragScreenPoint(
        from: selectionStartPoint,
        to: selectionEndPoint,
        description: "Chrome textarea selection"
    )
    try tapModifier(KeyCode.rightShift, keyboard: keyboard, delays: delays, flag: .maskShift)
    try verifyHisleCLIMode("hangul", stage: "Drag selection input right Shift")
    try tapKey(KeyCode.j, keyboard: keyboard, delays: delays)
    Thread.sleep(forTimeInterval: TimeInterval(idleMilliseconds) / 1000.0)
}

private func typeSelectedRangeInputSequence(
    keyboard: KeyboardDriver,
    delays: SeededDelayGenerator
) throws {
    print("Typing Chrome IME selected-range-input sequence")
    try verifyHisleCLIMode("roman", stage: "Selected range input initial mode")
    try tapModifier(KeyCode.rightShift, keyboard: keyboard, delays: delays, flag: .maskShift)
    try verifyHisleCLIMode("hangul", stage: "Selected range input right Shift")
    try tapKey(KeyCode.j, keyboard: keyboard, delays: delays)
    Thread.sleep(forTimeInterval: TimeInterval(idleMilliseconds) / 1000.0)
}

private func typeSelectedRangeNumbersSequence(
    keyboard: KeyboardDriver,
    delays: SeededDelayGenerator
) throws {
    print("Typing Chrome IME selected-range-numbers sequence")
    try verifyHisleCLIMode("roman", stage: "Selected range numbers initial mode")
    try tapModifier(KeyCode.rightShift, keyboard: keyboard, delays: delays, flag: .maskShift)
    try verifyHisleCLIMode("hangul", stage: "Selected range numbers right Shift")

    for keyCode in [
        KeyCode.one,
        KeyCode.two,
        KeyCode.three,
    ] {
        try tapKey(keyCode, keyboard: keyboard, delays: delays)
    }

    Thread.sleep(forTimeInterval: TimeInterval(idleMilliseconds) / 1000.0)
}

private func typeSelectedRangeAnnyeonghaseyoSequence(
    keyboard: KeyboardDriver,
    delays: SeededDelayGenerator,
    scenarioName: String = "selected-range-annyeonghaseyo"
) throws {
    print("Typing Chrome IME \(scenarioName) sequence")
    try verifyHisleCLIMode("roman", stage: "\(scenarioName) initial mode")
    try tapModifier(KeyCode.rightShift, keyboard: keyboard, delays: delays, flag: .maskShift)
    try verifyHisleCLIMode("hangul", stage: "\(scenarioName) right Shift")

    for keyCode in [
        KeyCode.j, KeyCode.f, KeyCode.s,
        KeyCode.h, KeyCode.e, KeyCode.a,
        KeyCode.m, KeyCode.f,
        KeyCode.n, KeyCode.c,
        KeyCode.j, KeyCode.four,
    ] {
        try tapKey(keyCode, keyboard: keyboard, delays: delays)
    }

    Thread.sleep(forTimeInterval: TimeInterval(idleMilliseconds) / 1000.0)
}

private func typeDoubleClickSelectionAnnyeonghaseyoSequence(
    keyboard: KeyboardDriver,
    delays: SeededDelayGenerator,
    clickPoint: CGPoint
) throws {
    print("Typing Chrome IME double-click-selection-annyeonghaseyo sequence")
    try verifyHisleCLIMode("roman", stage: "Double click selection initial mode")
    Thread.sleep(forTimeInterval: 0.7)
    print("Double-clicking content word at \(clickPoint)")
    try doubleClickScreenPoint(clickPoint, description: "Chrome double-click word selection")
    try tapModifier(KeyCode.rightShift, keyboard: keyboard, delays: delays, flag: .maskShift)
    try verifyHisleCLIMode("hangul", stage: "Double click selection right Shift")

    for keyCode in [
        KeyCode.j, KeyCode.f, KeyCode.s,
        KeyCode.h, KeyCode.e, KeyCode.a,
        KeyCode.m, KeyCode.f,
        KeyCode.n, KeyCode.c,
        KeyCode.j, KeyCode.four,
    ] {
        try tapKey(keyCode, keyboard: keyboard, delays: delays)
    }

    Thread.sleep(forTimeInterval: TimeInterval(idleMilliseconds) / 1000.0)
}

private func runChromeDriver() throws {
    let options = try DriverOptions.parse(arguments: Array(CommandLine.arguments.dropFirst()))
    try requireAccessibilityPermission(rerunCommand: "make chrome-ime-repro")
    try waitForObserverReadiness(options.readyFile)
    let observerReady = ObserverReadyMetadata.load(from: options.readyFile)

    let originalInputSourceID = currentInputSourceID()
    let driverStartTime = guiTestTimestamp()
    let expectedText = expectedValueOverride ?? String(repeating: expectedUnitText, count: options.iterations)
    let driverStateURL = options.runDirectory.appendingPathComponent("driver-state.json")
    try writeJSONObject(
        [
            "active_input_source_before_selection": originalInputSourceID ?? NSNull(),
            "driver_start_time": driverStartTime,
            "expected_value": expectedText,
            "iteration_count": options.iterations,
            "seed": options.seed,
            "scenario": chromeScenario,
            "selected_input_source_id": hisleInputSourceID,
            "target_kind": chromeTargetKind,
            "delay_min_milliseconds": delayMinMilliseconds,
            "delay_max_milliseconds": delayMaxMilliseconds,
            "idle_milliseconds": idleMilliseconds,
            "click_initial_caret": clickInitialCaret,
            "skip_focus_click": skipFocusClick,
        ],
        to: driverStateURL
    )

    var didSelectHisle = false
    defer {
        if didSelectHisle, let originalInputSourceID, originalInputSourceID != hisleInputSourceID {
            try? selectInputSource(id: originalInputSourceID)
        }
    }

    let shouldClickToFocus = !skipFocusClick &&
        chromeScenario != "click-during-composition" &&
        chromeScenario != "selected-range-input" &&
        chromeScenario != "selected-range-numbers" &&
        chromeScenario != "selected-range-annyeonghaseyo" &&
        chromeScenario != "stale-selection-annyeonghaseyo" &&
        chromeScenario != "double-click-selection-annyeonghaseyo"
    let app = try focusChromeTestWindow(allowFocusClick: shouldClickToFocus)
    if shouldClickToFocus {
        try clickFocusedWindowCenter(of: app, appName: chromeAppName)
    }

    let runtimeIdentityLogStartDate = Date()
    print("Selecting hisle input source: \(hisleInputSourceID)")
    try selectInputSource(id: hisleInputSourceID)
    didSelectHisle = true
    Thread.sleep(forTimeInterval: 0.3)

    let focusedApp = try focusChromeTestWindow(allowFocusClick: shouldClickToFocus)
    if shouldClickToFocus {
        try clickFocusedWindowCenter(of: focusedApp, appName: chromeAppName)
    }
    if clickInitialCaret {
        let point: CGPoint?
        if let clientPoint = observerReady.initialCaretClientPoint,
           let webAreaFrame = focusedWebAreaFrame(for: focusedApp) {
            point = CGPoint(x: webAreaFrame.minX + clientPoint.x, y: webAreaFrame.minY + clientPoint.y)
            print("Using Chrome AXWebArea frame for initial caret click: \(webAreaFrame)")
        } else {
            point = observerReady.initialCaretScreenPoint
        }

        guard let point else {
            throw GuiTestFailure.message("HISLE_CHROME_CLICK_INITIAL_CARET is set, but observer-ready.json has no initial caret screen point.")
        }
        let adjustedPoint = adjustedClickPoint(point)
        print("Clicking initial caret screen point: \(adjustedPoint)")
        try clickScreenPoint(adjustedPoint, description: "Chrome initial caret")
    }

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

    switch chromeScenario {
    case "standard":
        try typeDiagnosticSequence(keyboard: keyboard, delays: delays, iterations: options.iterations)
    case "click-during-composition":
        try typeClickDuringCompositionSequence(keyboard: keyboard, delays: delays)
    case "idle-stress":
        try typeIdleStressSequence(keyboard: keyboard, delays: delays, iterations: options.iterations)
    case "midline-insert":
        try typeMidlineInsertSequence(keyboard: keyboard, delays: delays)
    case "two-insert-move":
        try typeTwoInsertMoveSequence(keyboard: keyboard, delays: delays)
    case "active-move-continue":
        try typeActiveMoveContinueSequence(keyboard: keyboard, delays: delays)
    case "click-move-continue":
        guard let point = observerReady.clickAfterInputScreenPoint else {
            throw GuiTestFailure.message("HISLE_CHROME_CLICK_AFTER_INPUT_CARET is required for click-move-continue.")
        }
        try typeClickMoveContinueSequence(keyboard: keyboard, delays: delays, clickPoint: adjustedClickPoint(point))
    case "drag-selection-input":
        let startPoint = observedScreenPoint(
            clientPoint: observerReady.dragSelectionStartClientPoint,
            screenPoint: observerReady.dragSelectionStartScreenPoint,
            focusedApp: focusedApp
        )
        let endPoint = observedScreenPoint(
            clientPoint: observerReady.dragSelectionEndClientPoint,
            screenPoint: observerReady.dragSelectionEndScreenPoint,
            focusedApp: focusedApp
        )
        guard let startPoint, let endPoint else {
            throw GuiTestFailure.message("HISLE_CHROME_DRAG_SELECTION is required for drag-selection-input.")
        }
        try typeDragSelectionInputSequence(
            keyboard: keyboard,
            delays: delays,
            selectionStartPoint: adjustedClickPoint(startPoint),
            selectionEndPoint: adjustedClickPoint(endPoint)
        )
    case "selected-range-input":
        try typeSelectedRangeInputSequence(keyboard: keyboard, delays: delays)
    case "selected-range-numbers":
        try typeSelectedRangeNumbersSequence(keyboard: keyboard, delays: delays)
    case "selected-range-annyeonghaseyo":
        try typeSelectedRangeAnnyeonghaseyoSequence(keyboard: keyboard, delays: delays)
    case "stale-selection-annyeonghaseyo":
        try typeSelectedRangeAnnyeonghaseyoSequence(
            keyboard: keyboard,
            delays: delays,
            scenarioName: chromeScenario
        )
    case "double-click-selection-annyeonghaseyo":
        let point = observedScreenPoint(
            clientPoint: observerReady.initialCaretClientPoint,
            screenPoint: observerReady.initialCaretScreenPoint,
            focusedApp: focusedApp
        )
        guard let point else {
            throw GuiTestFailure.message("HISLE_CHROME_INITIAL_CARET is required for double-click-selection-annyeonghaseyo.")
        }
        try typeDoubleClickSelectionAnnyeonghaseyoSequence(
            keyboard: keyboard,
            delays: delays,
            clickPoint: adjustedClickPoint(point)
        )
    default:
        throw GuiTestFailure.message("Unsupported HISLE_CHROME_SCENARIO: \(chromeScenario)")
    }
    try keyLogger.throwIfFailed()
    writeRuntimeIdentityLog(
        to: options.runDirectory.appendingPathComponent("runtime-identity.log"),
        since: runtimeIdentityLogStartDate
    )
    print("Chrome IME HID sequence completed. Target: \(chromeTargetKind). Scenario: \(chromeScenario). Expected final value: \(String(reflecting: expectedText))")
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
