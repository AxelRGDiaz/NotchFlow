import Foundation

/// Permisos que la app puede llegar a solicitar. Cada uno se pide solo al
/// activar la función que lo necesita.
public enum PermissionKind: Hashable, Sendable {
    case calendar
    /// Apple Events hacia una app concreta (Música, Spotify).
    case automation(bundleIdentifier: String)
    case notifications
    case bluetooth
    case location
    case accessibility
}

/// Estado real de una integración. La interfaz lo muestra tal cual para que
/// un módulo sin permiso o no soportado no bloquee ni disfrace al resto.
public enum ServiceStatus: Equatable, Sendable {
    /// Aún no se ha iniciado o no se ha consultado.
    case idle
    case available
    /// El permiso no se ha pedido todavía; se puede solicitar.
    case needsPermission(PermissionKind)
    /// El usuario lo denegó; solo puede cambiarse en Ajustes del Sistema.
    case denied(PermissionKind)
    case unsupported(reason: String)
    case failed(message: String)

    public var isAvailable: Bool { self == .available }
}

/// Ciclo de vida común: `start` registra observadores, `stop` los libera y
/// cancela tareas. Ambos deben ser idempotentes.
@MainActor
public protocol ServiceLifecycle: AnyObject {
    func start()
    func stop()
}
