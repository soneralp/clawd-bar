import XCTest
@testable import ClawdCore

final class AlarmsTests: XCTestCase {
    private func aggregate(_ states: [String: SessionState]) -> Aggregate {
        let records = states.map { id, state in
            SessionRecord(sessionId: id, pid: 1, cwd: "/p/\(id)", project: id, state: state,
                          detail: "d", subagents: 0, stateSince: 0, updatedAt: 0)
        }
        return Aggregate(records: records, now: 10)
    }

    func testRunningToDoneAndRunningToWaitingNeedAttention() {
        let before = aggregate(["a": .running, "b": .running, "c": .running])
        let after = aggregate(["a": .done, "b": .waiting, "c": .running])
        XCTAssertEqual(Set(Alarms.sessionsNeedingAttention(from: before, to: after)), ["a", "b"])
    }

    func testOtherTransitionsDoNotNeedAttention() {
        let before = aggregate(["a": .done, "b": .waiting, "c": .waiting])
        let after = aggregate(["a": .waiting, "b": .done, "c": .running, "new": .done])
        XCTAssertEqual(Alarms.sessionsNeedingAttention(from: before, to: after), [])
    }

    func testToggleAndContains() {
        var alarms = Alarms()
        XCTAssertFalse(alarms.isArmed("a"))
        alarms.toggle("a")
        XCTAssertTrue(alarms.isArmed("a"))
        alarms.toggle("a")
        XCTAssertFalse(alarms.isArmed("a"))
    }

    func testAlarmStaysArmedAcrossTurns() {
        var alarms = Alarms(armed: ["a"])
        let rang = alarms.sessionsToRing(from: aggregate(["a": .running]), to: aggregate(["a": .done]))
        XCTAssertEqual(rang, ["a"])
        XCTAssertTrue(alarms.isArmed("a"))
    }

    func testOnlyArmedSessionsRing() {
        let alarms = Alarms(armed: ["a"])
        let rang = alarms.sessionsToRing(from: aggregate(["a": .running, "b": .running]),
                                         to: aggregate(["a": .done, "b": .done]))
        XCTAssertEqual(rang, ["a"])
    }

    func testForgetsSessionsThatNoLongerExist() {
        var alarms = Alarms(armed: ["a", "gone"])
        alarms.retainOnly(aggregate(["a": .running]))
        XCTAssertEqual(alarms.armed, ["a"])
    }
}
