import XCTest
@testable import ClawdCore

final class SessionStoreTests: XCTestCase {
    private var directory: URL!
    private var store: SessionStore!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("clawd-tests-\(UUID().uuidString)", isDirectory: true)
        store = SessionStore(directory: directory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func makeRecord(id: String = "abc", pid: Int32 = 42) -> SessionRecord {
        SessionRecord(
            sessionId: id, pid: pid, cwd: "/Users/x/Developer/my-app",
            project: "my-app", state: .waiting, detail: "Waiting for permission: Bash",
            subagents: 2, stateSince: 100, updatedAt: 120
        )
    }

    func testWriteThenReadRoundTrips() throws {
        let record = makeRecord()
        try store.write(record)
        XCTAssertEqual(store.read(sessionId: "abc"), record)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent("abc.json.tmp").path))
    }

    func testJSONUsesSnakeCase() throws {
        try store.write(makeRecord())
        let text = try String(contentsOf: directory.appendingPathComponent("abc.json"), encoding: .utf8)
        XCTAssertTrue(text.contains("\"session_id\""))
        XCTAssertTrue(text.contains("\"state_since\""))
        XCTAssertTrue(text.contains("\"updated_at\""))
    }

    func testLoadAllSkipsCorruptFiles() throws {
        try store.ensureDirectory()
        try store.write(makeRecord())
        try "{not json".write(to: directory.appendingPathComponent("bad.json"), atomically: true, encoding: .utf8)
        try "x".write(to: directory.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)
        XCTAssertEqual(store.loadAll().map(\.sessionId), ["abc"])
    }

    func testLoadAllOnMissingDirectoryIsEmpty() {
        XCTAssertEqual(store.loadAll(), [])
    }

    func testDeleteRemovesFile() throws {
        try store.write(makeRecord())
        store.delete(sessionId: "abc")
        XCTAssertNil(store.read(sessionId: "abc"))
    }

    func testRejectsPathTraversalSessionIds() throws {
        XCTAssertThrowsError(try store.write(makeRecord(id: "../evil")))
        XCTAssertNil(store.read(sessionId: "../evil"))
    }

    func testDeleteAlsoRemovesLockFile() throws {
        try store.withLock(sessionId: "abc") { try store.write(makeRecord()) }
        store.delete(sessionId: "abc")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("abc.lock").path))
    }

    func testConcurrentLockedIncrementsAreNotLost() throws {
        try store.write(makeRecord())
        let iterations = 200
        DispatchQueue.concurrentPerform(iterations: iterations) { _ in
            try? store.withLock(sessionId: "abc") {
                var record = store.read(sessionId: "abc")!
                record.subagents += 1
                try store.write(record)
            }
        }
        XCTAssertEqual(store.read(sessionId: "abc")?.subagents, 2 + iterations)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".tmp") }
        XCTAssertEqual(leftovers, [])
    }

    func testPruneRemovesDeadPIDs() throws {
        try store.write(makeRecord(id: "alive", pid: 1))
        try store.write(makeRecord(id: "dead", pid: 2))
        let remaining = store.prune(isAlive: { $0 == 1 })
        XCTAssertEqual(remaining.map(\.pid), [1])
        XCTAssertEqual(store.loadAll().map(\.sessionId), ["alive"])
    }
}
