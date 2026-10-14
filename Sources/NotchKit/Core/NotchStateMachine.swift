import Foundation

/// Lógica de expansión y contracción, sin temporizadores ni AppKit: recibe
/// eventos y devuelve los efectos que el controlador de ventana debe ejecutar.
public struct NotchStateMachine: Equatable, Sendable {
    public struct Config: Equatable, Sendable {
        public var opensOnHover: Bool
        public var hoverOpenDelay: TimeInterval
        public var opensOnClick: Bool
        public var closesOnPointerExit: Bool
        public var closeDelay: TimeInterval

        public init(
            opensOnHover: Bool = true,
            hoverOpenDelay: TimeInterval = 0.25,
            opensOnClick: Bool = true,
            closesOnPointerExit: Bool = true,
            closeDelay: TimeInterval = 0.6
        ) {
            self.opensOnHover = opensOnHover
            self.hoverOpenDelay = hoverOpenDelay
            self.opensOnClick = opensOnClick
            self.closesOnPointerExit = closesOnPointerExit
            self.closeDelay = closeDelay
        }
    }

    public enum State: Equatable, Sendable {
        /// Del tamaño exacto del notch: invisible sobre un notch físico.
        case idle
        /// Con alas visibles porque hay actividad (música, evento próximo).
        case compact
        case expanded(pinned: Bool)

        public var isExpanded: Bool {
            if case .expanded = self { return true }
            return false
        }
    }

    public enum Event: Equatable, Sendable {
        case pointerEntered
        case pointerExited
        case clicked
        case openDelayElapsed
        case closeDelayElapsed
        /// Escape, clic fuera del panel o pérdida de la pantalla.
        case dismissRequested
        /// Atajo de teclado o elemento de la barra de menús: alterna el panel.
        case toggleRequested
        case pinToggled
        case activityChanged(hasActivity: Bool)
    }

    public enum Effect: Equatable, Sendable {
        case scheduleOpen(after: TimeInterval)
        case scheduleClose(after: TimeInterval)
        case cancelOpen
        case cancelClose
    }

    public private(set) var state: State = .idle
    public private(set) var hasActivity = false
    public private(set) var pointerInside = false
    public var config: Config

    public init(config: Config = Config()) {
        self.config = config
    }

    private var restingState: State { hasActivity ? .compact : .idle }

    public mutating func handle(_ event: Event) -> [Effect] {
        switch event {
        case .pointerEntered:
            pointerInside = true
            if state.isExpanded { return [.cancelClose] }
            guard config.opensOnHover else { return [] }
            if config.hoverOpenDelay <= 0 {
                state = .expanded(pinned: false)
                return []
            }
            return [.scheduleOpen(after: config.hoverOpenDelay)]

        case .pointerExited:
            pointerInside = false
            switch state {
            case .expanded(pinned: false) where config.closesOnPointerExit:
                return [.scheduleClose(after: max(config.closeDelay, 0))]
            case .expanded:
                return []
            case .idle, .compact:
                return [.cancelOpen]
            }

        case .clicked:
            guard !state.isExpanded, config.opensOnClick else { return [] }
            state = .expanded(pinned: false)
            return [.cancelOpen]

        case .openDelayElapsed:
            // Un temporizador atrasado no debe abrir si el cursor ya salió.
            guard pointerInside, !state.isExpanded else { return [] }
            state = .expanded(pinned: false)
            return []

        case .closeDelayElapsed:
            guard !pointerInside, state == .expanded(pinned: false) else { return [] }
            state = restingState
            return []

        case .dismissRequested:
            guard state.isExpanded else { return [.cancelOpen] }
            state = restingState
            return [.cancelOpen, .cancelClose]

        case .toggleRequested:
            state = state.isExpanded ? restingState : .expanded(pinned: false)
            return [.cancelOpen, .cancelClose]

        case .pinToggled:
            guard case .expanded(let pinned) = state else { return [] }
            state = .expanded(pinned: !pinned)
            if pinned, !pointerInside, config.closesOnPointerExit {
                return [.scheduleClose(after: max(config.closeDelay, 0))]
            }
            return [.cancelClose]

        case .activityChanged(let active):
            hasActivity = active
            if !state.isExpanded { state = restingState }
            return []
        }
    }
}
