import ClawdCore
import Foundation

/// Applies `HooksConfig` to the user's `~/.claude/settings.json` and keeps a
/// stable symlink to the bundled `clawd-hook` binary.
enum HooksInstaller {
    enum InstallError: LocalizedError {
        case hookBinaryMissing(URL)
        case settingsUnreadable(URL, underlying: Error)
        case settingsNotJSONObject(URL)

        var errorDescription: String? {
            switch self {
            case .hookBinaryMissing(let url):
                "The clawd-hook binary was not found next to the app at \(url.path)."
            case .settingsUnreadable(let url, let underlying):
                "\(url.path) could not be read, so it was left untouched. \(underlying.localizedDescription)"
            case .settingsNotJSONObject(let url):
                "\(url.path) does not contain a JSON object, so it was left untouched."
            }
        }
    }

    /// The command written into settings.json. Claude Code runs hook commands
    /// through a shell. The guard makes the hook a silent no-op if Clawd Bar is
    /// deleted without removing its hooks, instead of an error on every event.
    static let hookCommand =
        #"f="$HOME/.claude/clawd-bar/bin/clawd-hook"; [ -x "$f" ] && exec "$f"; exit 0"#

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
        let settings = try readSettings()
        try linkHookBinary()
        try writeSettings(HooksConfig.install(into: settings, command: hookCommand))
    }

    /// Removes the settings entries. The symlink stays, because sessions that
    /// are already running keep calling the hook until they restart.
    static func remove() throws {
        let settings = try readSettings()
        try writeSettings(HooksConfig.remove(from: settings, command: hookCommand))
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

    /// The real file behind settings.json, so dotfile-managed symlinks survive.
    private static var resolvedSettingsURL: URL {
        settingsURL.resolvingSymlinksInPath()
    }

    /// An empty dictionary when the file does not exist yet; throws when it
    /// exists but cannot be parsed, so we never clobber a hand-edited file.
    private static func readSettings() throws -> [String: Any] {
        let url = resolvedSettingsURL
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data: Data
        let object: Any
        do {
            data = try Data(contentsOf: url)
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw InstallError.settingsUnreadable(url, underlying: error)
        }
        guard let settings = object as? [String: Any] else { throw InstallError.settingsNotJSONObject(url) }
        return settings
    }

    private static func writeSettings(_ settings: [String: Any]) throws {
        let fileManager = FileManager.default
        let url = resolvedSettingsURL
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var attributes: [FileAttributeKey: Any] = [:]
        if fileManager.fileExists(atPath: url.path) {
            // Keep the very first backup: it is the user's file before Clawd Bar ever touched it.
            if !fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.copyItem(at: url, to: backupURL)
            }
            if let permissions = try? fileManager.attributesOfItem(atPath: url.path)[.posixPermissions] {
                attributes[.posixPermissions] = permissions
            }
        }

        let data = try JSONSerialization.data(
            withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: url, options: .atomic)
        if !attributes.isEmpty {
            try? fileManager.setAttributes(attributes, ofItemAtPath: url.path)
        }
    }
}
