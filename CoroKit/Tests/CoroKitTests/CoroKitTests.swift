import XCTest
@testable import CoroKit

// All lyric text below is invented placeholder text written for these tests.

final class LRCParserTests: XCTestCase {
    func testParsesBasicTimestampsInOrder() {
        let lrc = """
        [ar:Artista Inventado]
        [ti:Cancion de Prueba]
        [00:12.50]Primera linea de prueba
        [00:05.00]Linea cero
        [01:02.123]Linea con milisegundos
        """
        let lines = LRCParser.parse(lrc)
        XCTAssertEqual(lines.map(\.text), ["Linea cero", "Primera linea de prueba", "Linea con milisegundos"])
        XCTAssertEqual(lines[0].time, 5.0, accuracy: 0.001)
        XCTAssertEqual(lines[1].time, 12.5, accuracy: 0.001)
        XCTAssertEqual(lines[2].time, 62.123, accuracy: 0.001)
    }

    func testMultipleTimestampsOnOneLine() {
        let lines = LRCParser.parse("[00:10.00][00:30.00]Estribillo inventado\n[00:20.00]Verso")
        XCTAssertEqual(lines.map(\.text), ["Estribillo inventado", "Verso", "Estribillo inventado"])
        XCTAssertEqual(lines.map(\.time), [10, 20, 30])
    }

    func testColonFractionAndNoFraction() {
        let lines = LRCParser.parse("[00:07]Sin fraccion\n[00:08:50]Fraccion con dos puntos")
        XCTAssertEqual(lines[0].time, 7, accuracy: 0.001)
        XCTAssertEqual(lines[1].time, 8.5, accuracy: 0.001)
    }

    func testOffsetShiftsLyricsEarlier() {
        let lines = LRCParser.parse("[offset:+500]\n[00:10.00]Algo")
        XCTAssertEqual(lines[0].time, 9.5, accuracy: 0.001)
    }

    func testEmptyLinesAreKeptAndGarbageIgnored() {
        let lines = LRCParser.parse("texto suelto\n[00:01.00]\n[xx:yy]nada\n[00:02.00]Hola")
        XCTAssertEqual(lines.map(\.text), ["", "Hola"])
    }

    func testBracketsAfterTimestampStayInText() {
        let lines = LRCParser.parse("[00:03.00][coro] voces")
        XCTAssertEqual(lines.first?.text, "[coro] voces")
    }

    func testCRLFInput() {
        let lines = LRCParser.parse("[00:01.00]Uno\r\n[00:02.00]Dos\r\n")
        XCTAssertEqual(lines.map(\.text), ["Uno", "Dos"])
    }
}

final class LyricsSyncTests: XCTestCase {
    private let lines = [
        LyricLine(time: 5, text: "Uno"),
        LyricLine(time: 10, text: ""),
        LyricLine(time: 15, text: "Tres")
    ]

    func testActiveIndex() {
        XCTAssertNil(LyricsSync.activeIndex(in: lines, at: 4.9))
        XCTAssertEqual(LyricsSync.activeIndex(in: lines, at: 5), 0)
        XCTAssertEqual(LyricsSync.activeIndex(in: lines, at: 12), 1)
        XCTAssertEqual(LyricsSync.activeIndex(in: lines, at: 999), 2)
        XCTAssertNil(LyricsSync.activeIndex(in: [], at: 3))
    }

    func testNextChange() {
        XCTAssertEqual(LyricsSync.nextChange(in: lines, after: 0), 5)
        XCTAssertEqual(LyricsSync.nextChange(in: lines, after: 11), 15)
        XCTAssertNil(LyricsSync.nextChange(in: lines, after: 20))
    }

    func testFrameBeforeFirstLine() {
        let frame = LyricsSync.frame(for: .synced(lines), at: 1)
        XCTAssertEqual(frame.current, LyricsFrame.musicNote)
        XCTAssertEqual(frame.next, "Uno")
        XCTAssertNil(frame.index)
    }

    func testFrameMiddleShowsNoteForEmptyLine() {
        let frame = LyricsSync.frame(for: .synced(lines), at: 11)
        XCTAssertEqual(frame.previous, "Uno")
        XCTAssertEqual(frame.current, LyricsFrame.musicNote)
        XCTAssertEqual(frame.next, "Tres")
        XCTAssertEqual(frame.index, 1)
    }

    func testFrameForNonSynced() {
        XCTAssertEqual(LyricsSync.frame(for: .notFound, at: 0).current, "Sin letra disponible")
        XCTAssertTrue(LyricsSync.frame(for: .instrumental, at: 0).current.hasPrefix("Instrumental"))
        XCTAssertEqual(LyricsSync.frame(for: .synced([]), at: 0).current, "Sin letra disponible")
    }
}

