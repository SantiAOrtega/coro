#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

/// Shared between the app (which starts/updates the Live Activity) and the widget extension
/// (which renders it on the Lock Screen, Dynamic Island and CarPlay).
public struct LyricsActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var title: String
        public var artist: String
        public var previous: String?
        public var current: String
        public var next: String?
        public var isPlaying: Bool
        /// Song progress 0...1, refreshed on every line change.
        public var progress: Double
        /// Travels with every update, so changing it in Settings redraws CarPlay at once.
        public var carPlayStyle: CarPlayStyle

        public init(title: String, artist: String, previous: String?, current: String,
                    next: String?, isPlaying: Bool, progress: Double, carPlayStyle: CarPlayStyle = .large) {
            self.title = title
            self.artist = artist
            self.previous = previous
            self.current = current
            self.next = next
            self.isPlaying = isPlaying
            self.progress = progress
            self.carPlayStyle = carPlayStyle
        }
    }

    /// "Spotify", "Apple Music" or "Demo".
    public var sourceName: String

    public init(sourceName: String) {
        self.sourceName = sourceName
    }
}
#endif
