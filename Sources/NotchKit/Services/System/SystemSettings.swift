import AppKit

/// Paneles de Ajustes del Sistema a los que se enlaza cuando no hay API
/// pública para controlar algo directamente. Los identificadores no están
/// garantizados entre versiones de macOS; si uno falla se abre Ajustes sin más.
enum SystemSettings: String {
    case wifi = "com.apple.wifi-settings-extension"
    case bluetooth = "com.apple.BluetoothSettings"
    case displays = "com.apple.Displays-Settings.extension"
    case sound = "com.apple.Sound-Settings.extension"
    case battery = "com.apple.Battery-Settings.extension"
    case calendarPrivacy = "com.apple.preference.security?Privacy_Calendars"
    case remindersPrivacy = "com.apple.preference.security?Privacy_Reminders"
    case cameraPrivacy = "com.apple.preference.security?Privacy_Camera"
    case automationPrivacy = "com.apple.preference.security?Privacy_Automation"

    var url: URL? { URL(string: "x-apple.systempreferences:\(rawValue)") }

    @MainActor
    func open() {
        if let url, NSWorkspace.shared.open(url) { return }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
