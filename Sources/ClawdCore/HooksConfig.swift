import Foundation

/// Adds and removes Clawd Bar's entries in a Claude Code `settings.json`
/// dictionary without touching anything else.
///
/// Claude Code's format is:
/// ```json
/// { "hooks": { "Stop": [ { "matcher": "…", "hooks": [ { "type": "command", "command": "…" } ] } ] } }
/// ```
public enum HooksConfig {
    public struct Registration: Sendable {
        public var event: String
        public var matcher: String?
    }

    /// Every event the hook needs, with its matcher where one narrows it down.
    public static let events: [Registration] = [
        Registration(event: "SessionStart"),
        Registration(event: "UserPromptSubmit"),
        Registration(event: "PermissionRequest"),
        Registration(event: "PreToolUse", matcher: "AskUserQuestion"),
        Registration(event: "PostToolUse"),
        Registration(event: "PostToolUseFailure"),
        Registration(event: "Notification"),
        Registration(event: "SubagentStart"),
        Registration(event: "SubagentStop"),
        Registration(event: "Stop"),
        Registration(event: "StopFailure"),
        Registration(event: "SessionEnd"),
    ]

    public static func install(into settings: [String: Any], command: String) -> [String: Any] {
        var hooks = removingCommand(command, from: hookTable(settings))
        for registration in events {
            var entry: [String: Any] = ["hooks": [["type": "command", "command": command]]]
            entry["matcher"] = registration.matcher
            hooks[registration.event, default: []].append(entry)
        }
        var result = settings
        result["hooks"] = hooks
        return result
    }

    public static func remove(from settings: [String: Any], command: String) -> [String: Any] {
        let hooks = removingCommand(command, from: hookTable(settings))
        var result = settings
        result["hooks"] = hooks.isEmpty ? nil : hooks
        return result
    }

    /// True only when every required event carries the command.
    public static func isInstalled(_ settings: [String: Any], command: String) -> Bool {
        let hooks = hookTable(settings)
        return events.allSatisfy { registration in
            (hooks[registration.event] ?? []).contains { entryContains($0, command: command) }
        }
    }

    // MARK: - Private

    /// The `hooks` table with malformed values dropped.
    private static func hookTable(_ settings: [String: Any]) -> [String: [[String: Any]]] {
        guard let raw = settings["hooks"] as? [String: Any] else { return [:] }
        return raw.compactMapValues { value in
            guard let entries = value as? [Any] else { return nil }
            return entries.compactMap { $0 as? [String: Any] }
        }
    }

    private static func removingCommand(
        _ command: String,
        from hooks: [String: [[String: Any]]]
    ) -> [String: [[String: Any]]] {
        hooks.compactMapValues { entries in
            let kept = entries.compactMap { entry -> [String: Any]? in
                guard let handlers = entry["hooks"] as? [[String: Any]] else { return entry }
                let remaining = handlers.filter { $0["command"] as? String != command }
                if remaining.isEmpty { return nil }
                var updated = entry
                updated["hooks"] = remaining
                return updated
            }
            return kept.isEmpty ? nil : kept
        }
    }

    private static func entryContains(_ entry: [String: Any], command: String) -> Bool {
        (entry["hooks"] as? [[String: Any]] ?? []).contains { $0["command"] as? String == command }
    }
}

extension HooksConfig.Registration {
    init(event: String) { self.init(event: event, matcher: nil) }
}
