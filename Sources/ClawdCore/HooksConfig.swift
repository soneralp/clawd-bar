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
        var hooks = removingCommand(command, from: rawHooks(settings))
        for registration in events {
            var entry: [String: Any] = ["hooks": [["type": "command", "command": command]]]
            entry["matcher"] = registration.matcher
            if var entries = hooks[registration.event] as? [Any] {
                entries.append(entry)
                hooks[registration.event] = entries
            } else if hooks[registration.event] == nil {
                hooks[registration.event] = [entry]
            }
            // Any other value is left alone: we never overwrite something we don't understand.
        }
        var result = settings
        result["hooks"] = hooks
        return result
    }

    public static func remove(from settings: [String: Any], command: String) -> [String: Any] {
        var result = settings
        guard settings["hooks"] is [String: Any] else { return result }
        let hooks = removingCommand(command, from: rawHooks(settings))
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

    private static func rawHooks(_ settings: [String: Any]) -> [String: Any] {
        settings["hooks"] as? [String: Any] ?? [:]
    }

    /// The `hooks` table as typed entries, for reading only.
    private static func hookTable(_ settings: [String: Any]) -> [String: [[String: Any]]] {
        rawHooks(settings).compactMapValues { value in
            (value as? [Any])?.compactMap { $0 as? [String: Any] }
        }
    }

    /// Removes our handlers and passes every value we don't recognize through untouched.
    private static func removingCommand(_ command: String, from hooks: [String: Any]) -> [String: Any] {
        hooks.compactMapValues { value -> Any? in
            guard let entries = value as? [Any] else { return value }
            let kept = entries.compactMap { element -> Any? in
                guard let entry = element as? [String: Any],
                      let handlers = entry["hooks"] as? [Any]
                else { return element }
                let remaining = handlers.filter { ($0 as? [String: Any])?["command"] as? String != command }
                if remaining.count == handlers.count { return entry }
                if remaining.isEmpty { return nil }
                var updated = entry
                updated["hooks"] = remaining
                return updated
            }
            return kept.isEmpty && !entries.isEmpty ? nil : kept
        }
    }

    private static func entryContains(_ entry: [String: Any], command: String) -> Bool {
        (entry["hooks"] as? [[String: Any]] ?? []).contains { $0["command"] as? String == command }
    }
}

extension HooksConfig.Registration {
    init(event: String) { self.init(event: event, matcher: nil) }
}
