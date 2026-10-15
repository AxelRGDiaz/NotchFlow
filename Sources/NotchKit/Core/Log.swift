import os

/// Registros de diagnóstico por categoría. `Logger` trata las interpolaciones
/// dinámicas como privadas por defecto: no marcar como `.public` títulos de
/// canciones, eventos ni nombres de red.
public enum Log {
    public static let app = logger("app")
    public static let window = logger("window")
    public static let display = logger("display")
    public static let music = logger("music")
    public static let calendar = logger("calendar")
    public static let reminders = logger("reminders")
    public static let camera = logger("camera")
    public static let shelf = logger("shelf")
    public static let system = logger("system")
    public static let preferences = logger("preferences")

    private static func logger(_ category: String) -> Logger {
        Logger(subsystem: AppIdentity.bundleIdentifier, category: category)
    }
}