final class PlaybackSnapshotTests: XCTestCase {
    func testExtrapolatesAndClamps() {
        let track = TrackInfo(id: "1", title: "T", artist: "A", album: nil, duration: 100)
        let start = Date(timeIntervalSince1970: 1_000)
        let playing = PlaybackSnapshot(track: track, isPlaying: true, progress: 10, capturedAt: start)
        XCTAssertEqual(playing.position(at: start.addingTimeInterval(5)), 15, accuracy: 0.001)
        XCTAssertEqual(playing.position(at: start.addingTimeInterval(500)), 100, accuracy: 0.001)

        let paused = PlaybackSnapshot(track: track, isPlaying: false, progress: 10, capturedAt: start)
        XCTAssertEqual(paused.position(at: start.addingTimeInterval(5)), 10, accuracy: 0.001)
    }
}

final class TitleNormalizerTests: XCTestCase {
    func testCleansCommonSuffixes() {
        XCTAssertEqual(TitleNormalizer.clean("Mi Cancion - Remastered 2011"), "Mi Cancion")
        XCTAssertEqual(TitleNormalizer.clean("Mi Cancion (feat. Alguien)"), "Mi Cancion")
        XCTAssertEqual(TitleNormalizer.clean("Mi Cancion [Live]"), "Mi Cancion")
        XCTAssertEqual(TitleNormalizer.clean("Mi Cancion - En Directo"), "Mi Cancion")
    }

    func testKeepsMeaningfulParts() {
        XCTAssertEqual(TitleNormalizer.clean("Parte 1 (Interludio)"), "Parte 1 (Interludio)")
        XCTAssertEqual(TitleNormalizer.clean("Antes - Despues"), "Antes - Despues")
    }

    func testCleansSoundtrackAndSpanishSuffixes() {
        XCTAssertEqual(TitleNormalizer.clean("Mi Cancion - From \"La Pelicula\""), "Mi Cancion")
        XCTAssertEqual(TitleNormalizer.clean("Mi Cancion (From \"La Pelicula\" Soundtrack)"), "Mi Cancion")
        XCTAssertEqual(TitleNormalizer.clean("Mi Cancion - Versión Acústica"), "Mi Cancion")
        XCTAssertEqual(TitleNormalizer.clean("Mi Cancion – Sped Up"), "Mi Cancion")
        XCTAssertEqual(TitleNormalizer.clean("Mi Cancion (with Alguien)"), "Mi Cancion")
    }

    func testNoiseIsMatchedOnWholeWords() {
        // "Alive" contains "live" but is part of the title.
        XCTAssertEqual(TitleNormalizer.clean("Cancion (Alive)"), "Cancion (Alive)")
    }

    func testKeyFoldsCaseAccentsAndPunctuation() {
        XCTAssertEqual(TitleNormalizer.key("We Don’t Talk"), TitleNormalizer.key("we dont talk"))
        XCTAssertEqual(TitleNormalizer.key("Canción: Sesión, Vol. 5"), "cancion sesion vol 5")
    }
}

final class CarPlayStyleTests: XCTestCase {
    func testRawValuesAreStableForSavedSettings() {
        XCTAssertEqual(CarPlayStyle.allCases.map(\.rawValue), ["normal", "large", "currentOnly"])
    }

    func testEachStyleGrowsTheCurrentLine() {
        XCTAssertLessThan(CarPlayStyle.normal.currentSize, CarPlayStyle.large.currentSize)
        XCTAssertLessThan(CarPlayStyle.large.currentSize, CarPlayStyle.currentOnly.currentSize)
        XCTAssertNil(CarPlayStyle.currentOnly.nextSize)
        XCTAssertEqual(CarPlayStyle.currentOnly.currentLineLimit, 3)
    }
}

final class TrackInfoTests: XCTestCase {
    func testSplitsCombinedCredits() {
        XCTAssertEqual(TrackInfo.splitArtists("A & B"), ["A", "B"])
        XCTAssertEqual(TrackInfo.splitArtists("A, B feat. C"), ["A", "B", "C"])
        XCTAssertEqual(TrackInfo.splitArtists("Solo"), ["Solo"])
    }

    func testArtistsDefaultToPrimary() {
        XCTAssertEqual(TrackInfo(id: "1", title: "T", artist: "A", album: nil, duration: 1).artists, ["A"])
    }
}

final class LRCLibSelectionTests: XCTestCase {
    private func record(duration: Double?, synced: String?, plain: String? = nil, instrumental: Bool? = nil) -> LRCLibRecord {
        let json: [String: Any?] = ["id": 1, "duration": duration, "syncedLyrics": synced,
                                    "plainLyrics": plain, "instrumental": instrumental]
        let data = try! JSONSerialization.data(withJSONObject: json.compactMapValues { $0 })
        return try! JSONDecoder().decode(LRCLibRecord.self, from: data)
    }

    func testPrefersCloseSyncedMatch() {
        let far = record(duration: 250, synced: "[00:01.00]lejos")
        let close = record(duration: 201, synced: "[00:01.00]cerca")
        let plainOnly = record(duration: 200, synced: nil, plain: "solo texto")
        let best = LRCLibClient.bestRecord([plainOnly, far, close], duration: 200)
        XCTAssertEqual(best?.syncedLyrics, "[00:01.00]cerca")
    }

