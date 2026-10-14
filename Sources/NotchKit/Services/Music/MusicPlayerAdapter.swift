import Foundation

/// Resultado de consultar el permiso de automatización hacia una app.
public enum AutomationPermission: Equatable, Sendable {
    case granted
    case denied
    /// Aún no se ha preguntado al usuario.
    case notDetermined
    case targetNotRunning
}

/// Integración con un reproductor concreto. No existe una API pública para
/// "lo que suena en el sistema", así que cada reproductor compatible tiene su
/// adaptador y `MusicService` usa el que esté abierto.
@MainActor
public protocol MusicPlayerAdapter: AnyObject {
    var player: PlayerID { get }

    /// Debe responder sin lanzar la app ni provocar un aviso de permisos.
    var isRunning: Bool { get }

    /// Emite cuando el reproductor avisa de un cambio (pista, pausa, apertura
    /// o cierre). No lleva datos: el servicio vuelve a consultar.
    func changes() -> AsyncStream<Void>

    /// Con `askIfNeeded` el sistema muestra su aviso de consentimiento.
    func permission(askIfNeeded: Bool) async -> AutomationPermission

    /// `nil` si el reproductor está abierto pero sin pista cargada.
    func fetchNowPlaying() async throws -> NowPlaying?

    func artwork(for track: NowPlaying) async -> Data?

    func perform(_ command: MusicCommand) async throws
}

public enum MusicAdapterError: Error, Equatable, Sendable {
    /// El usuario denegó la automatización de este reproductor.
    case automationDenied
    case playerNotRunning
    case scriptFailed(code: Int)
}
