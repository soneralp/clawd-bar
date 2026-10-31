import AppKit

/// Brings the terminal to the front. Warp has no scripting interface for
/// selecting a specific tab, so this activates the app only.
enum WarpLauncher {
    static let bundleIdentifier = "dev.warp.Warp-Stable"

    static func activate() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error { NSLog("Clawd Bar: could not activate Warp: \(error)") }
        }
    }
}
