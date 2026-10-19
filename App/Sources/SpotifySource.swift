import CoroKit
import Foundation

/// Polls `GET /v1/me/player/currently-playing` (Development Mode compatible).
@MainActor
final class SpotifySource: NowPlayingSource {
    let kind: SourceKind = .spotify
    private let auth: SpotifyAuth

    init(auth: SpotifyAuth) {
        self.auth = auth
    }

    func prepare() async throws {
        _ = try await auth.validAccessToken()
    }

    func snapshot() async throws -> PlaybackSnapshot? {
        try await fetch(retryOnUnauthorized: true)
    }

    private func fetch(retryOnUnauthorized: Bool) async throws -> PlaybackSnapshot? {
        let token = try await auth.validAccessToken(forceRefresh: !retryOnUnauthorized)
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!,
                                 timeoutInterval: 8)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let sentAt = Date()
        let (data, response) = try await URLSession.shared.data(for: request)
        let receivedAt = Date()
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0

        switch status {
        case 200: break
        case 204: return nil
        case 401 where retryOnUnauthorized:
            return try await fetch(retryOnUnauthorized: false)
        case 429:
            let retry = TimeInterval(http?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 10
            throw NowPlayingError.rateLimited(retryAfter: retry)
        default:
            throw NowPlayingError.http(status)
        }

        let payload = try JSONDecoder().decode(CurrentlyPlaying.self, from: data)
        guard let item = payload.item, payload.currently_playing_type == "track" else { return nil }

        let track = TrackInfo(
            id: item.id ?? "\(item.name)-\(item.duration_ms)",
            title: item.name,
            artist: item.artists.first?.name ?? "",
            artists: item.artists.map(\.name),
            album: item.album?.name,
            duration: Double(item.duration_ms) / 1000
        )
        // Assume the server sampled the position halfway through the round trip.
        let capturedAt = sentAt.addingTimeInterval(receivedAt.timeIntervalSince(sentAt) / 2)
        return PlaybackSnapshot(
            track: track,
            isPlaying: payload.is_playing,
            progress: Double(payload.progress_ms ?? 0) / 1000,
            capturedAt: capturedAt
        )
    }

    private struct CurrentlyPlaying: Decodable {
        let progress_ms: Int?
        let is_playing: Bool
        let currently_playing_type: String?
        let item: Item?

        struct Item: Decodable {
            let id: String?
            let name: String
            let duration_ms: Int
            let album: Album?
            let artists: [Artist]
        }
        struct Album: Decodable { let name: String? }
        struct Artist: Decodable { let name: String }
    }
}
