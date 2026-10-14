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
