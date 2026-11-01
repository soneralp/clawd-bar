import XCTest
@testable import ClawdCore

final class InterruptionTests: XCTestCase {
    private var file: URL!
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("interrupt-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        file = directory.appendingPathComponent("t.jsonl")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func write(_ lines: [String]) throws {
        try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    private let toolUse = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","id":"t1","input":{}}]}}"#
    private let toolResult = #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}"#
    private let interruptedForTool = #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}"#
    private let interruptedPlain = #"{"type":"user","message":{"role":"user","content":"[Request interrupted by user]"}}"#
    private let summary = #"{"type":"system","subtype":"away_summary","content":"..."}"#
    private let title = #"{"type":"ai-title","aiTitle":"x","sessionId":"s"}"#
    private let prompt = #"{"type":"user","message":{"role":"user","content":"do the thing"}}"#

    func testInterruptedForToolUse() throws {
        try write([toolUse, toolResult, interruptedForTool, summary, title])
        XCTAssertTrue(TranscriptInspector.lastTurnWasInterrupted(at: file))
    }

    func testInterruptedPlainStringContent() throws {
        try write([toolUse, interruptedPlain])
        XCTAssertTrue(TranscriptInspector.lastTurnWasInterrupted(at: file))
    }

    func testRunningToolIsNotInterrupted() throws {
        try write([toolResult, toolUse, title])
        XCTAssertFalse(TranscriptInspector.lastTurnWasInterrupted(at: file))
    }

    func testNewPromptAfterInterruptIsNotInterrupted() throws {
        try write([interruptedForTool, prompt])
        XCTAssertFalse(TranscriptInspector.lastTurnWasInterrupted(at: file))
    }

    func testMissingFileIsNotInterrupted() {
        XCTAssertFalse(TranscriptInspector.lastTurnWasInterrupted(at: directory.appendingPathComponent("nope.jsonl")))
    }

    private func record(_ state: SessionState, updated: TimeInterval, transcript: String?) -> SessionRecord {
        SessionRecord(sessionId: "s1", pid: 1, cwd: "/p", project: "p", state: state, detail: "Working",
                      subagents: 2, stateSince: 10, updatedAt: updated, transcriptPath: transcript)
    }

    func testReconcileMarksStaleInterruptedSessionDone() throws {
        try write([toolUse, interruptedForTool])
        let result = try XCTUnwrap(Interruption.reconcile(record(.running, updated: 100, transcript: file.path), now: 200))
        XCTAssertEqual(result.state, .done)
        XCTAssertEqual(result.detail, "Interrupted")
        XCTAssertEqual(result.subagents, 0)
        XCTAssertEqual(result.stateSince, 200)
    }

    func testReconcileAlsoAppliesToWaiting() throws {
        try write([toolUse, interruptedForTool])
        XCTAssertEqual(Interruption.reconcile(record(.waiting, updated: 100, transcript: file.path), now: 200)?.state, .done)
    }

    func testReconcileSkipsRecentlyUpdatedSessions() throws {
        try write([toolUse, interruptedForTool])
        XCTAssertNil(Interruption.reconcile(record(.running, updated: 195, transcript: file.path), now: 200))
    }

    func testFindsTranscriptBySessionIdWhenPathWasNotRecorded() throws {
        let project = directory.appendingPathComponent("projects/-Users-x-app")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try (toolUse + "\n" + interruptedForTool + "\n").write(
            to: project.appendingPathComponent("s1.jsonl"), atomically: true, encoding: .utf8)
        let result = Interruption.reconcile(record(.running, updated: 100, transcript: nil), now: 200,
                                            projectsDirectory: directory.appendingPathComponent("projects"))
        XCTAssertEqual(result?.state, .done)
        let found = try XCTUnwrap(result?.transcriptPath)
        XCTAssertEqual(URL(fileURLWithPath: found).resolvingSymlinksInPath(),
                       project.appendingPathComponent("s1.jsonl").resolvingSymlinksInPath())
    }

    func testStoreSettlesInterruptedSessionsOnDisk() throws {
        try write([toolUse, interruptedForTool])
        let store = SessionStore(directory: directory.appendingPathComponent("sessions"))
        let stale = record(.running, updated: 100, transcript: file.path)
        try store.write(stale)
        let result = store.settleInterruptedSessions([stale], now: 200, projectsDirectory: nil)
        XCTAssertEqual(result.map(\.state), [.done])
        XCTAssertEqual(store.read(sessionId: "s1")?.detail, "Interrupted")
    }

    func testStoreKeepsSessionsThatAreStillWorking() throws {
        try write([toolUse])
        let store = SessionStore(directory: directory.appendingPathComponent("sessions"))
        let busy = record(.running, updated: 100, transcript: file.path)
        try store.write(busy)
        XCTAssertEqual(store.settleInterruptedSessions([busy], now: 200, projectsDirectory: nil), [busy])
    }

    func testReconcileSkipsDoneAndUninterrupted() throws {
        try write([toolUse])
        XCTAssertNil(Interruption.reconcile(record(.running, updated: 100, transcript: file.path), now: 200))
        try write([interruptedForTool])
        XCTAssertNil(Interruption.reconcile(record(.done, updated: 100, transcript: file.path), now: 200))
        XCTAssertNil(Interruption.reconcile(record(.running, updated: 100, transcript: nil), now: 200,
                                            projectsDirectory: nil))
    }
}
