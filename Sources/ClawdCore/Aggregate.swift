import Foundation

/// The single state the menu bar icon shows, in increasing order of urgency.
public enum IconState: Equatable, Sendable {
    case idle, done, running, waiting
}

/// One row in the dropdown menu.
public struct SessionRow: Equatable, Sendable {
    public var sessionId: String
    /// The project name, disambiguated with a short session id when several
    /// sessions share a project.
    public var displayName: String
    public var state: SessionState
    public var detail: String
    public var timeText: String
}

/// Everything the menu bar UI needs, derived from the current set of records.
public struct Aggregate: Equatable, Sendable {
    public var icon: IconState
    /// True while at least one session is working, even if another one is
    /// waiting and the icon shows yellow. Drives the working animation.
    public var isAnyRunning: Bool
    /// Empty unless a session is waiting; then the longest-waiting session's
    /// name, plus `+N` for the others.
    public var title: String
    /// Waiting sessions (longest-waiting first), then running ones (most recently active first).
    public var active: [SessionRow]
    /// Done sessions, most recently finished first.
    public var finished: [SessionRow]

    static let shortIdLength = 4

    public init(records: [SessionRecord], now: TimeInterval) {
        let projectCounts = Dictionary(grouping: records, by: \.project).mapValues(\.count)
        func row(_ record: SessionRecord) -> SessionRow {
            Self.makeRow(record, isDuplicate: projectCounts[record.project, default: 0] > 1, now: now)
        }

        let waiting = Self.sorted(records, in: .waiting, by: \.stateSince, newestFirst: false)
        let running = Self.sorted(records, in: .running, by: \.updatedAt, newestFirst: true)
        let done = Self.sorted(records, in: .done, by: \.stateSince, newestFirst: true)

        isAnyRunning = !running.isEmpty
        active = (waiting + running).map(row)
        finished = done.map(row)

        if !waiting.isEmpty { icon = .waiting }
        else if !running.isEmpty { icon = .running }
        else if !done.isEmpty { icon = .done }
        else { icon = .idle }

        if let first = waiting.first {
            let name = row(first).displayName
            title = waiting.count > 1 ? "\(name) +\(waiting.count - 1)" : name
        } else {
            title = ""
        }
    }

    /// Records in `state`, ordered by `key`; ties are broken by session id so the
    /// menu never reshuffles between refreshes.
    private static func sorted(
        _ records: [SessionRecord],
        in state: SessionState,
        by key: KeyPath<SessionRecord, TimeInterval>,
        newestFirst: Bool
    ) -> [SessionRecord] {
        records.filter { $0.state == state }.sorted { lhs, rhs in
            let left = lhs[keyPath: key], right = rhs[keyPath: key]
            if left != right { return newestFirst ? left > right : left < right }
            return lhs.sessionId < rhs.sessionId
        }
    }

    private static func makeRow(_ record: SessionRecord, isDuplicate: Bool, now: TimeInterval) -> SessionRow {
        let name = isDuplicate
            ? "\(record.project) · \(record.sessionId.prefix(shortIdLength))"
            : record.project

        var detail = record.detail
        if record.state == .running, record.subagents > 0 {
            detail += record.subagents == 1 ? " · 1 subagent" : " · \(record.subagents) subagents"
        }

        let elapsed = now - record.stateSince
        let timeText = record.state == .done
            ? DurationFormatter.ago(elapsed)
            : DurationFormatter.elapsed(elapsed)

        return SessionRow(sessionId: record.sessionId, displayName: name,
                          state: record.state, detail: detail, timeText: timeText)
    }
}
