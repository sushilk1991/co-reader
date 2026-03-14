import Foundation

enum CoReaderPaths {
    private static let appName = "CoReader"

    /// Synced directory — iCloud Drive when available, Application Support otherwise.
    /// Use for user-created data: notes, highlights, reading state.
    static var syncedDataDirectory: URL {
        get throws {
            if let cloudRoot = iCloudDriveDirectory {
                let dir = cloudRoot.appending(path: appName, directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                return dir
            }

            return try localDataDirectory
        }
    }

    /// Local-only directory for caches and indexes that should not sync.
    static var localDataDirectory: URL {
        get throws {
            guard let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw CoReaderPathError.missingDirectory("Application Support")
            }

            let dir = appSupport.appending(path: appName, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        }
    }

    /// Whether the synced directory resolves to iCloud Drive.
    static var isCloudSyncEnabled: Bool {
        iCloudDriveDirectory != nil
    }

    private static var iCloudDriveDirectory: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cloudRoot = home.appending(
            path: "Library/Mobile Documents/com~apple~CloudDocs",
            directoryHint: .isDirectory
        )
        guard FileManager.default.fileExists(atPath: cloudRoot.path) else {
            return nil
        }
        return cloudRoot
    }
}

enum CoReaderPathError: LocalizedError {
    case missingDirectory(String)

    var errorDescription: String? {
        switch self {
        case .missingDirectory(let name):
            "Unable to resolve the \(name) directory."
        }
    }
}
