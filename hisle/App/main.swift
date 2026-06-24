import Cocoa

if CommandLine.arguments.contains("--hisle-core-bootstrap-check") {
    HisleCoreBootstrap.runCommandLineCheck()
}

private let appDelegate = AppDelegate()

let app = NSApplication.shared
app.delegate = appDelegate

#if DEBUG
NSLog("hisle main started")
#endif
app.run()
