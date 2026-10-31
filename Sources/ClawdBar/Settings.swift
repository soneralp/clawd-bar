import Foundation
import ServiceManagement

/// User preferences, persisted in `UserDefaults`. Everything is off by default.
enum Settings {
    private enum Key {
        static let notifications = "notificationsEnabled"
        static let sound = "soundEnabled"
    }

    static var notificationsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Key.notifications) }
        set { UserDefaults.standard.set(newValue, forKey: Key.notifications) }
    }

    static var soundEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Key.sound) }
        set { UserDefaults.standard.set(newValue, forKey: Key.sound) }
    }

    /// Backed by the system's login item registry rather than `UserDefaults`,
    /// so it stays truthful if the user changes it in System Settings.
    static var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
