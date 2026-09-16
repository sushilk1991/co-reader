import Foundation

struct ReadingStateStore: Sendable {
    let fileURL: URL

    static func live() throws -> ReadingStateStore {
        let syncedDir = try CoReaderPaths.syncedDataDirectory
        return ReadingStateStore(
            fileURL: syncedDir.appending(path: "ReadingState.json")
        )
    }

    /// Reads through `NSFileCoordinator` so iCloud never hands back a half-written
    /// file, and refuses to block on a placeholder that has not been downloaded:
    /// the download is requested and the caller gets `notYetDownloaded` instead of
    /// a launch that hangs on `Data(contentsOf:)`.
    func load() throws -> ReadingState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .empty
        }

        if try isAwaitingCloudDownload() {
            try FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
            throw ReadingStateStoreError.notYetDownloaded
        }

        let data = try coordinatedRead()
        return try JSONDecoder().decode(ReadingState.self, from: data)
    }

    func save(_ state: ReadingState) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try coordinatedWrite(data)
    }

    private func isAwaitingCloudDownload() throws -> Bool {
        let values = try fileURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        guard let status = values.ubiquitousItemDownloadingStatus else {
            return false
        }

        return status == .notDownloaded
    }

    private func coordinatedRead() throws -> Data {
        var coordinationError: NSError?
        var outcome: Result<Data, any Error> = .failure(ReadingStateStoreError.unreadable)

        NSFileCoordinator().coordinate(readingItemAt: fileURL, options: [], error: &coordinationError) { url in
            outcome = Result { try Data(contentsOf: url) }
        }

        if let coordinationError {
            throw coordinationError
        }

        return try outcome.get()
    }

    private func coordinatedWrite(_ data: Data) throws {
        var coordinationError: NSError?
        var outcome: Result<Void, any Error> = .failure(ReadingStateStoreError.unreadable)

        NSFileCoordinator().coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordinationError) { url in
            outcome = Result { try data.write(to: url, options: .atomic) }
        }

        if let coordinationError {
            throw coordinationError
        }

        try outcome.get()
    }
}

enum ReadingStateStoreError: LocalizedError, Equatable {
    case notYetDownloaded
    case unreadable

    var errorDescription: String? {
        switch self {
        case .notYetDownloaded:
            "Your last session is still downloading from iCloud. Reading positions will not be saved until the next launch."
        case .unreadable:
            "The saved reading state could not be read."
        }
    }
}
