import Foundation
import ServiceManagement

/// User preferences.
enum Settings {
    private enum Key {
        static let armedAlarms = "armedAlarms"
    }

    /// Session ids with an armed alarm, kept across app restarts.
    static var armedAlarms: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Key.armedAlarms) ?? []) }
        set { UserDefaults.standard.set(newValue.sorted(), forKey: Key.armedAlarms) }
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
