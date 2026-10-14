import AppKit

/// Apple Music mediante Apple Events. Requiere el permiso de Automatización
/// hacia Música; nunca abre la app ni le envía eventos si está cerrada.
@MainActor
final class AppleMusicAdapter: MusicPlayerAdapter {
    let player = PlayerID.appleMusic
    private let runner: AppleScriptRunner

    init(runner: AppleScriptRunner) {
        self.runner = runner
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleIdentifier).isEmpty
    }

    func changes() -> AsyncStream<Void> {
        let bundleIdentifier = player.bundleIdentifier
        return AsyncStream { continuation in
            let observers = ObserverBag()
            // Música publica esta notificación al cambiar de pista o de estado.
            // No está documentada, por eso el servicio también refresca al
            // abrir el panel.
            let distributed = DistributedNotificationCenter.default()
            observers.add(distributed.addObserver(
                forName: Notification.Name("com.apple.Music.playerInfo"), object: nil, queue: nil
            ) { _ in
                continuation.yield()
            }, in: distributed)

            let workspace = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
                observers.add(workspace.addObserver(forName: name, object: nil, queue: nil) { notification in
                    let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                    if app?.bundleIdentifier == bundleIdentifier { continuation.yield() }
                }, in: workspace)
            }
            continuation.onTermination = { _ in observers.removeAll() }
        }
    }

    func permission(askIfNeeded: Bool) async -> AutomationPermission {
        guard isRunning else { return .targetNotRunning }
        return await Automation.permission(forBundleIdentifier: player.bundleIdentifier, askIfNeeded: askIfNeeded)
    }

    func fetchNowPlaying() async throws -> NowPlaying? {
        guard isRunning else { throw MusicAdapterError.playerNotRunning }
        let player = player
        return try await runner.run(Script.nowPlaying) { descriptor in
            MusicScriptParser.nowPlaying(from: descriptor, player: player, now: .now)
        }
    }

    func artwork(for track: NowPlaying) async -> Data? {
        guard isRunning else { return nil }
        let data = try? await runner.run(Script.artwork) { descriptor in
            descriptor.descriptorType == typeNull ? nil : descriptor.data
        }
        guard let data, !data.isEmpty else { return nil }
        return data
    }

    func perform(_ command: MusicCommand) async throws {
        guard isRunning else { throw MusicAdapterError.playerNotRunning }
        let verb = switch command {
        case .playPause: "playpause"
        case .next: "next track"
        case .previous: "previous track"
        }
        try await runner.run(Script.command(verb)) { _ in }
    }

    /// La guarda `is running` evita que AppleScript abra Música por su cuenta.
    private enum Script {
        static let nowPlaying = """
        if application id "com.apple.Music" is not running then return {}
        tell application id "com.apple.Music"
            if player state is stopped then return {}
            try
                set t to current track
                set d to 0
                try
                    set d to duration of t
                end try
                return {(player state is playing), name of t, artist of t, album of t, d, player position, persistent ID of t}
            on error
                return {}
            end try
        end tell
        """

        static let artwork = """
        if application id "com.apple.Music" is not running then return missing value
        tell application id "com.apple.Music"
            try
                return raw data of artwork 1 of current track
            on error
                return missing value
            end try
        end tell
        """

        static func command(_ verb: String) -> String {
            "if application id \"com.apple.Music\" is running then tell application id \"com.apple.Music\" to \(verb)"
        }
    }
}

enum MusicScriptParser {
    /// Interpreta la lista `{reproduciendo, título, artista, álbum, duración,
    /// posición, id}`. Una lista vacía significa que no hay pista.
    static func nowPlaying(from descriptor: NSAppleEventDescriptor, player: PlayerID, now: Date) -> NowPlaying? {
        guard descriptor.numberOfItems >= 7 else { return nil }
        func text(_ index: Int) -> String? {
            guard let value = descriptor.atIndex(index)?.stringValue, !value.isEmpty else { return nil }
            return value
        }
        guard let title = text(2) else { return nil }
        let duration = descriptor.atIndex(5)?.doubleValue ?? 0
        return NowPlaying(
            player: player,
            trackID: text(7),
            title: title,
            artist: text(3),
            album: text(4),
            // Las emisiones en directo no tienen duración.
            duration: duration > 0 ? duration : nil,
            isPlaying: descriptor.atIndex(1)?.booleanValue ?? false,
            position: max(descriptor.atIndex(6)?.doubleValue ?? 0, 0),
            positionDate: now
        )
    }
}

/// Observadores de notificaciones que se retiran juntos al terminar un flujo.
final class ObserverBag: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(NotificationCenter, NSObjectProtocol)] = []

    func add(_ token: NSObjectProtocol, in center: NotificationCenter) {
        lock.withLock { entries.append((center, token)) }
    }

    func removeAll() {
        let current = lock.withLock {
            defer { entries = [] }
            return entries
        }
        for (center, token) in current { center.removeObserver(token) }
    }
}
