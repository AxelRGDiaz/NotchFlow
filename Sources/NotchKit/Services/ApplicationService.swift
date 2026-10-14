import AppKit
import Observation
import UniformTypeIdentifiers

/// Aplicaciones favoritas: son accesos directos elegidos por el usuario, no
/// los iconos de estado de esas apps en la barra de menús.
@MainActor
@Observable
final class ApplicationService: ServiceLifecycle {
    private(set) var runningBundleIdentifiers: Set<String> = []

    @ObservationIgnored private let store: PreferencesStore
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var iconCache: [String: NSImage] = [:]

    init(store: PreferencesStore) {
        self.store = store
    }

    var favorites: [FavoriteApp] { store.preferences.favorites }

    func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshRunning() }
            })
        }
        refreshRunning()
    }

    func stop() {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers = []
        runningBundleIdentifiers = []
    }

    // MARK: - Consulta

    /// Ubicación actual de la app; `nil` si ya no está instalada.
    func url(for app: FavoriteApp) -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleIdentifier) { return url }
        if let url = app.lastKnownURL, FileManager.default.fileExists(atPath: url.path) { return url }
        return nil
    }

    func icon(for app: FavoriteApp) -> NSImage {
        if let cached = iconCache[app.bundleIdentifier] { return cached }
        guard let url = url(for: app) else {
            return NSWorkspace.shared.icon(for: .applicationBundle)
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[app.bundleIdentifier] = icon
        return icon
    }

    func isRunning(_ app: FavoriteApp) -> Bool {
        runningBundleIdentifiers.contains(app.bundleIdentifier)
    }

    func open(_ app: FavoriteApp) {
        guard let url = url(for: app) else {
            Log.app.notice("La app favorita ya no está instalada")
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - Edición

    /// Abre el selector de archivos del sistema para elegir aplicaciones.
    func presentAddPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = String(localized: "Añadir")
        guard panel.runModal() == .OK else { return }
        add(panel.urls)
    }

    func add(_ urls: [URL]) {
        let existing = Set(favorites.map(\.bundleIdentifier))
        let new = urls.compactMap(FavoriteApp.init(applicationURL:)).filter { !existing.contains($0.bundleIdentifier) }
        store.preferences.favorites = (favorites + new).uniqued(by: \.bundleIdentifier)
    }

    func remove(_ app: FavoriteApp) {
        store.preferences.favorites.removeAll { $0.bundleIdentifier == app.bundleIdentifier }
        iconCache[app.bundleIdentifier] = nil
    }

    func move(_ app: FavoriteApp, by offset: Int) {
        var list = favorites
        guard let index = list.firstIndex(of: app), list.indices.contains(index + offset) else { return }
        list.swapAt(index, index + offset)
        store.preferences.favorites = list
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var list = favorites
        list.move(fromOffsets: source, toOffset: destination)
        store.preferences.favorites = list
    }

    private func refreshRunning() {
        runningBundleIdentifiers = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }
}

extension FavoriteApp {
    /// Crea un favorito a partir de un paquete `.app`; `nil` si no lo es.
    init?(applicationURL url: URL) {
        guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
        self.init(
            bundleIdentifier: identifier,
            displayName: name.hasSuffix(".app") ? String(name.dropLast(4)) : name,
            lastKnownURL: url
        )
    }
}

extension Array {
    func uniqued<Key: Hashable>(by key: KeyPath<Element, Key>) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert($0[keyPath: key]).inserted }
    }
}
