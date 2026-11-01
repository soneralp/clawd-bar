import Foundation

/// Reads a session's name from its Claude Code transcript (`*.jsonl`).
///
/// Claude Code appends `custom-title` entries (set with `/rename`) and
/// `ai-title` entries (generated automatically) and repeats them as the
/// conversation grows, so the tail of the file is enough. Transcripts can be
/// tens of megabytes; reading only the tail keeps the hook fast.
public enum TranscriptTitles {
    public struct Titles: Equatable, Sendable {
        public var custom: String?
        public var ai: String?

        public init(custom: String? = nil, ai: String? = nil) {
            self.custom = custom
            self.ai = ai
        }
    }

    public static let defaultTailBytes = 64 * 1024

    public static func read(from url: URL, tailBytes: Int = defaultTailBytes) -> Titles {
        guard let tail = TranscriptTail.read(url, tailBytes: tailBytes) else { return Titles() }
        let lines = tail.lines

        var titles = Titles()
        for line in lines.reversed() where titles.custom == nil || titles.ai == nil {
            guard let entry = parseTitleEntry(line) else { continue }
            if titles.custom == nil, entry.type == "custom-title" { titles.custom = entry.value }
            if titles.ai == nil, entry.type == "ai-title" { titles.ai = entry.value }
        }
        return titles
    }

    private static let customMarker = Data(#""type":"custom-title""#.utf8)
    private static let aiMarker = Data(#""type":"ai-title""#.utf8)

    private static func parseTitleEntry(_ line: Data.SubSequence) -> (type: String, value: String)? {
        // Cheap byte search first; most lines are messages, not titles.
        let key: String
        if line.range(of: customMarker) != nil {
            key = "customTitle"
        } else if line.range(of: aiMarker) != nil {
            key = "aiTitle"
        } else {
            return nil
        }
        guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              let type = object["type"] as? String,
              let value = (object[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return (type, value)
    }
}

extension SessionRecord {
    /// Updates each title only when the transcript tail contained one, so a
    /// title is never lost just because it scrolled out of the tail.
    public mutating func applyTitles(_ titles: TranscriptTitles.Titles) {
        if let custom = titles.custom { customTitle = custom }
        if let ai = titles.ai { aiTitle = ai }
    }
}
