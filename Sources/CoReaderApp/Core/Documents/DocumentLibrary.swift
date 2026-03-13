import Foundation

struct DocumentLibrary {
    private(set) var documents: [ReaderDocument] = []

    mutating func importDocument(at url: URL) -> ReaderDocument {
        let normalizedURL = url.standardizedFileURL
        if let existing = documents.first(where: { $0.fileURL == normalizedURL }) {
            return existing
        }

        let document = ReaderDocument(fileURL: normalizedURL)
        documents.insert(document, at: 0)
        return document
    }
}
