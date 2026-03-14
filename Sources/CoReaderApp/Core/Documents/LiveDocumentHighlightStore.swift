import CryptoKit
import Foundation

@MainActor
struct LiveDocumentHighlightStore: DocumentHighlightStoring {
    private let baseDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseDirectory: URL) {
        self.baseDirectory = baseDirectory
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    static func liveDefault() throws -> LiveDocumentHighlightStore {
        guard let applicationSupportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw NSError(
                domain: "CoReader.DocumentHighlightStore",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to resolve Application Support directory."]
            )
        }

        let directory = applicationSupportDirectory
            .appending(path: "CoReader", directoryHint: .isDirectory)
            .appending(path: "Highlights", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return LiveDocumentHighlightStore(baseDirectory: directory)
    }

    func loadHighlights(for document: ReaderDocument) throws -> [PDFDocumentHighlight] {
        let fileURL = fileURL(for: document)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode([PDFDocumentHighlight].self, from: data)
            .sorted { $0.createdAt > $1.createdAt }
    }

    func upsertHighlight(_ highlight: PDFDocumentHighlight, for document: ReaderDocument) throws {
        var highlights = try loadHighlights(for: document)
        if let index = highlights.firstIndex(where: { $0.id == highlight.id }) {
            highlights[index] = highlight
        } else {
            highlights.insert(highlight, at: 0)
        }

        try persist(highlights, for: document)
    }

    func removeHighlight(id: UUID, for document: ReaderDocument) throws {
        let filteredHighlights = try loadHighlights(for: document)
            .filter { $0.id != id }
        try persist(filteredHighlights, for: document)
    }

    private func persist(_ highlights: [PDFDocumentHighlight], for document: ReaderDocument) throws {
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let data = try encoder.encode(highlights)
        try data.write(to: fileURL(for: document), options: .atomic)
    }

    private func fileURL(for document: ReaderDocument) -> URL {
        let digest = SHA256.hash(data: Data(document.fileURL.standardizedFileURL.path.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let filename = "\(document.title.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: "-")))-\(digest.prefix(12)).json"
        return baseDirectory.appending(path: filename)
    }
}
