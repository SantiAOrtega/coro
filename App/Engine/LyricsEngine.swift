import CoroKit
import Foundation

/// Orchestrates: now-playing source → lyrics provider → sync → UI + Live Activity (CarPlay).
@MainActor
final class LyricsEngine: ObservableObject {
    typealias ActivityState = LyricsActivityAttributes.ContentState

    // MARK: Published state

    @Published var sourceKind: SourceKind {
        didSet { UserDefaults.standard.set(sourceKind.rawValue, forKey: Keys.source) }
    }
    /// Seconds added to the playback position. Positive = lines appear earlier.
    @Published var syncOffset: Double {
        didSet { UserDefaults.standard.set(syncOffset, forKey: Keys.offset) }
    }
    @Published var keepAliveInBackground: Bool {
        didSet { UserDefaults.standard.set(keepAliveInBackground, forKey: Keys.keepAlive) }
    }
    /// Part of every Live Activity state, so the next tick pushes a change to CarPlay.
    @Published var carPlayStyle: CarPlayStyle {
        didSet { UserDefaults.standard.set(carPlayStyle.rawValue, forKey: Keys.carPlayStyle) }
    }

    @Published private(set) var isRunning = false
    @Published private(set) var snapshot: PlaybackSnapshot?
    @Published private(set) var lyrics: Lyrics = .notFound
    @Published private(set) var isLoadingLyrics = false
    @Published private(set) var frame: LyricsFrame?
    @Published private(set) var position: TimeInterval = 0
    /// Persistent problem the user must fix (permissions, config).
    @Published private(set) var setupMessage: String?
    /// Transient problem (network, rate limit) — clears on the next good poll.
    @Published private(set) var transientMessage: String?

    let auth = SpotifyAuth()

    // MARK: Collaborators

    private let provider: LyricsProvider
    private let liveActivity = LiveActivityController()
    private let keeper = BackgroundKeeper()
    private var source: NowPlayingSource?
    private var loopTask: Task<Void, Never>?
    private var lyricsTask: Task<Void, Never>?
    private var expectedTrackID: String?
    private var nextPoll = Date.distantPast
    private var lastSentState: ActivityState?

    private enum Keys {
        static let source = "engine.source"
        static let offset = "engine.syncOffset"
        static let keepAlive = "engine.keepAlive"
        static let carPlayStyle = "engine.carPlayStyle"
    }

    init(provider: LyricsProvider? = nil) {
        self.provider = provider ?? LRCLibClient(userAgent: AppConfig.userAgent,
                                                 cacheDirectory: AppConfig.lyricsCacheDirectory)
        let defaults = UserDefaults.standard
        sourceKind = SourceKind(rawValue: defaults.string(forKey: Keys.source) ?? "") ?? .spotify
        syncOffset = defaults.object(forKey: Keys.offset) as? Double ?? 0.3
        keepAliveInBackground = defaults.object(forKey: Keys.keepAlive) as? Bool ?? true
        carPlayStyle = CarPlayStyle(rawValue: defaults.string(forKey: Keys.carPlayStyle) ?? "") ?? .large
        liveActivity.endAllStale()
    }

    // MARK: Lifecycle

    func start() async {
        guard !isRunning else { return }
        setupMessage = nil
        transientMessage = nil

        let source = makeSource(sourceKind)
        do {
            try await source.prepare()
        } catch {
            setupMessage = error.localizedDescription
            return
        }

        self.source = source
        isRunning = true
        nextPoll = .distantPast
        if keepAliveInBackground { keeper.start() }

        if liveActivity.areActivitiesEnabled {
            do {
                try liveActivity.start(sourceName: source.kind.rawValue, state: idleState())
            } catch {
                setupMessage = "No se pudo crear la Live Activity: \(error.localizedDescription)"
            }
        } else {
            setupMessage = "Activa las Actividades en directo de Coro en Ajustes para verlo en CarPlay."
        }

        loopTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if Date() >= self.nextPoll { await self.poll() }
                self.tick()
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
        lyricsTask?.cancel()
        lyricsTask = nil
        keeper.stop()
        liveActivity.end()
        isRunning = false
        source = nil
        snapshot = nil
        frame = nil
        lyrics = .notFound
        expectedTrackID = nil
        lastSentState = nil
        transientMessage = nil
    }

    func restart() async {
        stop()
        await start()
    }

    func report(_ error: Error) {
        setupMessage = error.localizedDescription
    }