    func testFallsBackToPlain() {
        let far = record(duration: 400, synced: "[00:01.00]lejos")
        let plainOnly = record(duration: 200, synced: nil, plain: "solo texto")
        XCTAssertEqual(LRCLibClient.bestRecord([far, plainOnly], duration: 200)?.plainLyrics, "solo texto")
    }

    func testRecordToLyrics() {
        XCTAssertEqual(LRCLibClient.lyrics(from: record(duration: 1, synced: nil, instrumental: true)), .instrumental)
        XCTAssertTrue(LRCLibClient.lyrics(from: record(duration: 1, synced: "[00:01.00]hola")).isSynced)
        XCTAssertEqual(LRCLibClient.lyrics(from: record(duration: 1, synced: nil, plain: "a\nb")), .plain(["a", "b"]))
        XCTAssertEqual(LRCLibClient.lyrics(from: record(duration: 1, synced: nil)), .notFound)
    }

    func testPercentEncodingEscapesPlusAndAmpersand() {
        XCTAssertEqual(LRCLibClient.percentEncode("A+B & C"), "A%2BB%20%26%20C")
    }

    private func named(_ title: String, _ artist: String) -> LRCLibRecord {
        let data = try! JSONSerialization.data(withJSONObject: ["trackName": title, "artistName": artist])
        return try! JSONDecoder().decode(LRCLibRecord.self, from: data)
    }

    func testMatchesFeaturedArtistAndRetitledCredit() {
        let track = TrackInfo(id: "1", title: "Sesion: Vol. 5", artist: "Productor",
                              artists: ["Productor", "Cantante"], album: nil, duration: 200)
        XCTAssertTrue(LRCLibClient.matches(named("sesion: vol. 5", "productor/cantante"), track))
        XCTAssertTrue(LRCLibClient.matches(named("Sesion: Vol. 5", "Cantante"), track))
        XCTAssertFalse(LRCLibClient.matches(named("Sesion: Vol. 5", "Otro Grupo"), track))
        XCTAssertFalse(LRCLibClient.matches(named("Otra Cancion", "Cantante"), track))
    }

    func testArtistMustBeAWholeName() {
        let track = TrackInfo(id: "1", title: "Cancion", artist: "Ed", album: nil, duration: 200)
        XCTAssertFalse(LRCLibClient.matches(named("Cancion", "Eddie Banda"), track))
    }
}

/// Serves canned LRCLIB answers in order, keyed by path and the presence of `artist_name`.
final class StubLRCLib: URLProtocol {
    nonisolated(unsafe) static var responses: [String: [(Int, String)]] = [:]
    nonisolated(unsafe) static var requests: [String] = []
    private static let lock = NSLock()

    static func key(for url: URL) -> String {
        let hasArtist = url.query?.contains("artist_name=") ?? false
        return url.lastPathComponent + (hasArtist ? "+artist" : "")
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let key = Self.key(for: url)
        Self.lock.lock()
        Self.requests.append(key)
        let (status, body) = Self.responses[key]?.isEmpty == false ? Self.responses[key]!.removeFirst() : (404, "{}")
        Self.lock.unlock()
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class LRCLibClientRequestTests: XCTestCase {
    private func client() -> LRCLibClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubLRCLib.self]
        return LRCLibClient(session: URLSession(configuration: configuration), userAgent: "tests")
    }

    private let track = TrackInfo(id: "t", title: "Sesion: Vol. 5", artist: "Productor",
                                  artists: ["Productor", "Cantante"], album: "Album", duration: 200)

    override func setUp() {
        StubLRCLib.responses = [:]
        StubLRCLib.requests = []
    }

    func testRetriesAServerError() async throws {
        StubLRCLib.responses["get+artist"] = [
            (503, ""),
            (200, #"{"duration": 200, "syncedLyrics": "[00:01.00]hola"}"#)
        ]
        let lyrics = try await client().lyrics(for: track)
        XCTAssertTrue(lyrics.isSynced)
        XCTAssertEqual(StubLRCLib.requests, ["get+artist", "get+artist"])
    }

    func testFallsBackToTitleSearchFilteredByArtist() async throws {
        StubLRCLib.responses["search+artist"] = [(200, "[]")]
        StubLRCLib.responses["search"] = [(200, """
            [{"trackName": "Sesion: Vol. 5", "artistName": "Otro Grupo", "duration": 200, "syncedLyrics": "[00:01.00]otro"},
             {"trackName": "sesion: vol. 5", "artistName": "Productor, Cantante", "duration": 199, "syncedLyrics": "[00:01.00]bien"}]
            """)]
        let lyrics = try await client().lyrics(for: track)
        XCTAssertEqual(lyrics, .synced([LyricLine(time: 1, text: "bien")]))
        XCTAssertEqual(StubLRCLib.requests, ["get+artist", "search+artist", "search"])
    }
}
