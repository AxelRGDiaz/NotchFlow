import Foundation
import Observation

/// Persistencia local de las preferencias en `UserDefaults`, como un único
/// valor JSON. Nada sale del equipo.
@MainActor
@Observable
public final class PreferencesStore {
    public static let defaultKey = "preferences.v1"

    public var preferences: Preferences {
        didSet {
            guard preferences != oldValue else { return }
            save()
        }
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String

    public init(defaults: UserDefaults = .standard, key: String = PreferencesStore.defaultKey) {
        self.defaults = defaults
        self.key = key
        self.preferences = Self.load(from: defaults, key: key)
    }

    public func reset() {
        preferences = Preferences()
    }

    private static func load(from defaults: UserDefaults, key: String) -> Preferences {
        guard let data = defaults.data(forKey: key) else { return Preferences() }
        do {
            return try JSONDecoder().decode(Preferences.self, from: data)
        } catch {
            Log.preferences.error("No se pudieron leer las preferencias; se usan los valores por defecto")
            return Preferences()
        }
    }

    private func save() {
        do {
            defaults.set(try JSONEncoder().encode(preferences), forKey: key)
        } catch {
            Log.preferences.error("No se pudieron guardar las preferencias")
        }
    }
}
