import AppKit
import ClawdCore
import UserNotifications

/// Optional alerts when a session starts waiting or finishes.
final class Notifier {
    static let soundName = NSSound.Name("Glass")

    /// `UNUserNotificationCenter` crashes when the process has no bundle
    /// identifier, e.g. when launched with `swift run`.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : .current()
    }

    func requestAuthorization() {
        center?.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { NSLog("Clawd Bar: notification authorization failed: \(error)") }
        }
    }

    func notify(_ row: SessionRow) {
        guard row.state != .running else { return }
        if Settings.soundEnabled {
            NSSound(named: Self.soundName)?.play()
        }
        guard Settings.notificationsEnabled, let center else { return }

        let content = UNMutableNotificationContent()
        content.title = row.state == .waiting ? "\(row.displayName) needs you" : "\(row.displayName) finished"
        content.body = row.detail
        let request = UNNotificationRequest(
            identifier: "\(row.sessionId).\(row.state.rawValue)", content: content, trigger: nil
        )
        center.add(request) { error in
            if let error { NSLog("Clawd Bar: failed to deliver notification: \(error)") }
        }
    }
}
