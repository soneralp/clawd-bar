import Foundation

/// Reads the end of a transcript to learn how the latest turn ended.
public enum TranscriptInspector {
    public static let defaultTailBytes = 32 * 1024

    /// Marker Claude Code writes as a user message when the user presses Esc.
    static let interruptionMarker = "[Request interrupted by user"

    /// True when the most recent user or assistant entry is Claude Code's
    /// interruption marker, i.e. the user cancelled the turn.
    public static func lastTurnWasInterrupted(at url: URL, tailBytes: Int = defaultTailBytes) -> Bool {
        guard let data = TranscriptTail.read(url, tailBytes: tailBytes) else { return false }
        for line in data.lines.reversed() {
            guard line.range(of: userMarker) != nil || line.range(of: assistantMarker) != nil,
                  let entry = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let type = entry["type"] as? String, type == "user" || type == "assistant"
            else { continue }
            return type == "user" && isInterruption(entry["message"] as? [String: Any])
        }
        return false
    }

    private static let userMarker = Data(#""type":"user""#.utf8)
    private static let assistantMarker = Data(#""type":"assistant""#.utf8)

    private static func isInterruption(_ message: [String: Any]?) -> Bool {
        switch message?["content"] {
        case let text as String:
            return text.hasPrefix(interruptionMarker)
        case let parts as [[String: Any]]:
            return parts.contains { ($0["text"] as? String)?.hasPrefix(interruptionMarker) == true }
        default:
            return false
        }
    }
}

/// Claude Code sends no hook event when the user interrupts a turn, so a
/// session would look busy forever. This settles such sessions after the fact.
public enum Interruption {
    /// Sessions updated more recently than this are assumed to still be live.
    public static let staleAfter: TimeInterval = 10

    /// The record marked done if it is running or waiting, has been quiet for
    /// `staleAfter` seconds and its transcript ends with an interruption;
    /// otherwise `nil`.
    public static func reconcile(
        _ record: SessionRecord,
        now: TimeInterval,
        projectsDirectory: URL? = defaultProjectsDirectory
    ) -> SessionRecord? {
        guard record.state != .done,
              now - record.updatedAt >= staleAfter,
              let transcript = transcriptURL(for: record, projectsDirectory: projectsDirectory),
              TranscriptInspector.lastTurnWasInterrupted(at: transcript)
        else { return nil }

        var settled = record
        settled.state = .done
        settled.detail = "Interrupted"
        settled.subagents = 0
        settled.stateSince = now
        settled.updatedAt = now
        settled.transcriptPath = transcript.path
        return settled
    }

    /// `~/.claude/projects`, where Claude Code keeps one folder of transcripts per project.
    public static var defaultProjectsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects", isDirectory: true)
    }

    /// The recorded transcript path, or for records written before paths were
    /// recorded, `<projects>/*/<sessionId>.jsonl`.
    static func transcriptURL(for record: SessionRecord, projectsDirectory: URL?) -> URL? {
        if let path = record.transcriptPath, !path.isEmpty { return URL(fileURLWithPath: path) }
        guard let projectsDirectory,
              let projects = try? FileManager.default.contentsOfDirectory(
                  at: projectsDirectory, includingPropertiesForKeys: nil)
        else { return nil }
        let name = "\(record.sessionId).jsonl"
        return projects
            .map { $0.appendingPathComponent(name) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

extension SessionStore {
    /// Marks interrupted sessions done on disk and returns the updated set.
    /// Each rewrite happens under the session lock and re-checks the latest
    /// record, so a hook event arriving at the same time always wins.
    public func settleInterruptedSessions(
        _ records: [SessionRecord],
        now: TimeInterval,
        projectsDirectory: URL? = Interruption.defaultProjectsDirectory
    ) -> [SessionRecord] {
        records.map { record in
            guard Interruption.reconcile(record, now: now, projectsDirectory: projectsDirectory) != nil else {
                return record
            }
            let settled = try? withLock(sessionId: record.sessionId) { () -> SessionRecord? in
                guard let latest = read(sessionId: record.sessionId),
                      let settled = Interruption.reconcile(latest, now: now, projectsDirectory: projectsDirectory)
                else { return nil }
                try write(settled)
                return settled
            }
            return (settled ?? nil) ?? read(sessionId: record.sessionId) ?? record
        }
    }
}

/// The last `tailBytes` of a file, split into complete lines.
struct TranscriptTail {
    let lines: [Data.SubSequence]

    static func read(_ url: URL, tailBytes: Int) -> TranscriptTail? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let offset = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        guard (try? handle.seek(toOffset: offset)) != nil, let data = try? handle.readToEnd() else { return nil }

        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        // The first line is almost certainly cut in half when reading from mid-file.
        if offset > 0, !lines.isEmpty { lines.removeFirst() }
        return TranscriptTail(lines: lines)
    }
}
