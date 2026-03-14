import Foundation

@MainActor
struct NoOpDocumentHighlightStore: DocumentHighlightStoring {
    func loadHighlights(for document: ReaderDocument) throws -> [PDFDocumentHighlight] { [] }
    func upsertHighlight(_ highlight: PDFDocumentHighlight, for document: ReaderDocument) throws {}
    func removeHighlight(id: UUID, for document: ReaderDocument) throws {}
}
