import AppKit
import NotchKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = AppController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
    }
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
// App de tipo agente: sin icono en el Dock ni barra de menús propia.
app.setActivationPolicy(.accessory)
app.run()
