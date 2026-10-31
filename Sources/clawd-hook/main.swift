// clawd-hook: a Claude Code hook that records session state for Clawd Bar.
//
// Claude Code passes the event as JSON on stdin. This program must never
// print to stdout (Claude Code would interpret it) and must always exit 0 so
// that a Clawd Bar problem can never block a Claude session.

import ClawdCore
import Foundation

func log(_ message: String) {
    FileHandle.standardError.write(Data("clawd-hook: \(message)\n".utf8))
}

let input = FileHandle.standardInput.readDataToEndOfFile()
guard let event = HookEvent(jsonData: input) else {
    log("ignoring payload without hook_event_name/session_id")
    exit(0)
}

let store = SessionStore(directory: SessionStore.defaultDirectory)
let current = store.read(sessionId: event.sessionId)
let pid = current?.pid ?? ProcessTree.claudePID()

if let updated = Transition.apply(event, to: current, pid: pid, now: Date().timeIntervalSince1970) {
    do {
        try store.write(updated)
    } catch {
        log("failed to write session \(event.sessionId): \(error)")
    }
} else {
    store.delete(sessionId: event.sessionId)
}
exit(0)
