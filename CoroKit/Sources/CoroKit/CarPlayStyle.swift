import Foundation

/// How the lyric fills its CarPlay slot (also used on Apple Watch). The slot's size is
/// CarPlay's call and depends on the car's screen; only the text inside it changes.
public enum CarPlayStyle: String, Codable, Hashable, CaseIterable, Sendable {
    /// The v0.1 look: current line 20 pt, next line 14 pt.
    case normal
    /// Bigger current line, next line kept small so singers still see what's coming.
    case large
    /// Only the current line, as big as three lines allow.
    case currentOnly

    public var title: String {
        switch self {
        case .normal: "Normal"
        case .large: "Grande + siguiente"
        case .currentOnly: "Solo la actual"
        }
    }

    /// Point size of the current line before `minimumScaleFactor` shrinks a long one.
    public var currentSize: Double {
        switch self {
        case .normal: 20
        case .large: 25
        case .currentOnly: 30
        }
    }

    public var currentLineLimit: Int {
        self == .currentOnly ? 3 : 2
    }

    /// Point size of the next line, or nil when it isn't shown.
    public var nextSize: Double? {
        switch self {
        case .normal: 14
        case .large: 12
        case .currentOnly: nil
        }
    }
}
