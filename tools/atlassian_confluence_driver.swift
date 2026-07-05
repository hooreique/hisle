// swiftlint:disable:next blanket_disable_command
// swiftlint:disable file_length function_body_length

import Cocoa
import Foundation

private let chromeAppName = "Google Chrome"
private let chromeAlternateAppNames = ["Google Chrome for Testing", "Google Chrome Canary"]
private let chromeBundleIDs = [
    "com.google.Chrome",
    "com.google.Chrome.forTesting",
    "com.google.Chrome.canary"
]
private let chromeLaunchTimeout: TimeInterval = 60.0
private let chromeFocusTimeout: TimeInterval = 20.0
private let delayMinMilliseconds = environmentInteger("HISLE_ATLASSIAN_DELAY_MIN_MS", defaultValue: 70, minimum: 0)
private let delayMaxMilliseconds = environmentInteger("HISLE_ATLASSIAN_DELAY_MAX_MS", defaultValue: 120, minimum: 0)
private let idleMilliseconds = environmentInteger("HISLE_ATLASSIAN_IDLE_MS", defaultValue: 1100, minimum: 0)
private let clickScreenDX = environmentDouble("HISLE_ATLASSIAN_CLICK_SCREEN_DX", defaultValue: 0)
private let clickScreenDY = environmentDouble("HISLE_ATLASSIAN_CLICK_SCREEN_DY", defaultValue: 0)
private let skipEditorClick = ProcessInfo.processInfo.environment["HISLE_ATLASSIAN_SKIP_EDITOR_CLICK"] == "1"
private let hangulBeforeEditorClick = ProcessInfo.processInfo.environment[
    "HISLE_ATLASSIAN_HANGUL_BEFORE_EDITOR_CLICK"
] == "1"
private let initialCaretOffset = ProcessInfo.processInfo.environment["HISLE_ATLASSIAN_INITIAL_CARET_OFFSET"] ?? ""
private let atlassianScenario = ProcessInfo.processInfo.environment["HISLE_ATLASSIAN_SCENARIO"] ?? "annyeonghaseyo"
private let atlassianWordCount = environmentInteger("HISLE_ATLASSIAN_WORD_COUNT", defaultValue: 3, minimum: 1)
private let expectedText = ProcessInfo.processInfo.environment["HISLE_ATLASSIAN_EXPECTED_TEXT"]
    .flatMap { $0.isEmpty ? nil : $0 } ?? "안녕하세요"

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
        "--predicate", "subsystem == \"hooreique.inputmethod.hisle\" && eventMessage CONTAINS \"controller runtime\""
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

private struct DriverOptions {
    let runDirectory: URL
    let readyFile: URL
    let seed: UInt64

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

        return DriverOptions(
            runDirectory: URL(fileURLWithPath: runDirectoryPath),
            readyFile: URL(fileURLWithPath: readyFilePath),
            seed: seed
        )
    }
}

private struct ObserverReadyMetadata {
    let observerPort: Int?
    let windowTitleContains: String
    let editorClickClientPoint: CGPoint?
    let editorClickScreenPoint: CGPoint?
    let currentPageURL: String?
    let profileDirectory: String?

    static func load(from url: URL) -> ObserverReadyMetadata {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return ObserverReadyMetadata(
                observerPort: nil,
                windowTitleContains: "Confluence",
                editorClickClientPoint: nil,
                editorClickScreenPoint: nil,
                currentPageURL: nil,
                profileDirectory: nil
            )
        }

        let editorState = root["editor_state"] as? [String: Any]
        let clientPoint = Self.point(from: root["editor_click_client_point"]) ??
            Self.point(from: editorState?["editor_click_client_point"])
        let screenPoint = Self.point(from: root["editor_click_screen_point"]) ??
            Self.point(from: editorState?["editor_click_screen_point"])
        let title = root["window_title_contains"] as? String

