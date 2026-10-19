import CoroKit
import Foundation

/// Fake player with original placeholder lines, to test the Live Activity / CarPlay
/// pipeline without Spotify. Loops every 48 s.
@MainActor
final class DemoSource: NowPlayingSource {
    let kind: SourceKind = .demo
    private let startedAt = Date()

    private static let track = TrackInfo(id: "demo-1", title: "Prueba de carretera",
                                         artist: "Coro Demo", album: nil, duration: 48)

    // Original text written for this demo.
    private static let script: [(TimeInterval, String)] = [
        (2, "Arranca el motor, empieza la prueba"),
        (6, "Cada línea cambia con el compás"),
        (10, "Si me lees en CarPlay, todo va bien"),
        (14, ""),
        (18, "La siguiente frase ya asoma debajo"),
        (22, "Ajusta el desfase si llego tarde"),
        (26, "o si me adelanto un poco"),
        (30, ""),
        (34, "Ojos en la carretera, ¿vale?"),
        (38, "Tararea, pero conduce tranquilo"),
        (42, "Fin de la demo, vuelvo a empezar")
    ]
    private static let lines: [LyricLine] = script.map { LyricLine(time: $0.0, text: $0.1) }

    func snapshot() async throws -> PlaybackSnapshot? {
        let elapsed = Date().timeIntervalSince(startedAt)
        let duration = Self.track.duration
        let loopStart = startedAt.addingTimeInterval(floor(elapsed / duration) * duration)
        return PlaybackSnapshot(track: Self.track, isPlaying: true, progress: 0, capturedAt: loopStart)
    }

    func bundledLyrics(for track: TrackInfo) -> Lyrics? {
        track.id == Self.track.id ? .synced(Self.lines) : nil
    }
}
