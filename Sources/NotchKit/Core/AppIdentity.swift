import Foundation

/// Identidad del producto leída del bundle. Los valores de respaldo solo se
/// usan fuera de un `.app` (pruebas, `swift run`).
public enum AppIdentity {
    public static var displayName: String {
        info("CFBundleDisplayName") ?? info("CFBundleName") ?? "NotchFlow"
    }

    public static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.axeldiaz.notchflow"
    }

    public static var version: String {
        info("CFBundleShortVersionString") ?? "0.0.0"
    }

    private static func info(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