    // MARK: Polling

    private func makeSource(_ kind: SourceKind) -> NowPlayingSource {
        switch kind {
        case .spotify: return SpotifySource(auth: auth)
        case .appleMusic: return AppleMusicSource()
        case .demo: return DemoSource()
        }
    }

    private func poll() async {
        guard let source else { return }
        do {
            let latest = try await source.snapshot()
            guard isRunning else { return }
            if latest?.track != snapshot?.track { trackChanged(to: latest?.track) }
            snapshot = latest
            transientMessage = nil
            nextPoll = Date().addingTimeInterval(pollInterval(for: latest, kind: source.kind))
        } catch NowPlayingError.rateLimited(let retryAfter) {
            transientMessage = NowPlayingError.rateLimited(retryAfter: retryAfter).localizedDescription
            nextPoll = Date().addingTimeInterval(max(retryAfter, 5))
        } catch let error as SpotifyAuthError {
            setupMessage = error.localizedDescription
            nextPoll = Date().addingTimeInterval(15)
        } catch {
            transientMessage = "Sin conexión con \(source.kind.rawValue)"
            nextPoll = Date().addingTimeInterval(5)
        }
    }

    /// Adaptive polling keeps us well inside Spotify's Development Mode quota:
    /// ~20 req/min while playing, faster only right before a track ends.
    private func pollInterval(for snapshot: PlaybackSnapshot?, kind: SourceKind) -> TimeInterval {
        switch kind {
        case .demo: return 30
        case .appleMusic: return 1 // local API, free
        case .spotify:
            guard let snapshot else { return 5 }
            guard snapshot.isPlaying else { return 4 }
            let remaining = snapshot.track.duration - snapshot.position(at: Date())
            return remaining < 4 ? max(1, remaining) : 3
        }
    }

    private func trackChanged(to track: TrackInfo?) {
        lyricsTask?.cancel()
        lyrics = .notFound
        frame = nil
        lastSentState = nil
        expectedTrackID = track?.id
        isLoadingLyrics = false
        guard let track else { return }

        if let bundled = source?.bundledLyrics(for: track) {
            lyrics = bundled
            return
        }

        isLoadingLyrics = true
        let provider = self.provider
        lyricsTask = Task { [weak self] in
            // LRCLIB has short outages: a failed download is tried again while the track keeps playing.
            for delay in [0, 10, 30] {
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                guard !Task.isCancelled else { return }
                let result: Lyrics
                do {
                    result = try await provider.lyrics(for: track)
                } catch {
                    await MainActor.run {
                        guard let self, self.expectedTrackID == track.id else { return }
                        self.isLoadingLyrics = false
                        if delay == 0 { self.transientMessage = "No pude descargar la letra" }
                    }
                    continue
                }
                await MainActor.run {
                    guard let self, !Task.isCancelled, self.expectedTrackID == track.id else { return }
                    self.lyrics = result
                    self.isLoadingLyrics = false
                }
                return
            }
        }
    }

    // MARK: Rendering

    private func tick() {
        guard let snapshot else {
            frame = nil
            send(idleState())
            return
        }

        let now = snapshot.position(at: Date())
        position = now

        let newFrame = isLoadingLyrics
            ? LyricsFrame(previous: nil, current: "Buscando letra…", next: nil, index: nil)
            : LyricsSync.frame(for: lyrics, at: now + syncOffset)
        if newFrame != frame { frame = newFrame }

        let duration = snapshot.track.duration
        send(ActivityState(
            title: snapshot.track.title,
            artist: snapshot.track.artist,
            previous: newFrame.previous,
            current: newFrame.current,
            next: newFrame.next,
            isPlaying: snapshot.isPlaying,
            progress: duration > 0 ? min(1, now / duration) : 0,
            carPlayStyle: carPlayStyle
        ))
    }

    /// Only pushes to the Live Activity when visible text or play state changes
    /// (~once per lyric line), which stays within iOS update budgets.
    private func send(_ state: ActivityState) {
        var comparable = state
        comparable.progress = 0
        guard comparable != lastSentState else { return }
        lastSentState = comparable
        liveActivity.update(state)
    }

    private func idleState() -> ActivityState {
        ActivityState(title: "Coro", artist: sourceKind.rawValue, previous: nil,
                      current: "Esperando música…", next: "Dale al play en \(sourceKind.rawValue)",
                      isPlaying: false, progress: 0, carPlayStyle: carPlayStyle)
    }
}
