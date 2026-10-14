import Foundation
import IOKit.ps
import Observation
import notify

/// Estado de la batería mediante IOKit. Solo lectura y sin permisos.
@MainActor
@Observable
final class BatteryService: ServiceLifecycle {
    /// `nil` en equipos sin batería interna.
    private(set) var status: BatteryStatus?

    @ObservationIgnored private var tokens: [Int32] = []

    func start() {
        guard tokens.isEmpty else { return }
        // Avisos del sistema al cambiar el porcentaje o la fuente de alimentación.
        for name in ["com.apple.system.powersources.percent", "com.apple.system.powersources.source"] {
            var token: Int32 = 0
            let result = notify_register_dispatch(name, &token, .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
            if result == NOTIFY_STATUS_OK { tokens.append(token) }
        }
        refresh()
    }

    func stop() {
        tokens.forEach { notify_cancel($0) }
        tokens = []
        status = nil
    }

    func refresh() {
        status = Self.readStatus()
    }

    private static func readStatus() -> BatteryStatus? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  info[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = info[kIOPSCurrentCapacityKey] as? Double,
                  let maximum = info[kIOPSMaxCapacityKey] as? Double, maximum > 0 else { continue }
            return BatteryStatus(
                level: min(max(current / maximum, 0), 1),
                isCharging: info[kIOPSIsChargingKey] as? Bool ?? false,
                isPluggedIn: info[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            )
        }
        return nil
    }
}
