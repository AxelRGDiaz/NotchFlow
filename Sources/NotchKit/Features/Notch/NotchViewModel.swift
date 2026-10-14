import Foundation
import Observation

/// Estado de presentación del notch. Envuelve la máquina de estados pura y
/// ejecuta sus efectos con tareas cancelables de un solo disparo.
@MainActor
@Observable
final class NotchViewModel {
    private(set) var state: NotchStateMachine.State = .idle
    private(set) var compactContent = CompactContent()
    var geometry: NotchGeometry
    let store: PreferencesStore

    /// Se invoca cuando cambia el marco que debe tener la ventana.
    @ObservationIgnored var onLayoutChange: (() -> Void)?
    @ObservationIgnored var onOpenSettings: ((SettingsTab) -> Void)?

    @ObservationIgnored private var machine = NotchStateMachine()
    @ObservationIgnored private var openTask: Task<Void, Never>?
    @ObservationIgnored private var closeTask: Task<Void, Never>?

    init(store: PreferencesStore, geometry: NotchGeometry) {
        self.store = store
        self.geometry = geometry
    }

    var layout: NotchLayout {
        let preferences = store.preferences
        return NotchLayout(
            geometry: geometry,
            contentSize: preferences.panelSize.contentSize,
            wingWidth: compactContent.wingWidth,
            maxWingWidth: preferences.maxWingWidth
        )
    }

    var shapeSize: CGSize { layout.shapeFrame(for: state).size }
    var expandedSize: CGSize { layout.shapeFrame(for: .expanded(pinned: false)).size }
    var windowFrame: CGRect { layout.windowFrame(for: state) }
    var pointerInside: Bool { machine.pointerInside }

    var isPinned: Bool {
        if case .expanded(pinned: true) = state { return true }
        return false
    }

    func send(_ event: NotchStateMachine.Event) {
        machine.config = store.preferences.stateMachineConfig
        let effects = machine.handle(event)
        effects.forEach(run)
        if machine.state != state {
            Log.window.info("\(String(describing: event), privacy: .public): \(String(describing: self.state), privacy: .public) → \(String(describing: self.machine.state), privacy: .public)")
            state = machine.state
            onLayoutChange?()
        }
    }

    func setCompactContent(_ content: CompactContent) {
        guard content != compactContent else { return }
        let oldFrame = windowFrame
        let oldState = state
        compactContent = content
        send(.activityChanged(hasActivity: !content.isEmpty))
        // Sin cambio de estado (compacto → compacto) el ancho puede variar igualmente.
        if state == oldState, windowFrame != oldFrame { onLayoutChange?() }
    }

    func openSettings(_ tab: SettingsTab = .general) {
        send(.dismissRequested)
        onOpenSettings?(tab)
    }

    func cancelPendingWork() {
        openTask?.cancel()
        closeTask?.cancel()
    }

    private func run(_ effect: NotchStateMachine.Effect) {
        switch effect {
        case .scheduleOpen(let delay):
            openTask?.cancel()
            openTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.send(.openDelayElapsed)
            }
        case .scheduleClose(let delay):
            closeTask?.cancel()
            closeTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.send(.closeDelayElapsed)
            }
        case .cancelOpen:
            openTask?.cancel()
        case .cancelClose:
            closeTask?.cancel()
        }
    }
}
