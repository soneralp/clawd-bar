import XCTest
@testable import ClawdCore

final class TransitionTests: XCTestCase {
    private let now: TimeInterval = 100
    private let cwd = "/Users/x/Developer/my-app"

    private func event(
        _ name: String,
        tool: String? = nil,
        notification: String? = nil,
        lastMessage: String? = nil,
        error: String? = nil,
        source: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> HookEvent {
        var json: [String: Any] = ["hook_event_name": name, "session_id": "s1", "cwd": cwd]
        json["tool_name"] = tool
        json["notification_type"] = notification
        json["last_assistant_message"] = lastMessage
        json["error_type"] = error
        json["source"] = source
        let data = try! JSONSerialization.data(withJSONObject: json)
        guard let event = HookEvent(jsonData: data) else {
            XCTFail("HookEvent failed to parse", file: file, line: line)
            fatalError()
        }
        return event
    }

    private func current(_ state: SessionState, subagents: Int = 0, since: TimeInterval = 50) -> SessionRecord {
        SessionRecord(sessionId: "s1", pid: 7, cwd: cwd, project: "my-app", state: state,
                      detail: "previous", subagents: subagents, stateSince: since, updatedAt: since)
    }

    private func apply(_ event: HookEvent, to record: SessionRecord?) -> SessionRecord? {
        Transition.apply(event, to: record, pid: 99, now: now)
    }

    func testSessionStartCreatesReadyRecord() throws {
        let record = try XCTUnwrap(apply(event("SessionStart", source: "startup"), to: nil))
        XCTAssertEqual(record.state, .done)
        XCTAssertEqual(record.detail, "Ready")
        XCTAssertEqual(record.project, "my-app")
        XCTAssertEqual(record.stateSince, now)
        XCTAssertEqual(record.updatedAt, now)
        XCTAssertEqual(record.pid, 99)
        XCTAssertEqual(record.sessionId, "s1")
    }

    func testUserPromptSubmitSetsRunning() throws {
        let record = try XCTUnwrap(apply(event("UserPromptSubmit"), to: current(.done)))
        XCTAssertEqual(record.state, .running)
        XCTAssertEqual(record.detail, "Working")
        XCTAssertEqual(record.stateSince, now)
    }

    func testPermissionRequestSetsWaitingWithTool() throws {
        let record = try XCTUnwrap(apply(event("PermissionRequest", tool: "Bash"), to: current(.running)))
        XCTAssertEqual(record.state, .waiting)
        XCTAssertEqual(record.detail, "Waiting for permission: Bash")
    }

    func testMissingToolNameStillWaits() throws {
        let record = try XCTUnwrap(apply(event("PermissionRequest"), to: current(.running)))
        XCTAssertEqual(record.state, .waiting)
        XCTAssertEqual(record.detail, "Waiting for permission")
    }

    func testAskUserQuestionSetsWaiting() throws {
        let record = try XCTUnwrap(apply(event("PreToolUse", tool: "AskUserQuestion"), to: current(.running)))
        XCTAssertEqual(record.state, .waiting)
        XCTAssertEqual(record.detail, "Asking a question")
    }

    func testOtherPreToolUseDoesNotChangeState() throws {
        let record = try XCTUnwrap(apply(event("PreToolUse", tool: "Bash"), to: current(.running)))
        XCTAssertEqual(record.state, .running)
        XCTAssertEqual(record.stateSince, 50)
        XCTAssertEqual(record.updatedAt, now)
    }

    func testNotificationPermissionPromptSetsWaiting() throws {
        let record = try XCTUnwrap(apply(event("Notification", notification: "permission_prompt"), to: current(.running)))
        XCTAssertEqual(record.state, .waiting)
        XCTAssertEqual(record.detail, "Waiting for permission")
    }

    func testNotificationPermissionPromptKeepsMoreSpecificDetail() throws {
        var waiting = current(.waiting)
        waiting.detail = "Waiting for permission: Bash"
        let record = try XCTUnwrap(apply(event("Notification", notification: "permission_prompt"), to: waiting))
        XCTAssertEqual(record.detail, "Waiting for permission: Bash")
        XCTAssertEqual(record.stateSince, 50)
    }

    func testNotificationIdlePromptMovesRunningToDone() throws {
        let record = try XCTUnwrap(apply(event("Notification", notification: "idle_prompt"), to: current(.running)))
        XCTAssertEqual(record.state, .done)
    }

    func testNotificationIdlePromptDoesNotOverrideWaiting() throws {
        let record = try XCTUnwrap(apply(event("Notification", notification: "idle_prompt"), to: current(.waiting)))
        XCTAssertEqual(record.state, .waiting)
        XCTAssertEqual(record.stateSince, 50)
    }

    func testElicitationNotificationsSetWaiting() throws {
        for type in ["elicitation_dialog", "elicitation_url_dialog", "agent_needs_input"] {
            let record = try XCTUnwrap(apply(event("Notification", notification: type), to: current(.running)))
            XCTAssertEqual(record.state, .waiting, type)
            XCTAssertEqual(record.detail, "Waiting for input", type)
        }
    }

    func testPostToolUseClearsWaiting() throws {
        for name in ["PostToolUse", "PostToolUseFailure"] {
            let record = try XCTUnwrap(apply(event(name, tool: "Bash"), to: current(.waiting)))
            XCTAssertEqual(record.state, .running, name)
            XCTAssertEqual(record.detail, "Working", name)
        }
    }

    func testSubagentStartIncrementsAndKeepsState() throws {
        let record = try XCTUnwrap(apply(event("SubagentStart"), to: current(.running)))
        XCTAssertEqual(record.subagents, 1)
        XCTAssertEqual(record.state, .running)
        XCTAssertEqual(record.stateSince, 50)
    }

    func testSubagentStopDecrementsNotBelowZero() throws {
        let once = try XCTUnwrap(apply(event("SubagentStop"), to: current(.running, subagents: 1)))
        XCTAssertEqual(once.subagents, 0)
        let again = try XCTUnwrap(apply(event("SubagentStop"), to: once))
        XCTAssertEqual(again.subagents, 0)
    }

    func testStopSetsDoneWithTruncatedMessage() throws {
        let message = "Line one\n" + String(repeating: "a", count: 100)
        let record = try XCTUnwrap(apply(event("Stop", lastMessage: message), to: current(.running, subagents: 3)))
        XCTAssertEqual(record.state, .done)
        let expectedPrefix = String(("Line one " + String(repeating: "a", count: 100)).prefix(60))
        XCTAssertEqual(record.detail, "Done · \(expectedPrefix)…")
        XCTAssertEqual(record.subagents, 0)
    }

    func testStopWithShortMessageIsNotEllipsized() throws {
        let record = try XCTUnwrap(apply(event("Stop", lastMessage: "  All set.  "), to: current(.running)))
        XCTAssertEqual(record.detail, "Done · All set.")
    }

    func testStopWithoutMessage() throws {
        let record = try XCTUnwrap(apply(event("Stop"), to: current(.running)))
        XCTAssertEqual(record.detail, "Done")
    }

    func testStopFailureSetsDoneWithError() throws {
        let record = try XCTUnwrap(apply(event("StopFailure", error: "rate_limit"), to: current(.running)))
        XCTAssertEqual(record.state, .done)
        XCTAssertEqual(record.detail, "Error: rate_limit")
    }

    func testSessionEndReturnsNil() {
        XCTAssertNil(apply(event("SessionEnd"), to: current(.running)))
    }

    func testUnknownEventLeavesRecordUnchanged() throws {
        let before = current(.waiting)
        let record = try XCTUnwrap(apply(event("FooEvent"), to: before))
        var expected = before
        expected.pid = 99
        expected.updatedAt = now
        XCTAssertEqual(record, expected)
    }

    func testUnknownEventWithNoRecordCreatesRunning() throws {
        let record = try XCTUnwrap(apply(event("PostToolUse", tool: "Read"), to: nil))
        XCTAssertEqual(record.state, .running)
        XCTAssertEqual(record.detail, "Working")
    }

    func testSameStateKeepsStateSince() throws {
        let record = try XCTUnwrap(apply(event("UserPromptSubmit"), to: current(.running)))
        XCTAssertEqual(record.stateSince, 50)
        XCTAssertEqual(record.updatedAt, now)
    }

    func testSessionStartAfterClearResetsToReady() throws {
        let record = try XCTUnwrap(apply(event("SessionStart", source: "clear"), to: current(.running, subagents: 2)))
        XCTAssertEqual(record.state, .done)
        XCTAssertEqual(record.subagents, 0)
    }

    func testSessionStartAfterCompactKeepsState() throws {
        let record = try XCTUnwrap(apply(event("SessionStart", source: "compact"), to: current(.running, subagents: 1)))
        XCTAssertEqual(record.state, .running)
        XCTAssertEqual(record.subagents, 1)
        XCTAssertEqual(record.stateSince, 50)
    }

    func testUserPromptSubmitResetsStaleSubagents() throws {
        let record = try XCTUnwrap(apply(event("UserPromptSubmit"), to: current(.running, subagents: 3)))
        XCTAssertEqual(record.subagents, 0)
    }

    func testRecordTakesThePIDItIsGiven() throws {
        let record = try XCTUnwrap(apply(event("UserPromptSubmit"), to: current(.done)))
        XCTAssertEqual(record.pid, 99)
    }

    func testProjectNameFromCwd() {
        XCTAssertEqual(Transition.projectName(fromCwd: "/Users/x/Developer/my-app", home: "/Users/x"), "my-app")
        XCTAssertEqual(Transition.projectName(fromCwd: "/Users/x/Developer/my-app/", home: "/Users/x"), "my-app")
        XCTAssertEqual(Transition.projectName(fromCwd: "/Users/x", home: "/Users/x"), "~")
        XCTAssertEqual(Transition.projectName(fromCwd: "/Users/x/", home: "/Users/x"), "~")
        XCTAssertEqual(Transition.projectName(fromCwd: "/", home: "/Users/x"), "/")
        XCTAssertEqual(Transition.projectName(fromCwd: "", home: "/Users/x"), "~")
    }

    func testHookEventReturnsNilWithoutSessionId() {
        let data = Data(#"{"hook_event_name":"Stop","cwd":"/tmp"}"#.utf8)
        XCTAssertNil(HookEvent(jsonData: data))
    }

    func testHookEventReturnsNilForGarbage() {
        XCTAssertNil(HookEvent(jsonData: Data("not json".utf8)))
        XCTAssertNil(HookEvent(jsonData: Data("[1,2]".utf8)))
    }
}
