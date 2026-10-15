import Foundation

/// Secciones del panel expandido. La configuración no es un módulo: siempre
/// está accesible desde el panel y desde la barra de menús.
public enum ModuleID: String, Codable, CaseIterable, Sendable {
    case music
    case calendar
    case apps
    case quickControls
    case activity
    case reminders
    case shelf
    case camera
    case timer
}

public enum AppearanceMode: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark
}

public enum PanelSize: String, Codable, CaseIterable, Sendable {
    case small
    case medium
    case large

    /// Tamaño del contenido bajo la franja del notch, pestañas incluidas.
    public var contentSize: CGSize {
        switch self {
        case .small: CGSize(width: 480, height: 230)
        case .medium: CGSize(width: 600, height: 268)
        case .large: CGSize(width: 700, height: 330)
        }
    }
}

/// Indicadores que pueden aparecer en las alas del estado compacto.
public enum CompactIndicator: String, Codable, CaseIterable, Sendable {
    case music
    case nextEvent
    case battery
}

public struct FavoriteApp: Codable, Hashable, Identifiable, Sendable {
    public var bundleIdentifier: String
    public var displayName: String
    /// Última ubicación conocida; se usa si el identificador ya no resuelve.
    public var lastKnownURL: URL?

    public var id: String { bundleIdentifier }

    public init(bundleIdentifier: String, displayName: String, lastKnownURL: URL? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.lastKnownURL = lastKnownURL
    }
}

/// Preferencias del usuario. El inicio al iniciar sesión no se guarda aquí:
/// su fuente de verdad es `SMAppService`, que el usuario puede cambiar desde Ajustes.
public struct Preferences: Codable, Equatable, Sendable {
    public var moduleOrder: [ModuleID] = ModuleID.allCases
    public var hiddenModules: Set<ModuleID> = []
    public var panelSize: PanelSize = .medium
    public var appearance: AppearanceMode = .system

    public var opensOnHover = true
    public var hoverOpenDelay: TimeInterval = 0.25
    public var opensOnClick = true
    public var closesOnPointerExit = true
    public var closeDelay: TimeInterval = 0.6
    public var animationDuration: TimeInterval = 0.35

    public var compactIndicators: Set<CompactIndicator> = [.music, .nextEvent]
    /// Ancho máximo de cada ala del estado compacto, en puntos.
    public var maxWingWidth: Double = 120

    public var favorites: [FavoriteApp] = []

    public init() {}

    public var visibleModules: [ModuleID] {
        moduleOrder.filter { !hiddenModules.contains($0) }
    }

    public var stateMachineConfig: NotchStateMachine.Config {
        NotchStateMachine.Config(
            opensOnHover: opensOnHover,
            hoverOpenDelay: hoverOpenDelay,
            opensOnClick: opensOnClick,
            closesOnPointerExit: closesOnPointerExit,
            closeDelay: closeDelay
        )
    }

    /// Corrige datos incoherentes (versiones antiguas, edición manual): cada
    /// módulo aparece una sola vez, los nuevos se añaden al final y los
    /// valores numéricos quedan dentro de rangos seguros.
    public func normalized() -> Preferences {
        var copy = self
        var seen = Set<ModuleID>()
        copy.moduleOrder = moduleOrder.filter { seen.insert($0).inserted }
        copy.moduleOrder += ModuleID.allCases.filter { !seen.contains($0) }

        var seenApps = Set<String>()
        copy.favorites = favorites.filter { !$0.bundleIdentifier.isEmpty && seenApps.insert($0.bundleIdentifier).inserted }

        copy.hoverOpenDelay = hoverOpenDelay.clamped(to: 0...2)
        copy.closeDelay = closeDelay.clamped(to: 0...5)
        copy.animationDuration = animationDuration.clamped(to: 0...1)
        copy.maxWingWidth = maxWingWidth.clamped(to: 0...240)
        // Sin ninguna forma de abrir el panel la app quedaría inutilizable.
        if !copy.opensOnHover && !copy.opensOnClick { copy.opensOnClick = true }
        return copy
    }
}

extension Preferences {
    /// Decodificación tolerante: una clave ausente o con un valor desconocido
    /// conserva su valor por defecto en lugar de invalidar todas las preferencias.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        func read<T: Decodable>(_ key: CodingKeys, into value: inout T) {
            if let decoded = try? c.decodeIfPresent(T.self, forKey: key) { value = decoded }
        }
        read(.moduleOrder, into: &moduleOrder)
        read(.hiddenModules, into: &hiddenModules)
        read(.panelSize, into: &panelSize)
        read(.appearance, into: &appearance)
        read(.opensOnHover, into: &opensOnHover)
        read(.hoverOpenDelay, into: &hoverOpenDelay)
        read(.opensOnClick, into: &opensOnClick)
        read(.closesOnPointerExit, into: &closesOnPointerExit)
        read(.closeDelay, into: &closeDelay)
        read(.animationDuration, into: &animationDuration)
        read(.compactIndicators, into: &compactIndicators)
        read(.maxWingWidth, into: &maxWingWidth)
        read(.favorites, into: &favorites)
        self = normalized()
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