        return ObserverReadyMetadata(
            observerPort: root["observer_port"] as? Int,
            windowTitleContains: (title?.isEmpty == false ? title : "Confluence") ?? "Confluence",
            editorClickClientPoint: clientPoint,
            editorClickScreenPoint: screenPoint,
            currentPageURL: root["current_page_url"] as? String,
            profileDirectory: root["profile_dir"] as? String
        )
    }

    private static func point(from value: Any?) -> CGPoint? {
        (value as? [String: Any]).flatMap { point -> CGPoint? in
            guard let pointX = point["x"] as? Double,
                  let pointY = point["y"] as? Double else {
                return nil
            }
            return CGPoint(x: pointX, y: pointY)
        }
    }
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
                "planned_delay_seconds": event.plannedDelay
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

private func title(_ title: String?, contains needle: String) -> Bool {
    guard let title else {
        return false
    }
    return title.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
}

private func chromeAppWithWindow(containing titleNeedle: String) -> NSRunningApplication? {
    for app in runningChromeApplications() {
        activate(app)
        if title(focusedWindowTitle(for: app), contains: titleNeedle) {
            return app
        }
    }
    return nil
}

@discardableResult
private func focusChromeWindow(containing titleNeedle: String) throws -> NSRunningApplication {
    guard let app = waitForValue(
        timeout: chromeLaunchTimeout,
        interval: 0.25,
        producer: { chromeAppWithWindow(containing: titleNeedle) }
    ) else {
        throw GuiTestFailure.message(
            "Timed out waiting for Chrome to open a window containing " +
                "\(String(reflecting: titleNeedle))."
        )
    }

    let focused = wait(timeout: chromeFocusTimeout, interval: 0.25) {
        activate(app)
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier &&
            title(focusedWindowTitle(for: app), contains: titleNeedle)
    }

    guard focused else {
        let frontmost = NSWorkspace.shared.frontmostApplication?.localizedName ?? "<unknown>"
        let chromeTitle = focusedWindowTitle(for: app) ?? "<unknown>"
        throw GuiTestFailure.message(
            "Chrome is not focused on the Confluence test page. " +
                "Frontmost app: \(frontmost). Chrome front window title: \(chromeTitle). " +
                "Expected title to contain: \(String(reflecting: titleNeedle))."
        )
    }

    return app
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
        print("Using Chrome AXWebArea frame for Confluence editor click: \(webAreaFrame)")
        return CGPoint(x: webAreaFrame.minX + clientPoint.x, y: webAreaFrame.minY + clientPoint.y)
    }

    return screenPoint
}

