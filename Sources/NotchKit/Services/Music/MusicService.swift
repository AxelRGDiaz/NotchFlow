import AppKit
import Observation

/// Estado de reproducción del reproductor compatible que esté abierto.
@MainActor
@Observable
final class MusicService: ServiceLifecycle {
    /// `.idle` significa que no hay ningún reproductor compatible abierto.
    private(set) var status: ServiceStatus = .idle
    private(set) var nowPlaying: NowPlaying?
    private(set) var artwork: NSImage?
    private(set) var activePlayer: PlayerID?

    @ObservationIgnored private let adapters: [any MusicPlayerAdapter]
    @ObservationIgnored private var listeners: [Task<Void, Never>] = []
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var artworkTrackKey: String?

    init(adapters: [any MusicPlayerAdapter]) {
        self.adapters = adapters
    }

    /// Reproductor que se abre desde el panel cuando no suena nada.
    let defaultPlayer = PlayerID.appleMusic

    func start() {
        guard listeners.isEmpty else { return }
        for adapter in adapters {
            let stream = adapter.changes()
            listeners.append(Task { [weak self] in
                for await _ in stream { self?.refresh() }
            })
        }
        refresh()
    }

    func stop() {
        listeners.forEach { $0.cancel() }
        listeners = []
        refreshTask?.cancel()
        status = .idle
        nowPlaying = nil
        artwork = nil
        activePlayer = nil
        artworkTrackKey = nil
    }

    /// Vuelve a consultar al reproductor. Los avisos llegan en ráfagas, así
    /// que las peticiones seguidas se agrupan en una sola.
    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            await self?.load()
        }
    }

    func requestPermission() {
        guard let adapter = runningAdapter else { return }
        Task { [weak self] in
            _ = await adapter.permission(askIfNeeded: true)
            self?.refresh()
        }
    }

    func perform(_ command: MusicCommand) {
        guard let adapter = runningAdapter else { return }
        Task { [weak self] in
            do {
                try await adapter.perform(command)
            } catch {
                Log.music.error("Fallo al enviar una orden al reproductor: \(String(describing: error), privacy: .public)")
            }
            self?.refresh()
        }
    }

    /// Abre la app que está reproduciendo; si no hay ninguna, Música.
    func openPlayer() {
        let candidates = [nowPlaying?.player, activePlayer, defaultPlayer].compactMap { $0 }
        guard let url = candidates.lazy.compactMap({
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleIdentifier)
        }).first else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private var runningAdapter: (any MusicPlayerAdapter)? {
        adapters.first { $0.isRunning }
    }

    private func load() async {
        guard let adapter = runningAdapter else {
            clear(status: .idle, player: nil)
            return
        }
        let permissionKind = PermissionKind.automation(bundleIdentifier: adapter.player.bundleIdentifier)
        switch await adapter.permission(askIfNeeded: false) {
        case .granted:
            break
        case .notDetermined:
            clear(status: .needsPermission(permissionKind), player: adapter.player)
            return
        case .denied:
            clear(status: .denied(permissionKind), player: adapter.player)
            return
        case .targetNotRunning:
            clear(status: .idle, player: nil)
            return
        }

        do {
            let track = try await adapter.fetchNowPlaying()
            guard !Task.isCancelled else { return }
            // Asignar solo si cambia: cada asignación invalida las vistas que lo leen.
            if activePlayer != adapter.player { activePlayer = adapter.player }
            if status != .available { status = .available }
            if nowPlaying != track { nowPlaying = track }
            await loadArtwork(for: track, from: adapter)
        } catch MusicAdapterError.automationDenied {
            clear(status: .denied(permissionKind), player: adapter.player)
        } catch MusicAdapterError.playerNotRunning {
            clear(status: .idle, player: nil)
        } catch {
            Log.music.error("Fallo al leer la reproducción: \(String(describing: error), privacy: .public)")
            clear(status: .failed(message: String(localized: "No se pudo leer la reproducción.")), player: adapter.player)
        }
    }

    private func loadArtwork(for track: NowPlaying?, from adapter: any MusicPlayerAdapter) async {
        guard let track else {
            artwork = nil
            artworkTrackKey = nil
            return
        }
        let key = track.trackID ?? "\(track.title)|\(track.artist ?? "")"
        // La carátula puede llegar después que el título; se reintenta mientras falte.
        guard key != artworkTrackKey || artwork == nil else { return }
        artworkTrackKey = key
        let data = await adapter.artwork(for: track)
        // Otra pista pudo empezar mientras se cargaba esta carátula.
        guard artworkTrackKey == key else { return }
        artwork = data.flatMap(NSImage.init(data:))
    }

    private func clear(status: ServiceStatus, player: PlayerID?) {
        if self.status != status { self.status = status }
        if activePlayer != player { activePlayer = player }
        if nowPlaying != nil { nowPlaying = nil }
        if artwork != nil { artwork = nil }
        artworkTrackKey = nil
    }
}
