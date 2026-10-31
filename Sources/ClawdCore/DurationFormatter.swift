import Foundation

/// Compact duration strings for menu rows.
public enum DurationFormatter {
    /// Time spent in an active state: `"12s"`, `"4m"`, `"1h 12m"`.
    public static func elapsed(_ seconds: TimeInterval) -> String {
        let total = wholeSeconds(seconds)
        switch total {
        case ..<60: return "\(total)s"
        case ..<3600: return "\(total / 60)m"
        default: return "\(total / 3600)h \((total % 3600) / 60)m"
        }
    }

    /// Time since a session finished: `"just now"`, `"8m ago"`, `"2h ago"`.
    public static func ago(_ seconds: TimeInterval) -> String {
        let total = wholeSeconds(seconds)
        switch total {
        case ..<60: return "just now"
        case ..<3600: return "\(total / 60)m ago"
        default: return "\(total / 3600)h ago"
        }
    }

    private static func wholeSeconds(_ seconds: TimeInterval) -> Int {
        guard seconds.isFinite else { return 0 }
        return max(0, Int(seconds))
    }
}
