import XCTest
@testable import ClawdCore

final class AggregateTests: XCTestCase {
    private let now: TimeInterval = 10_000

    private func record(
        _ id: String,
        _ state: SessionState,
        project: String? = nil,
        detail: String = "detail",
        subagents: Int = 0,
        since: TimeInterval = 9_000,
        updated: TimeInterval? = nil,
        customTitle: String? = nil,
        aiTitle: String? = nil
    ) -> SessionRecord {
        SessionRecord(sessionId: id, pid: 1, cwd: "/p/\(project ?? id)", project: project ?? id,
                      state: state, detail: detail, subagents: subagents,
                      stateSince: since, updatedAt: updated ?? since,
                      customTitle: customTitle, aiTitle: aiTitle)
    }

    func testCustomTitleWinsOverAITitle() {
        let row = Aggregate(records: [record("a", .running, project: "app", detail: "Working",
                                             customTitle: "Release prep", aiTitle: "Fix bug")], now: now).active[0]
        XCTAssertEqual(row.displayName, "Release prep")
        XCTAssertEqual(row.subtitle, "app · Working")
    }

    func testAITitleIsUsedWithoutCustomTitle() {
        let row = Aggregate(records: [record("a", .running, project: "app", detail: "Working",
                                             aiTitle: "Fix login bug")], now: now).active[0]
        XCTAssertEqual(row.displayName, "Fix login bug")
        XCTAssertEqual(row.subtitle, "app · Working")
    }

    func testUntitledRowFallsBackToProject() {
        let row = Aggregate(records: [record("a", .running, project: "app", detail: "Working")], now: now).active[0]
        XCTAssertEqual(row.displayName, "app")
        XCTAssertEqual(row.subtitle, "Working")
    }

    func testMenuBarTitleKeepsProjectNameEvenWhenTitled() {
        let records = [record("a", .waiting, project: "my-app", customTitle: "Weekly report")]
        XCTAssertEqual(Aggregate(records: records, now: now).title, "my-app")
    }

    func testTitledDuplicatesDoNotGetIdSuffix() {
        let records = [
            record("a1b2c3", .running, project: "x", aiTitle: "Refactor"),
            record("z9y8x7", .running, project: "x"),
        ]
        let names = Set(Aggregate(records: records, now: now).active.map(\.displayName))
        XCTAssertEqual(names, ["Refactor", "x · z9y8"])
    }

    func testEmptyIsIdle() {
        let aggregate = Aggregate(records: [], now: now)
        XCTAssertEqual(aggregate.icon, .idle)
        XCTAssertEqual(aggregate.title, "")
        XCTAssertTrue(aggregate.active.isEmpty)
        XCTAssertTrue(aggregate.finished.isEmpty)
    }

    func testOnlyRunningIsRunning() {
        XCTAssertEqual(Aggregate(records: [record("a", .running)], now: now).icon, .running)
    }

    func testRunningAndDoneIsRunning() {
        XCTAssertEqual(Aggregate(records: [record("a", .done), record("b", .running)], now: now).icon, .running)
    }

    func testAllDoneIsDone() {
        XCTAssertEqual(Aggregate(records: [record("a", .done), record("b", .done)], now: now).icon, .done)
    }

    func testWaitingWinsOverEverything() {
        let records = [record("a", .done), record("b", .running), record("c", .waiting)]
        XCTAssertEqual(Aggregate(records: records, now: now).icon, .waiting)
    }

    func testIsAnyRunning() {
        XCTAssertFalse(Aggregate(records: [], now: now).isAnyRunning)
        XCTAssertFalse(Aggregate(records: [record("a", .done), record("b", .waiting)], now: now).isAnyRunning)
        XCTAssertTrue(Aggregate(records: [record("a", .running)], now: now).isAnyRunning)
        // Keeps animating while another session waits; the icon is yellow then.
        let mixed = Aggregate(records: [record("a", .running), record("b", .waiting)], now: now)
        XCTAssertTrue(mixed.isAnyRunning)
        XCTAssertEqual(mixed.icon, .waiting)
    }

    func testTitleIsEmptyWithoutWaiting() {
        XCTAssertEqual(Aggregate(records: [record("a", .running), record("b", .done)], now: now).title, "")
    }

    func testTitleShowsSingleWaitingProject() {
        let records = [record("s1", .waiting, project: "my-app"), record("s2", .running)]
        XCTAssertEqual(Aggregate(records: records, now: now).title, "my-app")
    }

    func testTitleShowsPlusCountForMultipleWaiting() {
        let records = [
            record("a", .waiting, since: 9_500),
            record("b", .waiting, since: 9_100),
            record("c", .waiting, since: 9_900),
        ]
        XCTAssertEqual(Aggregate(records: records, now: now).title, "b +2")
    }

    func testActiveOrderWaitingBeforeRunning() {
        let records = [
            record("run-old", .running, updated: 9_000),
            record("wait", .waiting),
            record("run-new", .running, updated: 9_800),
        ]
        XCTAssertEqual(Aggregate(records: records, now: now).active.map(\.sessionId), ["wait", "run-new", "run-old"])
    }

    func testFinishedSortedNewestFirst() {
        let records = [record("old", .done, since: 8_000), record("new", .done, since: 9_900)]
        XCTAssertEqual(Aggregate(records: records, now: now).finished.map(\.sessionId), ["new", "old"])
    }

    func testDuplicateProjectNamesGetSuffix() {
        let records = [
            record("a1b2c3", .running, project: "x"),
            record("z9y8x7", .done, project: "x"),
            record("solo", .running, project: "y"),
        ]
        let aggregate = Aggregate(records: records, now: now)
        let names = Dictionary(uniqueKeysWithValues: (aggregate.active + aggregate.finished).map { ($0.sessionId, $0.displayName) })
        XCTAssertEqual(names["a1b2c3"], "x · a1b2")
        XCTAssertEqual(names["z9y8x7"], "x · z9y8")
        XCTAssertEqual(names["solo"], "y")
    }

    func testRunningDetailAppendsSubagentCount() {
        let two = Aggregate(records: [record("a", .running, detail: "Working", subagents: 2)], now: now)
        XCTAssertEqual(two.active.first?.detail, "Working · 2 subagents")
        let one = Aggregate(records: [record("a", .running, detail: "Working", subagents: 1)], now: now)
        XCTAssertEqual(one.active.first?.detail, "Working · 1 subagent")
        let none = Aggregate(records: [record("a", .running, detail: "Working")], now: now)
        XCTAssertEqual(none.active.first?.detail, "Working")
    }

    func testTimeTextUsesAgoForDone() {
        let records = [record("d", .done, since: now - 480), record("r", .running, since: now - 12)]
        let aggregate = Aggregate(records: records, now: now)
        XCTAssertEqual(aggregate.finished.first?.timeText, "8m ago")
        XCTAssertEqual(aggregate.active.first?.timeText, "12s")
    }

    func testTitleUsesDisplayNameWhenDuplicated() {
        let records = [
            record("a1b2c3", .waiting, project: "x", since: 9_000),
            record("z9y8x7", .waiting, project: "x", since: 9_500),
        ]
        XCTAssertEqual(Aggregate(records: records, now: now).title, "x · a1b2 +1")
    }
}
