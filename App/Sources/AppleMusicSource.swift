import CoroKit
import Foundation
import MediaPlayer

/// Reads the system Music app's player locally — no network, no account needed.
@MainActor
final class AppleMusicSource: NowPlayingSource {
    let kind: SourceKind = .appleMusic
    private let player = MPMusicPlayerController.systemMusicPlayer

    func prepare() async throws {
        let status: MPMediaLibraryAuthorizationStatus
        if MPMediaLibrary.authorizationStatus() == .notDetermined {
            status = await withCheckedContinuation { continuation in
                MPMediaLibrary.requestAuthorization { continuation.resume(returning: $0) }
            }
        } else {
            status = MPMediaLibrary.authorizationStatus()
        }
        guard status == .authorized else { throw NowPlayingError.permissionDenied("leer Apple Music") }
    }

    func snapshot() async throws -> PlaybackSnapshot? {
        guard let item = player.nowPlayingItem, let title = item.title else { return nil }
        let id = item.playbackStoreID.isEmpty ? String(item.persistentID) : item.playbackStoreID
        let track = TrackInfo(
            id: "am-\(id)",
            title: title,
            artist: item.artist ?? "",
            artists: TrackInfo.splitArtists(item.artist ?? ""),
            album: item.albumTitle,
            duration: item.playbackDuration
        )
        let position = player.currentPlaybackTime
        return PlaybackSnapshot(
            track: track,
            isPlaying: player.playbackState == .playing,
            progress: position.isFinite ? position : 0,
            capturedAt: Date()
        )
    }
}
