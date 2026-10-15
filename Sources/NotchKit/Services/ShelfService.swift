import AppKit
import Observation

/// Bandeja de archivos: guarda referencias (no copias) a los archivos que el
/// usuario suelta en el notch, para sacarlos después arrastrando o enviarlos
/// por AirDrop. Persiste entre sesiones; los archivos que ya no existen se
/// descartan al cargar.
@MainActor
@Observable
final class ShelfService {
    nonisolated static let defaultKey = "shelf.v1"
    nonisolated static let maxItems = 30

    private(set) var items: [URL] = []
    /// Zona sobre la que se están arrastrando archivos, para resaltarla.
    var targetedZone: ShelfDropZone?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let key: String

    init(defaults: UserDefaults = .standard, key: String = ShelfService.defaultKey) {
        self.defaults = defaults
        self.key = key
        let paths = defaults.stringArray(forKey: key) ?? []
        items = paths.compactMap { Self.resolved(URL(fileURLWithPath: $0)) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// El Finder entrega URL de referencia (`file:///.file/id=…`), cuyo último
    /// componente no es el nombre del archivo: se convierten a la ruta real
    /// para mostrar el nombre y para que al sacarlo o enviarlo lo conserve.
    nonisolated static func resolved(_ url: URL) -> URL? {
        guard url.isFileURL else { return nil }
        return ((url as NSURL).filePathURL ?? url).standardizedFileURL
    }

    /// Añade al principio, sin duplicados y hasta `maxItems`.
    func add(_ urls: [URL]) {
        let files = urls.compactMap(Self.resolved)
        guard !files.isEmpty else { return }
        var seen = Set<URL>()
        items = (files + items).filter { seen.insert($0).inserted }.prefix(Self.maxItems).map { $0 }
        save()
    }

    /// Quita los archivos que ya no están donde se guardaron, por ejemplo
    /// porque el Finder los movió al sacarlos de la bandeja.
    func pruneMissing() {
        let existing = items.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard existing != items else { return }
        items = existing
        save()
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        save()
    }

    func clear() {
        items = []
        save()
    }

    func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Abre el selector de AirDrop del sistema con estos archivos.
    func sendViaAirDrop(_ urls: [URL]) {
        let urls = urls.compactMap(Self.resolved)
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        guard service.canPerform(withItems: urls) else {
            Log.shelf.error("AirDrop no está disponible")
            return
        }
        // Una app de tipo agente debe activarse para que la ventana de AirDrop aparezca al frente.
        NSApp.activate()
        service.perform(withItems: urls)
    }

    private func save() {
        defaults.set(items.map(\.path), forKey: key)
    }
}

enum ShelfDropZone: Equatable, Sendable {
    case shelf
    case airDrop
}
