import AppKit
import Engine
import Platform

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let statusBar = StatusBarController()
statusBar.onQuit = { app.terminate(nil) }
// полный wiring — Task 13; здесь только сборка и запуск run loop
app.run()
