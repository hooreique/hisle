import Cocoa

if CommandLine.arguments.contains("--hisle-core-bootstrap-check") {
    HisleCoreBootstrap.runCommandLineCheck()
}

private let appDelegate = AppDelegate()

let app = NSApplication.shared
app.delegate = appDelegate

NSLog("hisle main started")
app.run()
