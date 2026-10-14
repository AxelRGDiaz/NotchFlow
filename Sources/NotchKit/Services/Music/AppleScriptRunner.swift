import Foundation

/// Ejecuta AppleScript fuera del hilo principal. `NSAppleScript` no admite uso
/// concurrente, así que todo pasa por una única cola en serie, que además
/// conserva los scripts ya compilados.
final class AppleScriptRunner: @unchecked Sendable {
    private let queue = DispatchQueue(label: "applescript-runner", qos: .userInitiated)
    // Solo se accede desde `queue`.
    private var compiled: [String: NSAppleScript] = [:]

    /// `transform` convierte el resultado a un valor `Sendable` dentro de la
    /// cola, porque `NSAppleEventDescriptor` no puede cruzar a otro hilo.
    func run<T: Sendable>(
        _ source: String,
        transform: @escaping @Sendable (NSAppleEventDescriptor) -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                let script: NSAppleScript
                if let cached = self.compiled[source] {
                    script = cached
                } else if let created = NSAppleScript(source: source) {
                    self.compiled[source] = created
                    script = created
                } else {
                    continuation.resume(throwing: MusicAdapterError.scriptFailed(code: 0))
                    return
                }

                var errorInfo: NSDictionary?
                let result = script.executeAndReturnError(&errorInfo)
                if let errorInfo {
                    let code = errorInfo[NSAppleScript.errorNumber] as? Int ?? 0
                    continuation.resume(throwing: Self.error(forCode: code))
                } else {
                    continuation.resume(returning: transform(result))
                }
            }
        }
    }

    static func error(forCode code: Int) -> MusicAdapterError {
        switch code {
        case -1743: .automationDenied
        case -600, -609: .playerNotRunning
        default: .scriptFailed(code: code)
        }
    }
}

enum Automation {
    /// Consulta (y opcionalmente solicita) el permiso para enviar Apple Events
    /// a una app. Con `askIfNeeded` la llamada espera a que el usuario responda,
    /// por eso se hace fuera del hilo principal.
    static func permission(forBundleIdentifier bundleIdentifier: String, askIfNeeded: Bool) async -> AutomationPermission {
        await Task.detached {
            let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
            let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, askIfNeeded)
            return permission(forStatus: status)
        }.value
    }

    static func permission(forStatus status: OSStatus) -> AutomationPermission {
        switch status {
        case noErr: .granted
        case -1744: .notDetermined  // errAEEventWouldRequireUserConsent
        case -600: .targetNotRunning  // procNotFound
        default: .denied  // -1743 errAEEventNotPermitted y cualquier otro fallo
        }
    }
}
