import AppKit

/// Elemento propio en la barra de menús: acceso de respaldo al panel, a la
/// configuración y a la salida, ya que la app no aparece en el Dock.
@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let onTogglePanel: () -> Void
    private let onOpenSettings: () -> Void

    init(onTogglePanel: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        self.onTogglePanel = onTogglePanel
        self.onOpenSettings = onOpenSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        statusItem.button?.image = Self.makeIcon()

        let menu = NSMenu()
        menu.addItem(item(String(localized: "Mostrar u ocultar el panel"), #selector(togglePanel)))
        menu.addItem(item(String(localized: "Configuración…"), #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Salir de \(AppIdentity.displayName)"), #selector(quit), key: "q"))
        statusItem.menu = menu
    }

    /// Silueta de una pantalla con su notch. Es una imagen plantilla: macOS
    /// la tiñe según la apariencia de la barra de menús.
    static func makeIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 14), flipped: true) { _ in
            let screen = NSBezierPath(roundedRect: NSRect(x: 1.25, y: 1.25, width: 15.5, height: 11.5), xRadius: 2.5, yRadius: 2.5)
            screen.lineWidth = 1.5
            NSColor.black.setStroke()
            screen.stroke()
            let notch = NSBezierPath(roundedRect: NSRect(x: 6, y: 1, width: 6, height: 3.25), xRadius: 1.5, yRadius: 1.5)
            NSColor.black.setFill()
            notch.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = AppIdentity.displayName
        return image
    }

    func remove() {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func togglePanel() { onTogglePanel() }
    @objc private func openSettings() { onOpenSettings() }
    @objc private func quit() { NSApp.terminate(nil) }
}
