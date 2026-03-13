struct LiveDocumentVisualExtractor: DocumentVisualExtracting {
    private let pdfExtractor = PDFVisualExtractor()

    func extractVisuals(for document: ReaderDocument) throws -> [DocumentVisualAsset] {
        switch document.kind {
        case .pdf:
            return try pdfExtractor.extract(from: document.fileURL)
        case .epub, .unknown:
            return []
        }
    }

    func renderPageSnapshot(for document: ReaderDocument, pageIndex: Int) throws -> DocumentVisualAsset? {
        switch document.kind {
        case .pdf:
            return try pdfExtractor.renderPageSnapshot(from: document.fileURL, pageIndex: pageIndex)
        case .epub, .unknown:
            return nil
        }
    }
}
