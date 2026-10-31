import Foundation

/// The coarse state of a Claude Code session as shown in the menu bar.
public enum SessionState: String, Codable, Sendable {
    /// Claude is working on a turn.
    case running
    /// Claude is blocked on the user: a permission prompt, a question, or an elicitation.
    case waiting
    /// Claude finished its turn and it is the user's move.
    case done
}

/// A snapshot of one session, persisted as `<sessionId>.json` by the hook
/// and read by the menu bar app.
public struct SessionRecord: Codable, Equatable, Sendable {
    public var sessionId: String
    /// PID of the Claude Code process that owns the session, used to detect
    /// sessions that disappeared without a `SessionEnd` event.
    public var pid: Int32
    public var cwd: String
    public var project: String
    public var state: SessionState
    public var detail: String
    public var subagents: Int
    /// When `state` last changed (Unix time, seconds).
    public var stateSince: TimeInterval
    /// When any hook event last touched this record (Unix time, seconds).
    public var updatedAt: TimeInterval

    public init(
        sessionId: String,
        pid: Int32,
        cwd: String,
        project: String,
        state: SessionState,
        detail: String,
        subagents: Int,
        stateSince: TimeInterval,
        updatedAt: TimeInterval
    ) {
        self.sessionId = sessionId
        self.pid = pid
        self.cwd = cwd
        self.project = project
        self.state = state
        self.detail = detail
        self.subagents = subagents
        self.stateSince = stateSince
        self.updatedAt = updatedAt
    }
}
