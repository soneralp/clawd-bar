import ClawdCore
import Foundation

/// Applies `HooksConfig` to the user's `~/.claude/settings.json` and keeps a
/// stable symlink to the bundled `clawd-hook` binary.
enum HooksInstaller {
    enum InstallError: LocalizedError {
        case hookBinaryMissing(URL)
        case settingsUnreadable(URL, underlying: Error)

        var errorDescription: String? {
            switch self {
            case .hookBinaryMissing(let url):
                "The clawd-hook binary was not found next to the app at \(url.path)."
            case .settingsUnreadable(let url, let underlying):
                "\(url.path) is not valid JSON, so it was left untouched. \(underlying.localizedDescription)"
            }
        }
    }

    /// The command written into settings.json. Claude Code runs hook commands
    /// through a shell, which expands `~`. Using the symlink keeps settings.json
    /// valid if the app is moved and reinstalled.
    static let hookCommand = "~/.claude/clawd-bar/bin/clawd-hook"

    private static var claudeDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude", isDirectory: true)
    }
    private static var settingsURL: URL { claudeDirectory.appendingPathComponent("settings.json") }
    private static var backupURL: URL { claudeDirectory.appendingPathComponent("settings.json.clawd-backup") }
    private static var symlinkURL: URL { claudeDirectory.appendingPathComponent("clawd-bar/bin/clawd-hook") }

    /// The `clawd-hook` executable shipped next to the app's own executable.
    private static var bundledHookURL: URL? {
        Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("clawd-hook")
    }

    static func isInstalled() -> Bool {
        guard let settings = try? readSettings() else { return false }
        return HooksConfig.isInstalled(settings, command: hookCommand)
    }

    static func install() throws {
        try linkHookBinary()
        let settings = try readSettings()
        try writeSettings(HooksConfig.install(into: settings, command: hookCommand))
    }

    static func remove() throws {
        let settings = try readSettings()
        try writeSettings(HooksConfig.remove(from: settings, command: hookCommand))
        try? FileManager.default.removeItem(at: symlinkURL)
    }

    // MARK: - Private

    private static func linkHookBinary() throws {
        let fileManager = FileManager.default
        guard let target = bundledHookURL, fileManager.isExecutableFile(atPath: target.path) else {
            throw InstallError.hookBinaryMissing(bundledHookURL ?? URL(fileURLWithPath: "clawd-hook"))
        }
        try fileManager.createDirectory(at: symlinkURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Replace any previous link, including one left dangling by a moved app.
        try? fileManager.removeItem(at: symlinkURL)
        try fileManager.createSymbolicLink(at: symlinkURL, withDestinationURL: target)
    }

    /// An empty dictionary when the file does not exist yet; throws when it
    /// exists but cannot be parsed, so we never clobber a hand-edited file.
    private static func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        do {
            let data = try Data(contentsOf: settingsURL)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CocoaError(.propertyListReadCorrupt)
            }
            return object
        } catch {
            throw InstallError.settingsUnreadable(settingsURL, underlying: error)
        }
    }

    private static func writeSettings(_ settings: [String: Any]) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: claudeDirectory, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: settingsURL.path) {
            try? fileManager.removeItem(at: backupURL)
            try fileManager.copyItem(at: settingsURL, to: backupURL)
        }
        let data = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: settingsURL, options: .atomic)
    }
}
