import Foundation

/// What the screens (app, Live Activity, CarPlay) show at a given instant.
public struct LyricsFrame: Equatable, Sendable {
    public let previous: String?
    public let current: String
    public let next: String?
    /// Index of the active line, `nil` before the first line or for unsynced lyrics.
    public let index: Int?

    public init(previous: String?, current: String, next: String?, index: Int?) {
        self.previous = previous
        self.current = current
        self.next = next
        self.index = index
    }

    public static let musicNote = "♪"
}

public enum LyricsSync {
    /// Index of the last line whose start time is `<= position` (binary search, lines sorted by time).
    public static func activeIndex(in lines: [LyricLine], at position: TimeInterval) -> Int? {
        var low = 0
        var high = lines.count - 1
        var answer: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= position {
                answer = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return answer
    }

    /// Start time of the next line after `position`, used to schedule the next refresh.
    public static func nextChange(in lines: [LyricLine], after position: TimeInterval) -> TimeInterval? {
        let next = (activeIndex(in: lines, at: position) ?? -1) + 1
        return next < lines.count ? lines[next].time : nil
    }

    public static func frame(for lyrics: Lyrics, at position: TimeInterval) -> LyricsFrame {
        switch lyrics {
        case .synced(let lines) where !lines.isEmpty:
            guard let index = activeIndex(in: lines, at: position) else {
                return LyricsFrame(previous: nil, current: LyricsFrame.musicNote,
                                   next: display(lines[0].text), index: nil)
            }
            return LyricsFrame(
                previous: index > 0 ? display(lines[index - 1].text) : nil,
                current: display(lines[index].text),
                next: index + 1 < lines.count ? display(lines[index + 1].text) : nil,
                index: index
            )
        case .plain:
            return LyricsFrame(previous: nil, current: "Letra sin sincronizar",
                               next: "Ábrela en la app", index: nil)
        case .instrumental:
            return LyricsFrame(previous: nil, current: "Instrumental \(LyricsFrame.musicNote)", next: nil, index: nil)
        case .notFound, .synced:
            return LyricsFrame(previous: nil, current: "Sin letra disponible", next: nil, index: nil)
        }
    }

    private static func display(_ text: String) -> String {
        text.isEmpty ? LyricsFrame.musicNote : text
    }
}
