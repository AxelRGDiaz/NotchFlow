import Foundation

public struct BatteryStatus: Equatable, Sendable {
    /// Nivel entre 0 y 1.
    public var level: Double
    public var isCharging: Bool
    public var isPluggedIn: Bool

    public init(level: Double, isCharging: Bool, isPluggedIn: Bool) {
        self.level = level
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
    }
}

public struct AudioVolume: Equatable, Sendable {
    /// Nivel entre 0 y 1.
    public var level: Double
    public var isMuted: Bool
    /// Falso en salidas sin control de volumen por software (p. ej. HDMI).
    public var isAdjustable: Bool

    public init(level: Double, isMuted: Bool, isAdjustable: Bool) {
        self.level = level
        self.isMuted = isMuted
        self.isAdjustable = isAdjustable
    }
}

/// Estado de una radio (Wi-Fi, Bluetooth). Solo lectura salvo que el servicio
/// indique expresamente que puede conmutarla.
public enum RadioState: Equatable, Sendable {
    case on
    case off
    case unavailable
    case unauthorized
}

/// Entrada de la vista de actividad. Solo contiene eventos generados por la
/// propia app; no hay acceso a las notificaciones de otras aplicaciones.
public struct ActivityItem: Equatable, Identifiable, Sendable {
    public enum Kind: String, Sendable {
        case eventSoon
        case trackChanged
        case batteryLow
        case chargingChanged
        case timerFinished
    }

    public var id: UUID
    public var kind: Kind
    public var title: String
    public var detail: String?
    public var date: Date

    public init(id: UUID = UUID(), kind: Kind, title: String, detail: String? = nil, date: Date = .now) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.date = date
    }
}
