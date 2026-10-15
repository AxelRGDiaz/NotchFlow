import AppKit

/// Reproducción de cualquier app (navegadores, Spotify, Música, podcasts…)
/// mediante mediaremote-adapter, que usa el framework privado MediaRemote a
/// través de `/usr/bin/perl`. Es la única API privada del proyecto, aprobada
/// expresamente para este módulo. Si deja de funcionar tras una actualización
/// de macOS, `isRunning` pasa a falso y `MusicService` usa el siguiente adaptador.
@MainActor
final class SystemNowPlayingAdapter: MusicPlayerAdapter {
    /// Identifica a la fuente, no a una app: la app real va en `NowPlaying.player`.
    let player = PlayerID(bundleIdentifier: "com.apple.mediaremote", displayName: String(localized: "Reproducción del sistema"))

    private static let perl = URL(fileURLWithPath: "/usr/bin/perl")
    /// Si el proceso falla más de estas veces en un minuto, se da por roto.
    private static let maxFailuresPerMinute = 3
    private static let startupTimeout: Duration = .seconds(5)
    /// Tras darlo por roto se vuelve a intentar con esta pausa, por si el fallo era pasajero.
    private static let brokenRetryDelay: Duration = .seconds(300)

    /// Lanza el adaptador como hijo y lo termina si NotchFlow desaparece, aunque
    /// sea por un cierre forzado: sin esto quedaría un proceso huérfano.
    /// Recibe como argumentos los del adaptador.
    static let supervisor = #"""
    use POSIX ":sys_wait_h";
    my $pid = fork() // exit 1;
    if ($pid == 0) { exec "/usr/bin/perl", @ARGV; exit 127; }
    sub stop { kill "TERM", $pid; waitpid($pid, 0); exit 0; }
    $SIG{TERM} = $SIG{INT} = $SIG{HUP} = \&stop;
    while (1) {
        if (waitpid($pid, WNOHANG) == $pid) { exit($? >> 8); }
        stop() if getppid() == 1;
        sleep 1;
    }
    """#

    private let scriptURL: URL
    private let frameworkURL: URL

    private var process: Process?
    private var state: [String: MediaRemoteValue] = [:]
    private var isFunctional = false
    private var failures: [Date] = []
    private var subscribers: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var watchdog: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var appNames: [String: String] = [:]

    /// `nil` fuera de un `.app` con el adaptador empaquetado (pruebas, `swift run`).
    init?(bundle: Bundle = .main) {
        guard let script = bundle.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let framework = bundle.privateFrameworksURL?.appendingPathComponent("MediaRemoteAdapter.framework"),
              FileManager.default.fileExists(atPath: framework.path) else { return nil }
        scriptURL = script
        frameworkURL = framework
    }

    var isRunning: Bool { isFunctional }

    func changes() -> AsyncStream<Void> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.unsubscribe(id) }
        }
        if process == nil { launch() }
        return stream
    }

    func permission(askIfNeeded: Bool) async -> AutomationPermission {
        isFunctional ? .granted : .targetNotRunning
    }

    func fetchNowPlaying() async throws -> NowPlaying? {
        guard isFunctional else { throw MusicAdapterError.playerNotRunning }
        guard let payload = MediaRemotePayload(state) else { return nil }
        let player = if let app = payload.appBundleIdentifier {
            PlayerID(bundleIdentifier: app, displayName: appName(for: app))
        } else {
            processPlayer(pid: payload.processIdentifier)
        }
        return payload.nowPlaying(player: player)
    }

    func artwork(for track: NowPlaying) async -> Data? {
        if case .data(let data) = state["artworkData"] { return data }
        return nil
    }

    func perform(_ command: MusicCommand) async throws {
        // Identificadores de orden de MediaRemote (kMRTogglePlayPause, etc.).
        let arguments = switch command {
        case .playPause: ["send", "2"]
        case .next: ["send", "4"]
        case .previous: ["send", "5"]
        case .seek(let position): ["seek", "\(Int(max(position, 0) * 1_000_000))"]
        }
        let status = try await Self.runOnce(arguments: [scriptURL.path, frameworkURL.path] + arguments)
        if status != 0 { throw MusicAdapterError.scriptFailed(code: Int(status)) }
    }

    // MARK: - Proceso de escucha

    private func launch() {
        let process = Process()
        process.executableURL = Self.perl
        process.arguments = ["-e", Self.supervisor, scriptURL.path, frameworkURL.path, "stream", "--micros", "--debounce=100"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let reader = LineReader { [weak self] update in
            Task { @MainActor in self?.apply(update) }
        }
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                reader.append(data)
            }
        }
        process.terminationHandler = { [weak self] process in
            let status = process.terminationStatus
            Task { @MainActor in self?.processEnded(process, status: status) }
        }

        do {
            try process.run()
            self.process = process
            Log.music.info("Escucha de MediaRemote iniciada")
        } catch {
            Log.music.error("No se pudo iniciar mediaremote-adapter: \(error.localizedDescription, privacy: .public)")
            markBroken()
            return
        }

        // El adaptador emite el estado completo nada más arrancar; si no lo
        // hace, se considera que macOS ya no le permite leer MediaRemote.
        watchdog?.cancel()
        watchdog = Task { [weak self] in
            try? await Task.sleep(for: Self.startupTimeout)
            guard !Task.isCancelled, let self, !self.isFunctional, self.process === process else { return }
            Log.music.error("mediaremote-adapter no respondió; se usa el respaldo")
            self.terminate()
            self.markBroken()
        }
    }

    private func apply(_ update: MediaRemoteUpdate) {
        if !isFunctional {
            isFunctional = true
            watchdog?.cancel()
            Log.music.info("MediaRemote disponible")
        }
        state = update.isDiff ? Self.merge(update.payload, into: state) : update.payload
        notify()
    }

    /// Aplica un diff al estado acumulado. El aviso de reproducción o pausa
    /// solo trae `playing`: la velocidad y la posición siguen siendo las del
    /// estado anterior, y una velocidad 0 rezagada haría pasar por pausada una
    /// pista que ya suena. En ese caso se descarta la velocidad y la posición
    /// se ancla al momento del cambio.
    nonisolated static func merge(_ diff: [String: MediaRemoteValue], into state: [String: MediaRemoteValue], now: Date = .now) -> [String: MediaRemoteValue] {
        var merged = state
        for (key, value) in diff {
            if case .null = value { merged[key] = nil } else { merged[key] = value }
        }
        guard case .bool(let playing) = diff["playing"], diff["playbackRate"] == nil else { return merged }
        merged["playbackRate"] = nil
        guard diff["timestampEpochMicros"] == nil, diff["elapsedTimeMicros"] == nil else { return merged }
        let nowMicros = now.timeIntervalSince1970 * 1_000_000
        // Al pausar, la posición avanzó desde la última marca si estaba sonando.
        if !playing, let before = MediaRemotePayload(state), before.isPlaying,
           case .number(let elapsed) = state["elapsedTimeMicros"],
           case .number(let stamp) = state["timestampEpochMicros"] {
            merged["elapsedTimeMicros"] = .number(elapsed + max(nowMicros - stamp, 0))
        }
        merged["timestampEpochMicros"] = .number(nowMicros)
        return merged
    }

    private func processEnded(_ ended: Process, status: Int32) {
        guard ended === process else { return }
        process = nil
        watchdog?.cancel()
        let wasFunctional = isFunctional
        isFunctional = false
        state = [:]
        notify()
        guard !subscribers.isEmpty else { return }

        Log.music.error("mediaremote-adapter terminó con código \(status)")
        let now = Date.now
        failures = failures.filter { now.timeIntervalSince($0) < 60 } + [now]
        guard failures.count <= Self.maxFailuresPerMinute else {
            markBroken()
            return
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(wasFunctional ? 1 : 3))
            guard let self, self.process == nil, !self.subscribers.isEmpty else { return }
            self.launch()
        }
    }

    private func unsubscribe(_ id: UUID) {
        subscribers[id] = nil
        if subscribers.isEmpty { terminate() }
    }

    private func terminate() {
        watchdog?.cancel()
        retryTask?.cancel()
        guard let process else { return }
        self.process = nil
        process.terminationHandler = nil
        if process.isRunning { process.terminate() }
        isFunctional = false
        state = [:]
    }

    private func markBroken() {
        isFunctional = false
        state = [:]
        notify()
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: Self.brokenRetryDelay)
            guard !Task.isCancelled, let self, self.process == nil, !self.subscribers.isEmpty else { return }
            self.failures = []
            self.launch()
        }
    }

    private func notify() {
        subscribers.values.forEach { $0.yield() }
    }

    private func appName(for bundleIdentifier: String) -> String {
        if let cached = appNames[bundleIdentifier] { return cached }
        var name = bundleIdentifier
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            name = FileManager.default.displayName(atPath: url.path)
            if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
        }
        appNames[bundleIdentifier] = name
        return name
    }

    /// Reproductores sin paquete de app (p. ej. uno de terminal): MediaRemote
    /// solo da su PID, así que se identifican por el nombre del proceso.
    private func processPlayer(pid: Int32?) -> PlayerID {
        var name: String?
        if let pid {
            name = NSRunningApplication(processIdentifier: pid)?.localizedName
            if name == nil {
                var buffer = [CChar](repeating: 0, count: 256)
                if proc_name(pid, &buffer, UInt32(buffer.count)) > 0 { name = String(cString: buffer) }
            }
        }
        let display = name ?? String(localized: "Reproductor desconocido")
        return PlayerID(bundleIdentifier: "process.\(display)", displayName: display)
    }

    private static func runOnce(arguments: [String]) async throws -> Int32 {
        let process = Process()
        process.executableURL = perl
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}

// MARK: - Formato de salida del adaptador

/// Valor de un campo del adaptador. La carátula llega en base64 y se decodifica
/// al leer la línea, fuera del hilo principal.
enum MediaRemoteValue: Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case data(Data)
    case null
}

/// Una línea de `stream`: el estado completo o solo los campos que cambiaron.
struct MediaRemoteUpdate: Equatable, Sendable {
    var isDiff: Bool
    var payload: [String: MediaRemoteValue]

    init(isDiff: Bool, payload: [String: MediaRemoteValue]) {
        self.isDiff = isDiff
        self.payload = payload
    }

    init?(line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "data",
              let payload = object["payload"] as? [String: Any] else { return nil }
        isDiff = object["diff"] as? Bool ?? false
        self.payload = payload.reduce(into: [:]) { result, entry in
            result[entry.key] = Self.value(for: entry.key, entry.value)
        }
    }

    private static func value(for key: String, _ raw: Any) -> MediaRemoteValue {
        switch raw {
        case is NSNull:
            return .null
        case let number as NSNumber:
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? .bool(number.boolValue) : .number(number.doubleValue)
        case let string as String where key == "artworkData":
            return Data(base64Encoded: string).map(MediaRemoteValue.data) ?? .null
        case let string as String:
            return .string(string)
        default:
            return .null
        }
    }
}

/// Vista tipada del estado acumulado. `nil` si no hay nada reproduciéndose.
struct MediaRemotePayload: Equatable, Sendable {
    /// Falta en procesos que no son apps con paquete, como un reproductor de terminal.
    var bundleIdentifier: String?
    var parentBundleIdentifier: String?
    var processIdentifier: Int32?
    var title: String
    var artist: String?
    var album: String?
    var isPlaying: Bool
    var duration: TimeInterval?
    var elapsed: TimeInterval
    var timestamp: Date?
    var itemIdentifier: String?

    init?(_ state: [String: MediaRemoteValue]) {
        func string(_ key: String) -> String? {
            guard case .string(let value) = state[key], !value.isEmpty else { return nil }
            return value
        }
        func number(_ key: String) -> Double? {
            guard case .number(let value) = state[key] else { return nil }
            return value
        }
        guard let title = string("title") else { return nil }
        bundleIdentifier = string("bundleIdentifier")
        parentBundleIdentifier = string("parentApplicationBundleIdentifier")
        processIdentifier = number("processIdentifier").map { Int32($0) }
        self.title = title
        artist = string("artist")
        album = string("album")
        var playing = false
        if case .bool(let value) = state["playing"] { playing = value }
        // Un reproductor en pausa puede seguir informando "playing" con velocidad 0.
        if number("playbackRate") == 0 { playing = false }
        isPlaying = playing
        duration = number("durationMicros").map { $0 / 1_000_000 }.flatMap { $0 > 0 ? $0 : nil }
        elapsed = max((number("elapsedTimeMicros") ?? 0) / 1_000_000, 0)
        timestamp = number("timestampEpochMicros").map { Date(timeIntervalSince1970: $0 / 1_000_000) }
        itemIdentifier = string("contentItemIdentifier") ?? string("uniqueIdentifier")
    }

    /// App que el usuario reconoce: el navegador, no su proceso auxiliar.
    var appBundleIdentifier: String? { parentBundleIdentifier ?? bundleIdentifier }

    func nowPlaying(player: PlayerID, now: Date = .now) -> NowPlaying {
        NowPlaying(
            player: player,
            trackID: itemIdentifier,
            title: title,
            artist: artist,
            album: album,
            duration: duration,
            isPlaying: isPlaying,
            position: elapsed,
            positionDate: timestamp ?? now
        )
    }
}

/// Acumula la salida del proceso y entrega cada línea completa ya interpretada.
final class LineReader: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private let onUpdate: @Sendable (MediaRemoteUpdate) -> Void

    init(onUpdate: @escaping @Sendable (MediaRemoteUpdate) -> Void) {
        self.onUpdate = onUpdate
    }

    func append(_ data: Data) {
        let lines: [Data] = lock.withLock {
            buffer.append(data)
            var complete: [Data] = []
            while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                complete.append(buffer[buffer.startIndex..<newline])
                buffer.removeSubrange(buffer.startIndex...newline)
            }
            return complete
        }
        for line in lines where !line.isEmpty {
            if let update = MediaRemoteUpdate(line: Data(line)) { onUpdate(update) }
        }
    }
}
