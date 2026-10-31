import Foundation

/// Maps a hook event onto a session record. Pure and deterministic so the whole
/// state machine can be unit tested.
public enum Transition {
    static let detailMessageLimit = 60

    /// Returns the updated record, or `nil` when the record should be deleted
    /// (the session ended).
    ///
    /// - Parameters:
    ///   - pid: PID of the owning Claude Code process; only used when creating a record.
    ///   - now: Current Unix time in seconds.
    public static func apply(
        _ event: HookEvent,
        to current: SessionRecord?,
        pid: Int32,
        now: TimeInterval
    ) -> SessionRecord? {
        if event.name == "SessionEnd" { return nil }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var record = current ?? SessionRecord(
            sessionId: event.sessionId, pid: pid, cwd: event.cwd,
            project: projectName(fromCwd: event.cwd, home: home),
            state: .running, detail: "Working", subagents: 0,
            stateSince: now, updatedAt: now
        )
        if !event.cwd.isEmpty, event.cwd != record.cwd {
            record.cwd = event.cwd
            record.project = projectName(fromCwd: event.cwd, home: home)
        }
        let previousState = current?.state

        switch event.name {
        case "SessionStart":
            record.state = .running
            record.detail = "Started"

        case "UserPromptSubmit", "PostToolUse", "PostToolUseFailure":
            record.state = .running
            record.detail = "Working"

        case "PermissionRequest":
            record.state = .waiting
            record.detail = event.toolName.map { "Waiting for permission: \($0)" } ?? "Waiting for permission"

        case "PreToolUse" where event.toolName == "AskUserQuestion":
            record.state = .waiting
            record.detail = "Asking a question"

        case "Notification":
            applyNotification(event.notificationType, to: &record)

        case "SubagentStart":
            record.subagents += 1

        case "SubagentStop":
            record.subagents = max(0, record.subagents - 1)

        case "Stop":
            record.state = .done
            record.subagents = 0
            record.detail = doneDetail(lastMessage: event.lastAssistantMessage)

        case "StopFailure":
            record.state = .done
            record.subagents = 0
            record.detail = event.errorType.map { "Error: \($0)" } ?? "Error"

        default:
            break
        }

        record.updatedAt = now
        if let previousState, previousState != record.state {
            record.stateSince = now
        }
        return record
    }

    /// The last path component of `cwd`, or `~` for the home directory.
    public static func projectName(fromCwd cwd: String, home: String) -> String {
        let trimmed = cwd.count > 1 && cwd.hasSuffix("/") ? String(cwd.dropLast()) : cwd
        let normalizedHome = home.hasSuffix("/") ? String(home.dropLast()) : home
        if trimmed.isEmpty || trimmed == normalizedHome { return "~" }
        if trimmed == "/" { return "/" }
        return (trimmed as NSString).lastPathComponent
    }

    // MARK: - Private

    private static func applyNotification(_ type: String?, to record: inout SessionRecord) {
        switch type {
        case "permission_prompt":
            // PermissionRequest usually fires first with the tool name; keep that detail.
            if record.state != .waiting {
                record.state = .waiting
                record.detail = "Waiting for permission"
            }
        case "elicitation_dialog", "elicitation_url_dialog", "agent_needs_input":
            record.state = .waiting
            record.detail = "Waiting for input"
        case "idle_prompt":
            // Never let an idle reminder hide a pending question.
            if record.state == .running {
                record.state = .done
                record.detail = "Done"
            }
        default:
            break
        }
    }

    private static func doneDetail(lastMessage: String?) -> String {
        let flattened = (lastMessage ?? "")
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard !flattened.isEmpty else { return "Done" }
        if flattened.count <= detailMessageLimit { return "Done · \(flattened)" }
        return "Done · \(flattened.prefix(detailMessageLimit))…"
    }
}
