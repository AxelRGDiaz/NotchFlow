import Foundation

public struct PlayerID: Hashable, Sendable {
    public var bundleIdentifier: String
    public var displayName: String

    public init(bundleIdentifier: String, displayName: String) {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
    }

    public static let appleMusic = PlayerID(bundleIdentifier: "com.apple.Music", displayName: "Music")
    public static let spotify = PlayerID(bundleIdentifier: "com.spotify.client", displayName: "Spotify")
}

public enum MusicCommand: Equatable, Sendable {
    case playPause
    case next
    case previous
    /// Salta a esa posición de la pista, en segundos.
    case seek(to: TimeInterval)
}

/// Instantánea de la reproducción. La posición se guarda junto al instante en
/// que se midió para interpolar el progreso sin volver a consultar al reproductor.
public struct NowPlaying: Equatable, Sendable {
    public var player: PlayerID
    /// Identificador de pista del reproductor; sirve para cachear la carátula.
    public var trackID: String?
    public var title: String
    public var artist: String?
    public var album: String?
    public var duration: TimeInterval?
    public var isPlaying: Bool
    public var position: TimeInterval
    public var positionDate: Date

    public init(
        player: PlayerID,
        trackID: String? = nil,
        title: String,
        artist: String? = nil,
        album: String? = nil,
        duration: TimeInterval? = nil,
        isPlaying: Bool,
        position: TimeInterval = 0,
        positionDate: Date = .now
    ) {
        self.player = player
        self.trackID = trackID
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.isPlaying = isPlaying
        self.position = position
        self.positionDate = positionDate
    }

    public func position(at now: Date) -> TimeInterval {
        let elapsed = isPlaying ? max(now.timeIntervalSince(positionDate), 0) : 0
        let value = max(position + elapsed, 0)
        guard let duration, duration > 0 else { return value }
        return min(value, duration)
    }

    /// Progreso entre 0 y 1, o `nil` si el reproductor no informa la duración.
    public func progress(at now: Date) -> Double? {
        guard let duration, duration > 0 else { return nil }
        return position(at: now) / duration
    }
}

/// Salto pedido al reproductor que todavía no se refleja en sus datos. El
/// reproductor tarda un momento en aplicarlo y en avisar: sin esto, la lectura
/// siguiente devolvería la barra a la posición vieja antes de saltar de nuevo.
public struct PendingSeek: Equatable, Sendable {
    /// Pasado este tiempo se acepta lo que diga el reproductor.
    public static let timeout: TimeInterval = 3
    /// Diferencia admitida para dar el salto por aplicado.
    public static let tolerance: TimeInterval = 1.5

    public var trackKey: String
    public var position: TimeInterval
    public var date: Date

    public init(track: NowPlaying, position: TimeInterval, date: Date) {
        trackKey = Self.key(track)
        self.position = position
        self.date = date
    }

    /// La pista a mostrar y si hay que seguir esperando al reproductor.
    public func reconcile(_ track: NowPlaying, now: Date) -> (track: NowPlaying, stillPending: Bool) {
        guard Self.key(track) == trackKey, now.timeIntervalSince(date) < Self.timeout else { return (track, false) }
        var expected = track
        expected.position = position
        expected.positionDate = date
        if abs(track.position(at: now) - expected.position(at: now)) <= Self.tolerance {
            return (track, false)
        }
        return (expected, true)
    }

    private static func key(_ track: NowPlaying) -> String {
        track.trackID ?? "\(track.title)|\(track.artist ?? "")"
    }
}
