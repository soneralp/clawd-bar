import Foundation

/// Reads and writes session records in a directory, one JSON file per session.
///
/// Writers (the hook, one process per event) and the reader (the menu bar app)
/// never share a file handle: every write goes to a temporary file that is then
/// renamed over the target, so readers only ever see complete documents.
public struct SessionStore: Sendable {
    public enum StoreError: Error, Equatable {
        case invalidSessionId(String)
        case renameFailed(errno: Int32)
    }

    /// `~/.claude/clawd-bar/sessions`
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/clawd-bar/sessions", isDirectory: true)
    }

    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func write(_ record: SessionRecord) throws {
        let target = try fileURL(for: record.sessionId)
        try ensureDirectory()
        let data = try Self.encoder.encode(record)
        let temporary = target.appendingPathExtension("tmp")
        try data.write(to: temporary)
        // rename(2) atomically replaces an existing target, unlike FileManager.moveItem.
        if rename(temporary.path, target.path) != 0 {
            let code = errno
            try? FileManager.default.removeItem(at: temporary)
            throw StoreError.renameFailed(errno: code)
        }
    }

    public func read(sessionId: String) -> SessionRecord? {
        guard let url = try? fileURL(for: sessionId) else { return nil }
        return Self.decode(at: url)
    }

    public func delete(sessionId: String) {
        guard let url = try? fileURL(for: sessionId) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// All readable records, sorted by session id. Unreadable files are skipped.
    public func loadAll() -> [SessionRecord] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [] }
        return urls
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap(Self.decode(at:))
    }

    /// Deletes records whose owning process is gone and returns the rest.
    @discardableResult
    public func prune(isAlive: (Int32) -> Bool) -> [SessionRecord] {
        loadAll().filter { record in
            if isAlive(record.pid) { return true }
            delete(sessionId: record.sessionId)
            return false
        }
    }

    // MARK: - Private

    private func fileURL(for sessionId: String) throws -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard !sessionId.isEmpty,
              sessionId.unicodeScalars.allSatisfy(allowed.contains)
        else { throw StoreError.invalidSessionId(sessionId) }
        return directory.appendingPathComponent("\(sessionId).json")
    }

    private static func decode(at url: URL) -> SessionRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(SessionRecord.self, from: data)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
