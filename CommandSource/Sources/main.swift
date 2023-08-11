import Cocoa

// `AppDelegete`を設定して、アプリケーションを実行する。

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
