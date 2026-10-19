import Foundation

/// Parses LRC-formatted synchronized lyrics.
///
/// Supports:
/// - `[mm:ss]`, `[mm:ss.xx]`, `[mm:ss.xxx]` and `[mm:ss:xx]` timestamps
/// - several timestamps on one line (`[00:10.00][01:20.00]text`)
/// - the `[offset:±ms]` tag (positive values make lyrics appear earlier)
/// - metadata tags (`[ar:...]`, `[ti:...]`, ...), which are ignored
public enum LRCParser {
    public static func parse(_ lrc: String) -> [LyricLine] {
        var entries: [(order: Int, time: TimeInterval, text: String)] = []
        var offset: TimeInterval = 0
        var order = 0

        for rawLine in lrc.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            var rest = Substring(rawLine.trimmingCharacters(in: .whitespaces))
            var times: [TimeInterval] = []

            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let time = parseTimestamp(tag) {
                    times.append(time)
                } else if times.isEmpty {
                    if let value = parseOffset(tag) { offset = value }
                    // Other metadata tags are skipped.
                } else {
                    // Bracketed text after the timestamps belongs to the lyric itself.
                    break
                }
                rest = rest[rest.index(after: close)...]
            }

            guard !times.isEmpty else { continue }
            let text = rest.trimmingCharacters(in: .whitespaces)
            for time in times {
                entries.append((order, time, text))
                order += 1
            }
        }

        return entries
            .sorted { $0.time != $1.time ? $0.time < $1.time : $0.order < $1.order }
            .map { LyricLine(time: max(0, $0.time - offset), text: $0.text) }
    }

    static func parseTimestamp(_ tag: Substring) -> TimeInterval? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        guard isDigits(parts[0]), let minutes = Int(parts[0]) else { return nil }

        var secondsText = String(parts[1])
        if parts.count == 3 {
            guard isDigits(parts[2]) else { return nil }
            secondsText += "." + parts[2]
        }
        guard !secondsText.isEmpty,
              secondsText.first?.isASCII == true, secondsText.first?.isNumber == true,
              secondsText.allSatisfy({ ($0.isASCII && $0.isNumber) || $0 == "." }),
              let seconds = Double(secondsText), seconds.isFinite, seconds < 60
        else { return nil }

        return Double(minutes) * 60 + seconds
    }

    static func parseOffset(_ tag: Substring) -> TimeInterval? {
        let prefix = "offset:"
        guard tag.lowercased().hasPrefix(prefix) else { return nil }
        let value = tag.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        guard let milliseconds = Int(value) else { return nil }
        return Double(milliseconds) / 1000
    }

    private static func isDigits(_ text: Substring) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber }
    }
}
