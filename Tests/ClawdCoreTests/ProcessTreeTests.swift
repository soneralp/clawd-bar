import XCTest
@testable import ClawdCore

final class ProcessTreeTests: XCTestCase {
    func testParentOfSelfIsPositive() throws {
        let parent = try XCTUnwrap(ProcessTree.parentPID(of: getpid()))
        XCTAssertEqual(parent, getppid())
    }

    func testProcessNameOfSelfIsNotEmpty() throws {
        let name = try XCTUnwrap(ProcessTree.processName(of: getpid()))
        XCTAssertFalse(name.isEmpty)
    }

    func testIsAliveForSelfAndForDeadPID() {
        XCTAssertTrue(ProcessTree.isAlive(getpid()))
        XCTAssertFalse(ProcessTree.isAlive(9_999_999))
        XCTAssertFalse(ProcessTree.isAlive(0))
        XCTAssertFalse(ProcessTree.isAlive(-1))
    }

    func testUnknownPIDHasNoParent() {
        XCTAssertNil(ProcessTree.parentPID(of: 9_999_999))
    }

    func testFindAncestorMatchesByName() throws {
        let parentName = try XCTUnwrap(ProcessTree.processName(of: getppid()))
        XCTAssertEqual(ProcessTree.findAncestor(startingAt: getpid(), named: [parentName]), getppid())
    }

    func testFindAncestorReturnsNilWhenNoMatch() {
        XCTAssertNil(ProcessTree.findAncestor(startingAt: getpid(), named: ["definitely-not-a-process"]))
    }
}
