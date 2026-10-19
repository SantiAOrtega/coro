import Foundation

/// A track as reported by any now-playing source (Spotify, Apple Music, demo).
public struct TrackInfo: Equatable, Hashable, Sendable, Codable {
    /// Stable identifier from the source (Spotify ID, persistent ID, ...).
    public let id: String
    public let title: String
    /// Primary artist only — lyric providers match better on a single name.
    public let artist: String
    /// Every credited artist, primary first. LRCLIB often files a collaboration under the
    /// featured artist or under all of them ("Bizarrap, Quevedo").
    public let artists: [String]
    public let album: String?
    /// Track length in seconds.
    public let duration: TimeInterval

    public init(id: String, title: String, artist: String, artists: [String]? = nil,
                album: String?, duration: TimeInterval) {
        self.id = id
        self.title = title
        self.artist = artist
        self.artists = artists ?? [artist]
        self.album = album
        self.duration = duration
    }

    /// Splits a combined credit ("Bad Bunny & Chencho Corleone", "A, B feat. C") into names.
    public static func splitArtists(_ credit: String) -> [String] {
        let separators = [" feat. ", " ft. ", " featuring ", " & ", ", ", " x ", " y ", " and "]
        var parts = [credit]
        for separator in separators {
            parts = parts.flatMap { $0.components(separatedBy: separator) }
        }
        let names = parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return names.isEmpty ? [credit] : names
    }
}

/// A point-in-time reading of the player. Position between polls is extrapolated locally,
/// which lets us poll the API every few seconds while still moving lyrics line by line.
public struct PlaybackSnapshot: Equatable, Sendable {
    public let track: TrackInfo
    public let isPlaying: Bool
    /// Playback position in seconds at `capturedAt`.
    public let progress: TimeInterval
    public let capturedAt: Date

    public init(track: TrackInfo, isPlaying: Bool, progress: TimeInterval, capturedAt: Date) {
        self.track = track
        self.isPlaying = isPlaying
        self.progress = progress
        self.capturedAt = capturedAt
    }

    /// Estimated playback position at `date`.
    public func position(at date: Date) -> TimeInterval {
        guard isPlaying else { return progress }
        let estimate = progress + date.timeIntervalSince(capturedAt)
        return min(max(0, estimate), track.duration)
    }
}

public struct LyricLine: Equatable, Hashable, Sendable, Codable {
    /// Start time in seconds.
    public let time: TimeInterval
    public let text: String

    public init(time: TimeInterval, text: String) {
        self.time = time
        self.text = text
    }
}

public enum Lyrics: Equatable, Sendable, Codable {
    case synced([LyricLine])
    case plain([String])
    case instrumental
    case notFound

    public var isSynced: Bool {
        if case .synced = self { return true }
        return false
    }
}
