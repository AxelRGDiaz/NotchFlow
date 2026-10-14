import Observation
import ServiceManagement

/// Inicio al iniciar sesión mediante `SMAppService`. El sistema es la fuente
/// de verdad: el usuario puede cambiarlo en Ajustes > General > Ítems de inicio.
@MainActor
@Observable
final class LoginItemService {
    enum State: Equatable {
        case enabled
        case disabled
        /// Registrado, pero el usuario debe aprobarlo en Ajustes del Sistema.
        case requiresApproval
        /// La app no se ejecuta desde un `.app` que el sistema pueda registrar.
        case unavailable
    }

    private(set) var state: State = .disabled
    private(set) var lastErrorMessage: String?

    init() {
        refresh()
    }

    var isEnabled: Bool { state == .enabled || state == .requiresApproval }

    func refresh() {
        switch SMAppService.mainApp.status {
        case .enabled: state = .enabled
        case .requiresApproval: state = .requiresApproval
        case .notRegistered: state = .disabled
        case .notFound: state = .unavailable
        @unknown default: state = .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) {
        lastErrorMessage = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            lastErrorMessage = error.localizedDescription
            Log.app.error("Fallo al cambiar el inicio de sesión: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }
}
