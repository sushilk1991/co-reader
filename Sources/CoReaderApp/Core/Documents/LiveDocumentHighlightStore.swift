import CryptoKit
import Foundation

@MainActor
struct LiveDocumentHighlightStore: DocumentHighlightStoring {
    private let baseDirectory: URL
    private let ioQueue = DispatchQueue(label: "CoReader.HighlightStore")
    private let readData: @Sendable (URL) throws -> Data
    private let cloudStatus: @Sendable (URL) throws -> URLUbiquitousItemDownloadingStatus?
    private let requestDownload: @Sendable (URL) throws -> Void

    init(
        baseDirectory: URL,
        readData: @escaping @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) },
        cloudStatus: @escaping @Sendable (URL) throws -> URLUbiquitousItemDownloadingStatus? = {
            try $0.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus
        },
        requestDownload: @escaping @Sendable (URL) throws -> Void = {
            try FileManager.default.startDownloadingUbiquitousItem(at: $0)
        }
    ) {
        self.baseDirectory = baseDirectory
        self.readData = readData
        self.cloudStatus = cloudStatus
        self.requestDownload = requestDownload
    }

    static func liveDefault() throws -> LiveDocumentHighlightStore {
        let syncedDir = try CoReaderPaths.syncedDataDirectory
        let directory = syncedDir.appending(path: "Highlights", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return LiveDocumentHighlightStore(baseDirectory: directory)
    }

    /// Use the reading-state GCD path; serialize reads with edits so asynchronous callers cannot lose updates.
    /// `MainActor -> BlockingWork (GCD) -> serial file access -> MainActor`.
    func loadHighlights(for document: ReaderDocument) async throws -> [PDFDocumentHighlight] {
        try await BlockingWork.run { _ in
            try ioQueue.sync { try readHighlights(for: document) }
        }
    }

    /// Keep each read-modify-write together after leaving the actor.
    func upsertHighlight(_ highlight: PDFDocumentHighlight, for document: ReaderDocument) async throws {
        try await BlockingWork.run { _ in
            try ioQueue.sync {
                var highlights = try readHighlights(for: document)
                if let index = highlights.firstIndex(where: { $0.id == highlight.id }) {
                    highlights[index] = highlight
                } else {
                    highlights.insert(highlight, at: 0)
                }

                try persist(highlights, for: document)
            }
        }
    }

    /// Deletion reads the synced file too, so it uses the same serialized worker path.
    func removeHighlight(id: UUID, for document: ReaderDocument) async throws {
        try await BlockingWork.run { _ in
            try ioQueue.sync {
                let highlights = try readHighlights(for: document).filter { $0.id != id }
                try persist(highlights, for: document)
            }
        }
    }

    /// Match reading-state placeholder handling: request the download and leave the synced data untouched.
    nonisolated private func readHighlights(for document: ReaderDocument) throws -> [PDFDocumentHighlight] {
        let fileURL = fileURL(for: document)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        if try cloudStatus(fileURL) == .notDownloaded {
            try requestDownload(fileURL)
            throw HighlightStoreError.notYetDownloaded
        }

        let data = try coordinatedRead(fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([PDFDocumentHighlight].self, from: data)
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Coordinate with iCloud exactly as ReadingStateStore does before opening the bytes.
    nonisolated private func coordinatedRead(_ fileURL: URL) throws -> Data {
        var coordinationError: NSError?
        var outcome: Result<Data, any Error> = .failure(HighlightStoreError.unreadable)
        NSFileCoordinator().coordinate(readingItemAt: fileURL, options: [], error: &coordinationError) { url in
            outcome = Result { try readData(url) }
        }

        if let coordinationError {
            throw coordinationError
        }

        return try outcome.get()
    }

    /// Coordinate replacements so iCloud sees one complete highlight file, as with reading state.
    nonisolated private func persist(_ highlights: [PDFDocumentHighlight], for document: ReaderDocument) throws {
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(highlights)
        var coordinationError: NSError?
        var outcome: Result<Void, any Error> = .failure(HighlightStoreError.unreadable)
        NSFileCoordinator().coordinate(
            writingItemAt: fileURL(for: document), options: .forReplacing, error: &coordinationError
        ) { url in
            outcome = Result { try data.write(to: url, options: .atomic) }
        }

        if let coordinationError {
            throw coordinationError
        }

        try outcome.get()
    }

    nonisolated private func fileURL(for document: ReaderDocument) -> URL {
        let digest = SHA256.hash(data: Data(document.fileURL.standardizedFileURL.path.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let filename = "\(document.title.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-")))-\(digest.prefix(12)).json"
        return baseDirectory.appending(path: filename)
    }
}

/// A placeholder is unavailable, not empty: edits must not replace highlights still in iCloud.
private enum HighlightStoreError: LocalizedError {
    case notYetDownloaded
    case unreadable

    var errorDescription: String? {
        switch self {
        case .notYetDownloaded:
            "Highlights are still downloading from iCloud. Reopen the document after the download finishes."
        case .unreadable:
            "The saved highlights could not be read."
        }
    }
}
