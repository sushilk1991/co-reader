import Foundation

@MainActor
protocol DocumentHighlightStoring {
    func loadHighlights(for document: ReaderDocument) async throws -> [PDFDocumentHighlight]
    func upsertHighlight(_ highlight: PDFDocumentHighlight, for document: ReaderDocument) async throws
    func removeHighlight(id: UUID, for document: ReaderDocument) async throws
}
