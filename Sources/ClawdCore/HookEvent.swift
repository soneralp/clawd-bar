import Foundation

/// The subset of a Claude Code hook payload that Clawd Bar cares about.
///
/// Claude Code writes one JSON object to the hook's stdin. Unknown fields are
/// ignored so that newer Claude Code versions keep working.
public struct HookEvent: Equatable, Sendable {
    public var name: String
    public var sessionId: String
    public var cwd: String
    public var toolName: String?
    public var notificationType: String?
    public var lastAssistantMessage: String?
    public var errorType: String?
    /// `SessionStart` only: `startup`, `resume`, `clear`, `compact` or `fork`.
    public var source: String?

    public init(
        name: String,
        sessionId: String,
        cwd: String,
        toolName: String? = nil,
        notificationType: String? = nil,
        lastAssistantMessage: String? = nil,
        errorType: String? = nil,
        source: String? = nil
    ) {
        self.name = name
        self.sessionId = sessionId
        self.cwd = cwd
        self.toolName = toolName
        self.notificationType = notificationType
        self.lastAssistantMessage = lastAssistantMessage
        self.errorType = errorType
        self.source = source
    }

    /// Returns `nil` when the payload is not a JSON object or lacks
    /// `hook_event_name` or `session_id`.
    public init?(jsonData: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let name = object["hook_event_name"] as? String, !name.isEmpty,
              let sessionId = object["session_id"] as? String, !sessionId.isEmpty
        else { return nil }

        self.init(
            name: name,
            sessionId: sessionId,
            cwd: object["cwd"] as? String ?? "",
            toolName: object["tool_name"] as? String,
            notificationType: object["notification_type"] as? String,
            lastAssistantMessage: object["last_assistant_message"] as? String,
            errorType: object["error_type"] as? String,
            source: object["source"] as? String
        )
    }
}
