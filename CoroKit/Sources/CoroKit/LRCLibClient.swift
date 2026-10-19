import Foundation

/// Raw record returned by https://lrclib.net/api
public struct LRCLibRecord: Decodable, Sendable {
    public let id: Int?
    public let trackName: String?
    public let artistName: String?
    public let albumName: String?
    public let duration: Double?
    public let instrumental: Bool?
    public let plainLyrics: String?
    public let syncedLyrics: String?
}

/// Abstraction so the engine can swap providers (LRCLIB for prototype, Musixmatch for the store build).
public protocol LyricsProvider: Sendable {
    func lyrics(for track: TrackInfo) async throws -> Lyrics
}

public enum LyricsProviderError: Error, Sendable {
    case badResponse(Int)
}

/// Lyrics are fetched at runtime on the user's device and only cached locally; nothing is bundled.
public actor LRCLibClient: LyricsProvider {
    private let session: URLSession
    private let baseURL = URL(string: "https://lrclib.net/api")!
    private let userAgent: String
    private let cacheDirectory: URL?
    private var memoryCache: [String: Lyrics] = [:]

    public init(session: URLSession = .shared, userAgent: String, cacheDirectory: URL? = nil) {
        self.session = session
        self.userAgent = userAgent
        self.cacheDirectory = cacheDirectory
        if let cacheDirectory {
            try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        }
    }

    public func lyrics(for track: TrackInfo) async throws -> Lyrics {
        if let cached = memoryCache[track.id] ?? loadFromDisk(track.id) {
            memoryCache[track.id] = cached
            return cached
        }

        var result = try await exactMatch(for: track)
        if result == nil || result == .notFound {
            result = try await searchMatch(for: track)
        }
        if result == nil || result == .notFound {
            result = try await titleOnlyMatch(for: track)
        }
        let lyrics = result ?? .notFound

        memoryCache[track.id] = lyrics
        if lyrics != .notFound { saveToDisk(lyrics, id: track.id) }
        return lyrics
    }

    // MARK: - Requests

    private func exactMatch(for track: TrackInfo) async throws -> Lyrics? {
        var query: [(String, String)] = [
            ("track_name", track.title),
            ("artist_name", track.artist),
            ("duration", String(Int(track.duration.rounded())))
        ]
        if let album = track.album, !album.isEmpty { query.append(("album_name", album)) }

        let (data, status) = try await get("get", query: query)
        if status == 404 { return nil }
        guard status == 200 else { throw LyricsProviderError.badResponse(status) }
        let record = try JSONDecoder().decode(LRCLibRecord.self, from: data)
        return Self.lyrics(from: record)
    }

    private func searchMatch(for track: TrackInfo) async throws -> Lyrics? {
        let query = [("track_name", TitleNormalizer.clean(track.title)), ("artist_name", track.artist)]
        let (data, status) = try await get("search", query: query)
        guard status == 200 else { throw LyricsProviderError.badResponse(status) }
        let records = try JSONDecoder().decode([LRCLibRecord].self, from: data)
        guard let best = Self.bestRecord(records, duration: track.duration) else { return nil }
        return Self.lyrics(from: best)
    }

    /// Songs LRCLIB files under another artist spelling or a featured artist
    /// ("Bizarrap, Quevedo", "KAROL G & Peso Pluma"): search by title alone and keep
    /// only records whose title and artist agree with the track.
    private func titleOnlyMatch(for track: TrackInfo) async throws -> Lyrics? {
        let (data, status) = try await get("search", query: [("track_name", TitleNormalizer.clean(track.title))])
        guard status == 200 else { throw LyricsProviderError.badResponse(status) }
        let records = try JSONDecoder().decode([LRCLibRecord].self, from: data)
        let matching = records.filter { Self.matches($0, track) }
        guard let best = Self.bestRecord(matching, duration: track.duration) else { return nil }
        return Self.lyrics(from: best)
    }

    /// LRCLIB answers 429/5xx or drops the connection now and then; without a retry
    /// the song would show "sin letra" until the next track.
    private static let retryDelays: [Duration] = [.milliseconds(600), .milliseconds(1500)]

    private func get(_ path: String, query: [(String, String)]) async throws -> (Data, Int) {
        let encoded = query.map { "\($0.0)=\(Self.percentEncode($0.1))" }.joined(separator: "&")
        guard let url = URL(string: baseURL.appendingPathComponent(path).absoluteString + "?" + encoded) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        var attempt = 0
        while true {
            let canRetry = attempt < Self.retryDelays.count
            do {
                let (data, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard canRetry, status == 429 || status >= 500 else { return (data, status) }
            } catch let error as URLError where canRetry && error.code != .cancelled {
                // Retried below.
            }
            try await Task.sleep(for: Self.retryDelays[attempt])
            attempt += 1
        }
    }

    // MARK: - Pure helpers (unit-tested)

    /// Prefers synced lyrics whose duration is within 3 s; then any synced; then plain.
    static func bestRecord(_ records: [LRCLibRecord], duration: TimeInterval) -> LRCLibRecord? {
        func distance(_ record: LRCLibRecord) -> Double { abs((record.duration ?? .infinity) - duration) }
        let synced = records.filter { !($0.syncedLyrics ?? "").isEmpty }
        if let close = synced.filter({ distance($0) <= 3 }).min(by: { distance($0) < distance($1) }) { return close }
        if let any = synced.min(by: { distance($0) < distance($1) }), distance(any) <= 15 { return any }
        return records.first { !($0.plainLyrics ?? "").isEmpty }
    }

    /// Same title once cleaned, and one of the track's artists named in the record's credit.
    static func matches(_ record: LRCLibRecord, _ track: TrackInfo) -> Bool {
        let title = TitleNormalizer.key(TitleNormalizer.clean(track.title))
        guard !title.isEmpty, TitleNormalizer.key(TitleNormalizer.clean(record.trackName ?? "")) == title else {
            return false
        }
        let credit = " \(TitleNormalizer.key(record.artistName ?? "")) "
        return ([track.artist] + track.artists).contains { artist in
            let name = TitleNormalizer.key(artist)
            return !name.isEmpty && credit.contains(" \(name) ")
        }
    }

    static func lyrics(from record: LRCLibRecord) -> Lyrics {
        if record.instrumental == true { return .instrumental }
        if let synced = record.syncedLyrics, !synced.isEmpty {
            let lines = LRCParser.parse(synced)
            if !lines.isEmpty { return .synced(lines) }
        }
        if let plain = record.plainLyrics, !plain.isEmpty {
            return .plain(plain.components(separatedBy: .newlines))
        }
        return .notFound
    }

    static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    // MARK: - Disk cache

    private func cacheURL(_ id: String) -> URL? {
        let safe = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
        return cacheDirectory?.appendingPathComponent("\(safe).json")
    }

    private func loadFromDisk(_ id: String) -> Lyrics? {
        guard let url = cacheURL(id), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Lyrics.self, from: data)
    }

    private func saveToDisk(_ lyrics: Lyrics, id: String) {
        guard let url = cacheURL(id), let data = try? JSONEncoder().encode(lyrics) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
