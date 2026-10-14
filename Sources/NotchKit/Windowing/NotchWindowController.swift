import AppKit
import SwiftUI

/// Único dueño de la ventana del notch: la crea una vez, la coloca en la
/// pantalla adecuada y ajusta su marco a la forma visible en cada estado.
@MainActor
final class NotchWindowController: NSObject {
    private let model: NotchViewModel
    private let modules: ModuleCoordinator
    private let panel = NotchPanel()
    private var settleTask: Task<Void, Never>?
    private var outsideClickMonitor: Any?
    private var isStarted = false

    init(model: NotchViewModel, modules: ModuleCoordinator) {
        self.model = model
        self.modules = modules
        super.init()

        let hosting = FirstMouseHostingView(rootView: NotchRootView(model: model, modules: modules))
        // La ventana manda sobre el tamaño; el contenido no debe redimensionarla
        // ni reservar el área segura del notch.
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        hosting.autoresizingMask = [.width, .height]

        let container = PointerTrackingView()
        container.addSubview(hosting)
        hosting.frame = container.bounds
        container.onPointerChange = { [weak self] in self?.syncPointer() }
        panel.contentView = container

        panel.onCancel = { [weak self] in self?.model.send(.dismissRequested) }
        model.onLayoutChange = { [weak self] in self?.applyLayout(animated: true) }
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil
        )
        observePreferences()
        refreshScreen()
        modules.start()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        settleTask?.cancel()
        model.cancelPendingWork()
        modules.stop()
        removeOutsideClickMonitor()
        panel.orderOut(nil)
    }

    /// Abre o cierra el panel desde la barra de menús. Aquí sí se toma el
    /// teclado, porque el usuario lo ha pedido de forma explícita.
    func togglePanel() {
        model.send(.toggleRequested)
        if model.state.isExpanded { panel.makeKey() }
    }

    // MARK: - Pantalla

    @objc private func screensChanged() {
        refreshScreen()
    }

    @objc private func didWake() {
        refreshScreen()
        modules.refreshAfterWake()
    }

    private func refreshScreen() {
        let screens = NSScreen.screens.map(ScreenDescriptor.init)
        guard let screen = NotchGeometry.preferredScreen(from: screens) else {
            Log.display.notice("Sin pantallas disponibles; se oculta el panel")
            panel.orderOut(nil)
            return
        }
        let geometry = NotchGeometry(screen: screen)
        if geometry != model.geometry {
            Log.display.info("Pantalla \(screen.displayID), notch físico: \(geometry.hasPhysicalNotch)")
            model.geometry = geometry
        }
        applyLayout(animated: false)
        panel.orderFrontRegardless()
    }

    private func observePreferences() {
        withObservationTracking {
            _ = model.store.preferences
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.isStarted else { return }
                self.applyLayout(animated: false)
                self.observePreferences()
            }
        }
    }

    // MARK: - Marco de la ventana

    /// Durante una transición la ventana ocupa la unión de los marcos inicial
    /// y final, para que la animación de SwiftUI no se recorte; al terminar se
    /// ciñe al marco final.
    private func applyLayout(animated: Bool) {
        settleTask?.cancel()
        let target = model.windowFrame
        let expanded = model.state.isExpanded
        let duration = model.store.preferences.animationDuration

        if expanded {
            installOutsideClickMonitor()
        } else {
            removeOutsideClickMonitor()
            releaseKeyboardIfNeeded()
        }

        let transition = animated && duration > 0 ? panel.frame.union(target) : target
        panel.setFrame(transition, display: true)
        if transition != target {
            settleTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(duration + 0.1))
                guard !Task.isCancelled, let self else { return }
                self.panel.setFrame(target, display: true)
                self.syncPointer()
            }
        }
        syncPointer()
    }

    /// Una ventana clave en una app inactiva solo suelta el teclado al salir de
    /// pantalla, así que se retira y se vuelve a mostrar sin hacerla clave.
    private func releaseKeyboardIfNeeded() {
        guard panel.isKeyWindow else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    // MARK: - Cursor

    /// Los eventos de entrada y salida no llegan cuando es la ventana la que
    /// cambia de tamaño bajo un cursor quieto, así que la posición real del
    /// cursor es la única fuente de verdad.
    private func syncPointer() {
        var hitFrame = panel.frame
        // El cursor pegado al borde superior informa una y igual al máximo.
        hitFrame.size.height += 2
        let inside = hitFrame.contains(NSEvent.mouseLocation)
        guard inside != model.pointerInside else { return }
        model.send(inside ? .pointerEntered : .pointerExited)
    }

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        // Solo clics, solo mientras el panel está abierto. No requiere permisos.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.model.state == .expanded(pinned: false) else { return }
            self.model.send(.dismissRequested)
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
    }
}
