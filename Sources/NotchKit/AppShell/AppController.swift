import AppKit
import SwiftUI

/// Compone la aplicación: preferencias, ventana del notch, módulos, barra de
/// menús y configuración. Es el único tipo que necesita el ejecutable.
@MainActor
public final class AppController {
    private let store = PreferencesStore()
    private let loginItem = LoginItemService()
    private let settingsNavigation = SettingsNavigation()
    private var modules: ModuleCoordinator?
    private var windowController: NotchWindowController?
    private var statusItem: StatusItemController?
    private var settingsWindow: NSWindow?
    private var isStarted = false

    public init() {}

    public func start() {
        guard !isStarted else { return }
        if isAnotherInstanceRunning {
            Log.app.notice("Ya hay otra instancia en ejecución; esta se cierra")
            NSApp.terminate(nil)
            return
        }
        isStarted = true

        // La geometría real se calcula al iniciar la ventana.
        let placeholder = NotchGeometry(screen: ScreenDescriptor(displayID: 0, frame: .zero))
        let model = NotchViewModel(store: store, geometry: placeholder)
        model.onOpenSettings = { [weak self] tab in self?.showSettings(tab) }
        let modules = ModuleCoordinator(store: store, model: model)
        let windowController = NotchWindowController(model: model, modules: modules)
        self.modules = modules
        self.windowController = windowController

        statusItem = StatusItemController(
            onTogglePanel: { [weak windowController] in windowController?.togglePanel() },
            onOpenSettings: { [weak self] in self?.showSettings(.general) }
        )

        observeAppearance()
        windowController.start()
        Log.app.info("Iniciada la versión \(AppIdentity.version, privacy: .public)")

        // Ayuda de desarrollo: `-debugExpand YES` abre el panel al arrancar.
        if UserDefaults.standard.bool(forKey: "debugExpand") { windowController.togglePanel() }
    }

    public func stop() {
        guard isStarted else { return }
        isStarted = false
        windowController?.stop()
        statusItem?.remove()
    }

    private var isAnotherInstanceRunning: Bool {
        guard let identifier = Bundle.main.bundleIdentifier else { return false }
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier).count > 1
    }

    private func observeAppearance() {
        withObservationTracking {
            applyAppearance(store.preferences.appearance)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isStarted else { return }
                self.observeAppearance()
            }
        }
    }

    private func applyAppearance(_ mode: AppearanceMode) {
        switch mode {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func showSettings(_ tab: SettingsTab) {
        guard let modules else { return }
        settingsNavigation.tab = tab
        if settingsWindow == nil {
            let view = SettingsView(store: store, loginItem: loginItem, apps: modules.apps, navigation: settingsNavigation)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.styleMask = [.titled, .closable]
            window.title = String(localized: "Configuración de \(AppIdentity.displayName)")
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        // Una app de tipo agente debe activarse para traer su ventana al frente.
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
