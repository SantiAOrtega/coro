import Foundation

/// Cleans streaming-service track titles so lyric databases can match them.
/// "Song - Remastered 2011" → "Song", "Song (feat. X)" → "Song", "Song - From \"Film\"" → "Song".
public enum TitleNormalizer {
    /// Whole words (compared on `key`, so accents and case don't matter).
    private static let noiseKeywords = [
        "remaster", "remastered", "remasterizado", "remasterizada", "live", "version", "edit",
        "mix", "remix", "mono", "stereo", "acoustic", "acustico", "acustica", "demo", "deluxe",
        "bonus", "single", "radio", "explicit", "en vivo", "en directo", "from", "sped up",
        "slowed", "reverb", "feat", "ft", "featuring", "with"
    ]
    private static let suffixSeparators = [" - ", " – ", " — "]

    public static func clean(_ title: String) -> String {
        var result = title

        // Drop " - Remastered 2011" / " - From \"Encanto\"" style suffixes.
        for separator in suffixSeparators {
            if let range = result.range(of: separator), isNoise(String(result[range.upperBound...])) {
                result = String(result[..<range.lowerBound])
                break
            }
        }

        // Drop "(feat. X)", "[with X]", "(Live)", ... groups.
        result = removeGroups(in: result, open: "(", close: ")")
        result = removeGroups(in: result, open: "[", close: "]")

        let trimmed = result.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? title : trimmed
    }

    /// Comparison key: case, accents, apostrophes and punctuation folded away,
    /// so "We Don’t Talk About Bruno" and "we dont talk about bruno" compare equal.
    public static func key(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        var output = ""
        var pendingSpace = false
        for scalar in folded.unicodeScalars {
            if "'’‘`´".unicodeScalars.contains(scalar) { continue }
            if CharacterSet.alphanumerics.contains(scalar) {
                if pendingSpace, !output.isEmpty { output.append(" ") }
                output.unicodeScalars.append(scalar)
                pendingSpace = false
            } else {
                pendingSpace = true
            }
        }
        return output
    }

    private static func isNoise(_ text: String) -> Bool {
        let words = " \(key(text)) "
        return noiseKeywords.contains { words.contains(" \($0) ") }
    }

    private static func removeGroups(in text: String, open: Character, close: Character) -> String {
        var output = ""
        var buffer = ""
        var depth = 0
        for character in text {
            if character == open {
                depth += 1
                buffer.append(character)
            } else if character == close, depth > 0 {
                depth -= 1
                buffer.append(character)
                if depth == 0 {
                    if !isNoise(buffer) { output += buffer }
                    buffer = ""
                }
            } else if depth > 0 {
                buffer.append(character)
            } else {
                output.append(character)
            }
        }
        return output + buffer
    }
}
