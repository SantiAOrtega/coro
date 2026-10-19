import Foundation

enum AppConfig {
    /// Set in Config.xcconfig → Info.plist (`SpotifyClientID`).
    static var spotifyClientID: String {
        (Bundle.main.object(forInfoDictionaryKey: "SpotifyClientID") as? String)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    static var isSpotifyConfigured: Bool {
        let id = spotifyClientID
        return !id.isEmpty && !id.hasPrefix("$(")
    }

    static let spotifyRedirectScheme = "coro"
    static let spotifyRedirectURI = "coro://spotify-callback"
    static let spotifyScopes = ["user-read-currently-playing", "user-read-playback-state"]

    static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return "Coro/\(version) (iOS lyrics prototype)"
    }

    static var lyricsCacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("lyrics", isDirectory: true)
    }
}
