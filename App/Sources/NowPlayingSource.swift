import CoroKit
import Foundation

enum SourceKind: String, CaseIterable, Identifiable {
    case spotify = "Spotify"
    case appleMusic = "Apple Music"
    case demo = "Demo"

    var id: String { rawValue }
}

enum NowPlayingError: LocalizedError {
    case rateLimited(retryAfter: TimeInterval)
    case http(Int)
    case permissionDenied(String)

    var errorDescription: String? {
        switch self {
        case .rateLimited(let seconds): return "Spotify pide esperar \(Int(seconds)) s"
        case .http(let code): return "Error de Spotify (\(code))"
        case .permissionDenied(let what): return "Sin permiso para \(what)"
        }
    }
}

/// Anything that can tell us what is playing and where. Spotify, Apple Music and the demo
/// implement it; a future backend-driven source (push to Live Activity) would too.
@MainActor
protocol NowPlayingSource: AnyObject {
    var kind: SourceKind { get }
    /// Called once when the engine starts with this source (permissions, timers...).
    func prepare() async throws
    /// `nil` means nothing is playing.
    func snapshot() async throws -> PlaybackSnapshot?
    /// Sources that already know the lyrics (demo) return them here and skip the provider.
    func bundledLyrics(for track: TrackInfo) -> Lyrics?
}

extension NowPlayingSource {
    func prepare() async throws {}
    func bundledLyrics(for track: TrackInfo) -> Lyrics? { nil }
}
