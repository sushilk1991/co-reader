import Foundation

/// Where the library lives. Stored as `{"libraryRoot": "/abs/path"}` so the app and the
/// `coreader` command agree on the folder.
public struct LibraryConfig: Codable, Sendable, Equatable {
    public var libraryRoot: URL

    /// Environment variable that overrides the configured library (tests, scripts, agents).
    public static let libraryEnvironmentKey = "COREADER_LIBRARY"
    /// Environment variable that overrides the caches folder.
    public static let cachesEnvironmentKey = "COREADER_CACHES"

    public init(libraryRoot: URL) {
        self.libraryRoot = libraryRoot
    }

    /// `~/Library/Application Support/Coreader/config.json`
    public static var configURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return support.appendingPathComponent("Coreader", isDirectory: true).appendingPathComponent("config.json")
    }

    /// `~/Library/Caches/Coreader`: derived data only, safe to delete.
    public static var cachesRoot: URL {
        if let override = path(ProcessInfo.processInfo.environment[cachesEnvironmentKey]) { return override }
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches", isDirectory: true)
        return caches.appendingPathComponent("Coreader", isDirectory: true)
    }

    public static func load() -> LibraryConfig {
        load(from: configURL, environment: ProcessInfo.processInfo.environment)
    }

    /// `COREADER_LIBRARY` wins, then the config file, then `defaultRoot()`.
    /// A missing or damaged config file is not an error: the default applies.
    public static func load(
        from configURL: URL,
        environment: [String: String] = [:],
        home: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    ) -> LibraryConfig {
        if let override = path(environment[libraryEnvironmentKey]) {
            return LibraryConfig(libraryRoot: override)
        }
        if let data = try? Data(contentsOf: configURL),
           let config = try? JSONDecoder().decode(LibraryConfig.self, from: data) {
            return config
        }
        return LibraryConfig(libraryRoot: defaultRoot(home: home))
    }

    public func save() throws {
        try save(to: Self.configURL)
    }

    public func save(to configURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try AtomicFile.write(try encoder.encode(self), to: configURL)
    }

    public static func defaultRoot() -> URL {
        defaultRoot(home: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true))
    }

    /// iCloud Drive when it is on (so the library syncs), otherwise Documents.
    public static func defaultRoot(home: URL) -> URL {
        let iCloudDrive = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: iCloudDrive.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return iCloudDrive.appendingPathComponent("Coreader", isDirectory: true)
        }
        return home.appendingPathComponent("Documents/Coreader", isDirectory: true)
    }

    // The file holds a plain path, not a `file://` URL, so people can read and edit it.
    private enum CodingKeys: String, CodingKey { case libraryRoot }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let text = try container.decode(String.self, forKey: .libraryRoot)
        guard let url = Self.path(text) else {
            throw DecodingError.dataCorruptedError(forKey: .libraryRoot, in: container, debugDescription: "Empty library path")
        }
        libraryRoot = url
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(libraryRoot.path, forKey: .libraryRoot)
    }

    private static func path(_ text: String?) -> URL? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if text.hasPrefix("file://"), let url = URL(string: text) { return url.standardizedFileURL }
        return URL(fileURLWithPath: (text as NSString).expandingTildeInPath, isDirectory: true).standardizedFileURL
    }
}
