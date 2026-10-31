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
do {
    try store.withLock(sessionId: event.sessionId) {
        let current = store.read(sessionId: event.sessionId)
        // Re-detect the owner on start/resume, or when the stored process is gone.
        let pid: Int32
        if let stored = current?.pid, event.name != "SessionStart", ProcessTree.isAlive(stored) {
            pid = stored
        } else {
            pid = ProcessTree.claudePID()
        }

        if var updated = Transition.apply(event, to: current, pid: pid, now: Date().timeIntervalSince1970) {
            if let path = event.transcriptPath, !path.isEmpty {
                updated.applyTitles(TranscriptTitles.read(from: URL(fileURLWithPath: path)))
            }
            try store.write(updated)
        } else {
            store.delete(sessionId: event.sessionId)
        }
    }
} catch {
    log("failed to update session \(event.sessionId): \(error)")
}
exit(0)
