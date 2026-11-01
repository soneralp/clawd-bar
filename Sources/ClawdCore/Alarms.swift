import Foundation

/// Per-session alarms: a session with an armed alarm chimes every time it
/// stops working and hands control back to the user.
public struct Alarms: Equatable, Sendable {
    public private(set) var armed: Set<String>

    public init(armed: Set<String> = []) {
        self.armed = armed
    }

    public func isArmed(_ sessionId: String) -> Bool {
        armed.contains(sessionId)
    }

    public mutating func toggle(_ sessionId: String) {
        if armed.remove(sessionId) == nil { armed.insert(sessionId) }
    }

    /// Drops alarms for sessions that have ended.
    public mutating func retainOnly(_ aggregate: Aggregate) {
        armed.formIntersection(Self.sessionIds(in: aggregate))
    }

    /// Armed sessions that just finished or started waiting for the user.
    public func sessionsToRing(from previous: Aggregate, to next: Aggregate) -> [String] {
        Self.sessionsNeedingAttention(from: previous, to: next).filter(armed.contains)
    }

    /// Sessions that went from running to done or waiting between two snapshots.
    /// Sessions seen for the first time never count, so launching the app is silent.
    public static func sessionsNeedingAttention(from previous: Aggregate, to next: Aggregate) -> [String] {
        let previousStates = Dictionary(
            (previous.active + previous.finished).map { ($0.sessionId, $0.state) },
            uniquingKeysWith: { first, _ in first }
        )
        return (next.active + next.finished)
            .filter { previousStates[$0.sessionId] == .running && $0.state != .running }
            .map(\.sessionId)
    }

    private static func sessionIds(in aggregate: Aggregate) -> Set<String> {
        Set((aggregate.active + aggregate.finished).map(\.sessionId))
    }
}