private func waitForObserverReadiness(_ readyFile: URL) throws {
    let isReady = wait(timeout: 60.0, interval: 0.1) {
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

private func typeAnnyeonghaseyoSequence(
    keyboard: KeyboardDriver,
    delays: SeededDelayGenerator,
    hangulAlreadySelected: Bool,
    observerPort: Int?
) throws {
    print("Typing Confluence IME sequence. Expected visible text contains: \(String(reflecting: expectedText))")
    if hangulAlreadySelected {
        try verifyHisleCLIMode("hangul", stage: "Confluence pre-focus Hangul mode")
        try placeObserverCaretIfRequested(observerPort: observerPort)
        try tapModifier(KeyCode.rightShift, keyboard: keyboard, delays: delays, flag: .maskShift)
        try verifyHisleCLIMode("hangul", stage: "Confluence right Shift after caret placement")
    } else {
        try verifyHisleCLIMode("roman", stage: "Confluence initial mode")
        try placeObserverCaretIfRequested(observerPort: observerPort)
        try tapModifier(KeyCode.rightShift, keyboard: keyboard, delays: delays, flag: .maskShift)
        try verifyHisleCLIMode("hangul", stage: "Confluence right Shift")
    }

    try typeAnnyeonghaseyoSyllables(keyboard: keyboard, delays: delays)

    Thread.sleep(forTimeInterval: TimeInterval(idleMilliseconds) / 1000.0)
}

private func typeAnnyeonghaseyoWordsSequence(
    keyboard: KeyboardDriver,
    delays: SeededDelayGenerator,
    hangulAlreadySelected: Bool,
    observerPort: Int?
) throws {
    print(
        "Typing Confluence IME word sequence. " +
            "Words: \(atlassianWordCount). Expected visible text contains: \(String(reflecting: expectedText))"
    )
    if hangulAlreadySelected {
        try verifyHisleCLIMode("hangul", stage: "Confluence pre-focus Hangul mode")
        try placeObserverCaretIfRequested(observerPort: observerPort)
        try tapModifier(KeyCode.rightShift, keyboard: keyboard, delays: delays, flag: .maskShift)
        try verifyHisleCLIMode("hangul", stage: "Confluence right Shift after caret placement")
    } else {
        try verifyHisleCLIMode("roman", stage: "Confluence initial mode")
        try placeObserverCaretIfRequested(observerPort: observerPort)
        try tapModifier(KeyCode.rightShift, keyboard: keyboard, delays: delays, flag: .maskShift)
        try verifyHisleCLIMode("hangul", stage: "Confluence right Shift")
    }

    for index in 1...atlassianWordCount {
        try typeAnnyeonghaseyoSyllables(keyboard: keyboard, delays: delays)
        if index < atlassianWordCount {
            try tapKey(KeyCode.space, keyboard: keyboard, delays: delays)
        }
    }

    Thread.sleep(forTimeInterval: TimeInterval(idleMilliseconds) / 1000.0)
}

private func placeObserverCaretIfRequested(observerPort: Int?) throws {
    guard !initialCaretOffset.isEmpty else {
        return
    }
    guard let observerPort else {
        throw GuiTestFailure.message("Observer did not report a port for caret placement.")
    }
    guard let url = URL(string: "http://127.0.0.1:\(observerPort)/place-caret") else {
        throw GuiTestFailure.message("Could not build observer caret placement URL.")
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"

    let semaphore = DispatchSemaphore(value: 0)
    var responseData = Data()
    var responseStatus = 0
    var responseError: Error?

    URLSession.shared.dataTask(with: request) { data, response, error in
        if let data {
            responseData = data
        }
        if let response = response as? HTTPURLResponse {
            responseStatus = response.statusCode
        }
        responseError = error
        semaphore.signal()
    }.resume()

    guard semaphore.wait(timeout: .now() + 5) == .success else {
        throw GuiTestFailure.message("Timed out asking observer to place Confluence caret.")
    }
    if let responseError {
        throw GuiTestFailure.message("Could not ask observer to place Confluence caret: \(responseError).")
    }
    guard (200..<300).contains(responseStatus) else {
        let body = String(data: responseData, encoding: .utf8) ?? ""
        throw GuiTestFailure.message(
            "Observer caret placement failed with HTTP \(responseStatus): \(body)"
        )
    }

    let json = (try? JSONSerialization.jsonObject(with: responseData)) as? [String: Any]
    let placedOffset = json?["initial_caret_offset"] ?? "unknown"
    print("Placed Confluence caret before typing at offset: \(placedOffset)")
}

private func typeAnnyeonghaseyoSyllables(
    keyboard: KeyboardDriver,
    delays: SeededDelayGenerator
) throws {
    for keyCode in [
        KeyCode.repJ, KeyCode.repF, KeyCode.repS,
        KeyCode.repH, KeyCode.repE, KeyCode.repA,
        KeyCode.repM, KeyCode.repF,
        KeyCode.repN, KeyCode.repC,
        KeyCode.repJ, KeyCode.four
    ] {
        try tapKey(keyCode, keyboard: keyboard, delays: delays)
    }
}

private func runAtlassianDriver() throws {
    let options = try DriverOptions.parse(arguments: Array(CommandLine.arguments.dropFirst()))
    try requireAccessibilityPermission(
        rerunCommand: "nix develop .#browser --command -- make atlassian-confluence-repro"
    )
    try waitForObserverReadiness(options.readyFile)
    let observerReady = ObserverReadyMetadata.load(from: options.readyFile)

    let originalInputSourceID = currentInputSourceID()
    let driverStartTime = guiTestTimestamp()
    let driverStateURL = options.runDirectory.appendingPathComponent("driver-state.json")
    try writeJSONObject(
        [
            "active_input_source_before_selection": originalInputSourceID ?? NSNull(),
            "driver_start_time": driverStartTime,
            "expected_text": expectedText,
            "scenario": atlassianScenario,
            "word_count": atlassianWordCount,
            "seed": options.seed,
            "selected_input_source_id": hisleInputSourceID,
            "delay_min_milliseconds": delayMinMilliseconds,
            "delay_max_milliseconds": delayMaxMilliseconds,
            "idle_milliseconds": idleMilliseconds,
            "skip_editor_click": skipEditorClick,
            "hangul_before_editor_click": hangulBeforeEditorClick,
            "window_title_contains": observerReady.windowTitleContains,
            "current_page_url": observerReady.currentPageURL ?? NSNull(),
            "profile_dir": observerReady.profileDirectory ?? NSNull()
        ],
        to: driverStateURL
    )

    let runtimeIdentityLogStartDate = Date()
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

    var didSelectHisle = false
    defer {
        if didSelectHisle, let originalInputSourceID, originalInputSourceID != hisleInputSourceID {
            try? selectInputSource(id: originalInputSourceID)
        }
    }

    let focusedApp = try focusChromeWindow(containing: observerReady.windowTitleContains)
    let clickPoint = observedScreenPoint(
        clientPoint: observerReady.editorClickClientPoint,
        screenPoint: observerReady.editorClickScreenPoint,
        focusedApp: focusedApp
    )

    if originalInputSourceID == hisleInputSourceID {
        try switchAwayAndBackToHisle(originalInputSourceID: nil)
        didSelectHisle = true
    } else {
        print("Selecting hisle input source: \(hisleInputSourceID)")
        try selectInputSource(id: hisleInputSourceID)
        didSelectHisle = true
    }
    Thread.sleep(forTimeInterval: 0.3)

    if hangulBeforeEditorClick {
        print("Selecting Hangul mode before focusing the Confluence editor")
        try verifyHisleCLIMode("roman", stage: "Confluence pre-focus initial mode")
        try tapModifier(KeyCode.rightShift, keyboard: keyboard, delays: delays, flag: .maskShift)
        try verifyHisleCLIMode("hangul", stage: "Confluence pre-focus right Shift")
    }

    let refocusedApp = try focusChromeWindow(containing: observerReady.windowTitleContains)
    if !skipEditorClick {
        guard let clickPoint else {
            throw GuiTestFailure.message(
                "Observer did not provide a Confluence editor click point. " +
                    "Set HISLE_ATLASSIAN_SKIP_EDITOR_CLICK=1 only if the editor already has focus."
            )
        }
        let adjustedPoint = adjustedClickPoint(clickPoint)
        print("Clicking Confluence editor screen point: \(adjustedPoint)")
        try clickScreenPoint(adjustedPoint, description: "Confluence editor focus")
        _ = refocusedApp
    }

    if hangulBeforeEditorClick {
        try verifyHisleCLIMode("roman", stage: "Confluence editor-focus Roman initialization")
    }

    switch atlassianScenario {
    case "annyeonghaseyo":
        try typeAnnyeonghaseyoSequence(
            keyboard: keyboard,
            delays: delays,
            hangulAlreadySelected: false,
            observerPort: observerReady.observerPort
        )
    case "annyeonghaseyo-words":
        try typeAnnyeonghaseyoWordsSequence(
            keyboard: keyboard,
            delays: delays,
            hangulAlreadySelected: false,
            observerPort: observerReady.observerPort
        )
    default:
        throw GuiTestFailure.message("Unsupported HISLE_ATLASSIAN_SCENARIO: \(atlassianScenario)")
    }
    try keyLogger.throwIfFailed()
    writeRuntimeIdentityLog(
        to: options.runDirectory.appendingPathComponent("runtime-identity.log"),
        since: runtimeIdentityLogStartDate
    )
    print("Confluence IME HID sequence completed.")
}

@main
private enum AtlassianConfluenceDriver {
    static func main() {
        do {
            try runAtlassianDriver()
        } catch {
            if let failure = error as? GuiTestFailure {
                fputs("Atlassian Confluence driver failed: \(failure.description)\n", stderr)
            } else {
                fputs("Atlassian Confluence driver failed: \(error)\n", stderr)
            }
            exit(1)
        }
    }
}
