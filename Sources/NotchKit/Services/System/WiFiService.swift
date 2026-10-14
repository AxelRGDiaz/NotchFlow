import CoreWLAN
import Observation

/// Estado de encendido del Wi-Fi mediante CoreWLAN. Solo lectura: el nombre de
/// la red exigiría permiso de Ubicación y no se solicita.
@MainActor
@Observable
final class WiFiService: NSObject, ServiceLifecycle, CWEventDelegate {
    private(set) var state: RadioState = .unavailable

    @ObservationIgnored private let client = CWWiFiClient.shared()
    @ObservationIgnored private var isMonitoring = false

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        client.delegate = self
        do {
            try client.startMonitoringEvent(with: .powerDidChange)
        } catch {
            Log.system.error("No se pudo observar el Wi-Fi: \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }

    func stop() {
        guard isMonitoring else { return }
        isMonitoring = false
        try? client.stopMonitoringAllEvents()
        client.delegate = nil
        state = .unavailable
    }

    func refresh() {
        guard let interface = client.interface() else {
            state = .unavailable
            return
        }
        state = interface.powerOn() ? .on : .off
    }

    // CoreWLAN llama al delegado desde un hilo en segundo plano.
    nonisolated func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor in self.refresh() }
    }
}
